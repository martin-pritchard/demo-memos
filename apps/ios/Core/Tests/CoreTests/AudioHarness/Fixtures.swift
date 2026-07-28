import Core
import Foundation

/// Deterministic signal generators. Every one is a pure function of its
/// arguments — the noise uses a seeded PRNG rather than `Float.random`, so the
/// bytes committed under `Fixtures/` can be regenerated identically.
///
/// Defaults match this project's capture format (48 kHz, mono) and a 0.5 s
/// length: at 1 kHz that is exactly 500 whole cycles, so a rectangular window
/// over a tone leaks no energy into neighbouring bins.
enum Fixtures {
  static func sine(
    dbFS: Double,
    frequency: Double = 1000,
    sampleRate: Double = 48000,
    channelCount: Int = 1,
    duration: Double = 0.5
  ) -> SampleBuffer {
    let amplitude = Float(pow(10, dbFS / 20))
    return tone(
      amplitude: amplitude, dc: 0, frequency: frequency,
      sampleRate: sampleRate, channelCount: channelCount, duration: duration
    )
  }

  static func sineWithDC(
    dbFS: Double,
    dc: Float,
    frequency: Double = 1000,
    sampleRate: Double = 48000,
    channelCount: Int = 1,
    duration: Double = 0.5
  ) -> SampleBuffer {
    let amplitude = Float(pow(10, dbFS / 20))
    return tone(
      amplitude: amplitude, dc: dc, frequency: frequency,
      sampleRate: sampleRate, channelCount: channelCount, duration: duration
    )
  }

  /// Uniform noise normalised to hit `rmsDBFS` exactly. Seeded, so two calls with
  /// the same arguments produce byte-identical samples.
  static func whiteNoise(
    rmsDBFS: Double,
    sampleRate: Double = 48000,
    channelCount: Int = 1,
    duration: Double = 0.5
  ) -> SampleBuffer {
    let count = frameCount(sampleRate: sampleRate, duration: duration) * channelCount
    var generator = Xorshift64(seed: 0x1234_5678_9ABC_DEF0)
    var samples = [Float](repeating: 0, count: count)
    var sumOfSquares = 0.0
    for index in 0..<count {
      let value = generator.nextUnit()  // −1..<1
      samples[index] = Float(value)
      sumOfSquares += value * value
    }
    guard count > 0, sumOfSquares > 0 else {
      return SampleBuffer(sampleRate: sampleRate, channelCount: channelCount, samples: samples)
    }
    // Rescale so the measured RMS lands on the target rather than near it.
    let currentRMS = (sumOfSquares / Double(count)).squareRoot()
    let targetRMS = pow(10, rmsDBFS / 20)
    let gain = Float(targetRMS / currentRMS)
    for index in 0..<count { samples[index] *= gain }
    return SampleBuffer(sampleRate: sampleRate, channelCount: channelCount, samples: samples)
  }

  static func silence(
    sampleRate: Double = 48000,
    channelCount: Int = 1,
    duration: Double = 0.5
  ) -> SampleBuffer {
    let count = frameCount(sampleRate: sampleRate, duration: duration) * channelCount
    return SampleBuffer(
      sampleRate: sampleRate,
      channelCount: channelCount,
      samples: [Float](repeating: 0, count: count)
    )
  }

  /// A unit impulse: sample 0 is full scale, every other sample is silent.
  static func impulse(
    sampleRate: Double = 48000,
    channelCount: Int = 1,
    duration: Double = 0.5
  ) -> SampleBuffer {
    let count = frameCount(sampleRate: sampleRate, duration: duration) * channelCount
    var samples = [Float](repeating: 0, count: count)
    if !samples.isEmpty { samples[0] = 1.0 }
    return SampleBuffer(sampleRate: sampleRate, channelCount: channelCount, samples: samples)
  }

  /// Concatenated tone segments, each `secondsEach` long, at the given peak
  /// levels in order — the dynamic fixture a leveler needs. Every other fixture
  /// here is steady-state, and a steady signal tells you nothing about a
  /// compressor: gain reduction only shows up when the level *changes*.
  ///
  /// Each segment restarts the phase at zero and holds a whole number of cycles
  /// at the default 1 kHz / 48 kHz / 0.5 s, so the level steps land exactly on a
  /// zero crossing. The step is then a pure amplitude change with no phase
  /// discontinuity — the fixture measures the leveler, not a click it created.
  static func levelSteps(
    dbFS: [Double],
    frequency: Double = 1000,
    sampleRate: Double = 48000,
    channelCount: Int = 1,
    secondsEach: Double = 0.5
  ) -> SampleBuffer {
    var samples: [Float] = []
    for level in dbFS {
      let segment = tone(
        amplitude: Float(pow(10, level / 20)), dc: 0, frequency: frequency,
        sampleRate: sampleRate, channelCount: channelCount, duration: secondsEach
      )
      samples.append(contentsOf: segment.samples)
    }
    return SampleBuffer(sampleRate: sampleRate, channelCount: channelCount, samples: samples)
  }

  // MARK: - Internals

  private static func frameCount(sampleRate: Double, duration: Double) -> Int {
    Int((sampleRate * duration).rounded())
  }

  private static func tone(
    amplitude: Float,
    dc: Float,
    frequency: Double,
    sampleRate: Double,
    channelCount: Int,
    duration: Double
  ) -> SampleBuffer {
    let frames = frameCount(sampleRate: sampleRate, duration: duration)
    var samples = [Float](repeating: 0, count: frames * channelCount)
    let step = 2 * Double.pi * frequency / sampleRate
    for frame in 0..<frames {
      let value = dc + amplitude * Float(sin(step * Double(frame)))
      for channel in 0..<channelCount {
        samples[frame * channelCount + channel] = value
      }
    }
    return SampleBuffer(sampleRate: sampleRate, channelCount: channelCount, samples: samples)
  }
}

/// A tiny xorshift64 PRNG — reproducible across runs and platforms, which
/// `SystemRandomNumberGenerator` is not, so the committed noise fixture is
/// stable.
struct Xorshift64 {
  private var state: UInt64

  init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

  private mutating func next() -> UInt64 {
    state ^= state << 13
    state ^= state >> 7
    state ^= state << 17
    return state
  }

  /// A double uniformly in −1.0..<1.0, from the top 53 bits.
  mutating func nextUnit() -> Double {
    let bits = next() >> 11  // 53 significant bits
    let unit = Double(bits) / Double(1 << 53)  // 0..<1
    return unit * 2 - 1
  }
}
