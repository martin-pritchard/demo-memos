import Foundation

/// A single second-order (biquad) section, Direct Form I, with `Double` state
/// and coefficients. Internal to the warmth chain: a peaking bell and a
/// high-shelf. Coefficients follow the RBJ Audio EQ Cookbook; both shapes have
/// unity gain at DC, which is what keeps the chain from introducing any DC.
private struct Biquad {
  private var b0 = 1.0
  private var b1 = 0.0
  private var b2 = 0.0
  private var a1 = 0.0
  private var a2 = 0.0
  private var x1 = 0.0
  private var x2 = 0.0
  private var y1 = 0.0
  private var y2 = 0.0

  mutating func reset() {
    x1 = 0
    x2 = 0
    y1 = 0
    y2 = 0
  }

  mutating func process(_ input: Float) -> Float {
    let x = Double(input)
    let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    x2 = x1
    x1 = x
    y2 = y1
    y1 = y
    return Float(y)
  }

  private mutating func setIdentity() {
    b0 = 1
    b1 = 0
    b2 = 0
    a1 = 0
    a2 = 0
  }

  /// RBJ peaking EQ. Unity gain at DC and Nyquist, `gainDB` at `frequency`.
  mutating func setPeaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) {
    guard gainDB != 0 else {
      setIdentity()
      return
    }
    let a = pow(10, gainDB / 40)
    let w0 = 2 * Double.pi * frequency / sampleRate
    let cosW0 = cos(w0)
    let alpha = sin(w0) / (2 * q)
    let a0 = 1 + alpha / a
    b0 = (1 + alpha * a) / a0
    b1 = (-2 * cosW0) / a0
    b2 = (1 - alpha * a) / a0
    a1 = (-2 * cosW0) / a0
    a2 = (1 - alpha / a) / a0
  }

  /// RBJ high shelf. Unity gain at DC, `gainDB` above `frequency`.
  mutating func setHighShelf(frequency: Double, gainDB: Double, sampleRate: Double) {
    guard gainDB != 0 else {
      setIdentity()
      return
    }
    let a = pow(10, gainDB / 40)
    let w0 = 2 * Double.pi * frequency / sampleRate
    let cosW0 = cos(w0)
    let alpha = sin(w0) / 2 * sqrt(2)  // shelf slope S = 1
    let twoSqrtAAlpha = 2 * sqrt(a) * alpha
    let a0 = (a + 1) - (a - 1) * cosW0 + twoSqrtAAlpha
    b0 = a * ((a + 1) + (a - 1) * cosW0 + twoSqrtAAlpha) / a0
    b1 = -2 * a * ((a - 1) + (a + 1) * cosW0) / a0
    b2 = a * ((a + 1) + (a - 1) * cosW0 - twoSqrtAAlpha) / a0
    a1 = 2 * ((a - 1) - (a + 1) * cosW0) / a0
    a2 = ((a + 1) - (a - 1) * cosW0 - twoSqrtAAlpha) / a0
  }
}

/// The warmth DSP as an allocation-free, in-place kernel over one mono channel
/// — the seam Unit 2 (#24) hosts inside a realtime render block. Setup (filter
/// state, coefficients) is preallocated in `init`/`update`; `process` only reads
/// and writes the caller's buffer and calls `libm` — no allocation, no locks, no
/// concurrency, per `docs/PRINCIPLES.ios.md` #1.
///
/// The chain, in order, and why:
/// 1. **head-bump bell** — woody low-mid body;
/// 2. **high-shelf cut** — softens the top *before* saturation, both for the
///    tape voicing and so it does not attenuate the harmonics the saturator is
///    about to add;
/// 3. **character saturation** `tanh(drive · x) / drive` — unity small-signal
///    gain, odd (no DC), harmonics rising with drive;
/// 4. **make-up** — level-match;
/// 5. **ceiling** `A · tanh(x / A)` — odd, and bounded by `A < 1` for *any*
///    input, so the output can never clip whatever the upstream EQ did.
public struct WarmthKernel {
  private let sampleRate: Double
  private var headBump = Biquad()
  private var highShelf = Biquad()
  private var drive = 0.0
  private var makeup: Float = 1
  private var ceiling: Float = 1

  public init(parameters: WarmthParameters, sampleRate: Double) {
    self.sampleRate = sampleRate
    update(parameters)
  }

  /// Recompute coefficients for new parameters. Safe to call between render
  /// blocks; allocation-free. Filter state is preserved so a dial move does not
  /// click (Unit 2 smooths the parameters into this).
  public mutating func update(_ parameters: WarmthParameters) {
    headBump.setPeaking(
      frequency: parameters.headBumpFrequency,
      gainDB: parameters.headBumpGainDB,
      q: parameters.headBumpQ,
      sampleRate: sampleRate)
    highShelf.setHighShelf(
      frequency: parameters.highShelfFrequency,
      gainDB: parameters.highShelfGainDB,
      sampleRate: sampleRate)
    drive = parameters.drive
    makeup = Float(pow(10, parameters.makeupGainDB / 20))
    ceiling = Float(parameters.ceiling)
  }

  /// Clear filter memory. Call when starting a fresh signal.
  public mutating func reset() {
    headBump.reset()
    highShelf.reset()
  }

  /// Process one mono channel in place. Allocation-free.
  public mutating func process(_ samples: UnsafeMutableBufferPointer<Float>) {
    let drive = self.drive
    let makeup = self.makeup
    let ceiling = self.ceiling
    for i in samples.indices {
      var x = samples[i]
      x = headBump.process(x)
      x = highShelf.process(x)
      if drive > 0 {
        x = Float(tanh(drive * Double(x)) / drive)
      }
      x *= makeup
      x = ceiling * Float(tanh(Double(x) / Double(ceiling)))
      samples[i] = x
    }
  }
}

/// The warmth processor as an offline `AudioProcessor`: one buffer in, one out,
/// allocating. This is the form the guardrail tests measure; Unit 2 (#24) uses
/// `WarmthKernel` directly for realtime playback. Same DSP either way.
///
/// `warmth == 0` short-circuits to the input untouched — a true bypass that
/// null-tests to `−∞`, not merely neutral settings.
public struct WarmthProcessor: AudioProcessor {
  public var warmth: Double

  public init(warmth: Double) {
    self.warmth = warmth
  }

  public func process(_ buffer: SampleBuffer) -> SampleBuffer {
    let w = min(max(warmth, 0), 1)
    guard w > 0 else { return buffer }

    let parameters = warmthParameters(w)
    let channelCount = max(buffer.channelCount, 1)
    var samples = buffer.samples

    if channelCount == 1 {
      var kernel = WarmthKernel(parameters: parameters, sampleRate: buffer.sampleRate)
      samples.withUnsafeMutableBufferPointer { kernel.process($0) }
    } else {
      // Interleaved: process each channel with its own filter state.
      let frameCount = samples.count / channelCount
      var channel = [Float](repeating: 0, count: frameCount)
      for offset in 0..<channelCount {
        for frame in 0..<frameCount {
          channel[frame] = samples[frame * channelCount + offset]
        }
        var kernel = WarmthKernel(parameters: parameters, sampleRate: buffer.sampleRate)
        channel.withUnsafeMutableBufferPointer { kernel.process($0) }
        for frame in 0..<frameCount {
          samples[frame * channelCount + offset] = channel[frame]
        }
      }
    }

    return SampleBuffer(
      sampleRate: buffer.sampleRate,
      channelCount: buffer.channelCount,
      samples: samples)
  }
}
