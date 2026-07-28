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

/// A gentle feed-forward leveler (#32): slow program levelling, as opposed to the
/// fast harmonic waveshaping `drive` already does. It pulls loud passages down
/// and lifts quiet detail — sustain, finger noise, breath, the room — which is
/// what reads as intimacy on the reference records.
///
/// Internal to the warmth chain, and hand-written rather than Apple's
/// `AUDynamicsProcessor` for two structural reasons (#32): an `AVAudioUnit` is a
/// graph *node*, so it could only sit after the whole source node — i.e. after
/// `ceiling`, inverting "peak control last" — and an AU stage would be invisible
/// to the offline guardrails that measure the loudness risk this stage creates.
///
/// Peak-domain detector, no lookahead: lookahead means latency and a delay line,
/// and neither is worth it for a stage tuned to be inaudible. `process` is
/// branch-light, allocation-free and `libm`-only, per `docs/PRINCIPLES.ios.md` #1.
private struct Leveler {
  private var attackCoefficient: Float = 1
  private var releaseCoefficient: Float = 1
  /// Envelope level at which gain reduction begins, linear.
  private var threshold: Float = 1
  /// `1/ratio − 1`, the exponent that turns an over-threshold *ratio* straight
  /// into a linear gain — so the whole gain computation is one `powf`, with no
  /// logs and no dB round trip in the per-sample path.
  private var exponent: Float = 0
  private var makeup: Float = 1

  /// The only state that survives a sample. Deliberately *not* cleared by
  /// `update`: a dial move must not restart the envelope, or every nudge clicks.
  private var envelope: Float = 0

  /// Below this the envelope snaps to zero. Long silences otherwise decay toward
  /// denormals, which are punishingly slow on some cores — a realtime-thread
  /// hazard that never shows up in an offline test.
  private let denormalFloor: Float = 1e-12

  mutating func update(_ parameters: WarmthParameters, sampleRate: Double) {
    attackCoefficient = Self.coefficient(seconds: parameters.levelerAttack, sampleRate: sampleRate)
    releaseCoefficient = Self.coefficient(
      seconds: parameters.levelerRelease, sampleRate: sampleRate)
    threshold = Float(pow(10, parameters.levelerThresholdDB / 20))
    exponent = Float(1 / parameters.levelerRatio - 1)
    makeup = Float(pow(10, parameters.levelerMakeupGainDB / 20))
  }

  mutating func reset() {
    envelope = 0
  }

  /// One sample in, one out. At `ratio == 1` the exponent is `0` and the make-up
  /// is `1`, so `powf(_, 0) == 1` makes this an *exact* identity — the stage
  /// bypasses itself at the bottom of the dial without needing a branch to do it.
  mutating func process(_ x: Float) -> Float {
    let magnitude = abs(x)
    // Asymmetric one-pole: fast to catch a rise, slow to let go — the asymmetry
    // is what makes it ride the performance instead of pumping on it.
    let coefficient = magnitude > envelope ? attackCoefficient : releaseCoefficient
    envelope += (magnitude - envelope) * coefficient
    if envelope < denormalFloor { envelope = 0 }

    guard envelope > threshold else { return x * makeup }
    return x * powf(envelope / threshold, exponent) * makeup
  }

  /// One-pole time constant → per-sample coefficient.
  private static func coefficient(seconds: Double, sampleRate: Double) -> Float {
    guard seconds > 0, sampleRate > 0 else { return 1 }
    return Float(1 - exp(-1 / (seconds * sampleRate)))
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
/// 4. **make-up** — level-match, restoring what the saturator took off;
/// 5. **leveler** — slow program levelling (#32). After the EQ so it reacts to
///    the level the EQ actually set, and after the saturator so it sees rounded
///    transients rather than raw spikes.
///
///    It sits after the make-up, not before, and that ordering is load-bearing:
///    the leveler's net gain works out to `(pivot − input)·(1 − 1/ratio)`, so it
///    is neutral only when its input sits *at* `levelerPivotDBFS`. Behind the
///    make-up it would see the saturator's ~0.8 dB loss instead, and compensate
///    for it a second time — the same loss corrected twice, which put a −12 dBFS
///    tone 1.3 dB up and broke the ±1 dB loudness guardrail. A static
///    level-changer belongs ahead of the stage that reacts to level;
/// 6. **ceiling** `A · tanh(x / A)` — odd, and bounded by `A < 1` for *any*
///    input, so the output can never clip whatever the upstream EQ did. Last, so
///    nothing downstream can break the guarantee.
public struct WarmthKernel {
  private let sampleRate: Double
  private var headBump = Biquad()
  private var highShelf = Biquad()
  private var drive = 0.0
  private var leveler = Leveler()
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
    leveler.update(parameters, sampleRate: sampleRate)
    makeup = Float(pow(10, parameters.makeupGainDB / 20))
    ceiling = Float(parameters.ceiling)
  }

  /// Clear filter and envelope memory. Call when starting a fresh signal, so a
  /// new take does not begin part-way into the last one's gain reduction.
  public mutating func reset() {
    headBump.reset()
    highShelf.reset()
    leveler.reset()
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
      x = leveler.process(x)
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
