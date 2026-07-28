/// Interleaved linear PCM, normalised to ±1.0 full scale — the value type every
/// piece of DSP in `Core` reads and returns. Named `SampleBuffer`, not
/// `AudioBuffer`, so it never collides with CoreAudio's C struct of that name if
/// a caller ever imports the framework.
///
/// This is a plain value: no `AVFoundation`, no sample-rate conversion, no
/// ownership of a file. Format bridging lives outside the shipping module.
public struct SampleBuffer: Sendable, Equatable {
  /// Frames per second, e.g. 48_000.
  public var sampleRate: Double
  /// Interleave width. 1 is mono; 2 is stereo.
  public var channelCount: Int
  /// Interleaved samples, nominally in −1.0...1.0. Length is
  /// `frameCount * channelCount`.
  public var samples: [Float]

  public init(sampleRate: Double, channelCount: Int, samples: [Float]) {
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.samples = samples
  }
}
