import AVFAudio
import Foundation

/// Reading a take off disk as samples.
///
/// Lifted out of `AudioPlayer` when `TakeExporter` needed the same thing: both
/// feed `Core`'s `WarmthRenderCore`, which takes a mono `[Float]` and a rate, so
/// there is one right answer to "what does this take sound like" and it should
/// not exist twice. `nonisolated` because the exporter reads off the main actor
/// while the player reads on it.
nonisolated enum TakeDecoder {

  /// Decode a take fully into mono ±1.0 float. Whole-file — fine for short
  /// song-idea takes (~11.5 MB/min at 48 kHz). A streaming producer is the
  /// escalation only if takes grow long.
  static func mono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat  // always deinterleaved float32
    let frames = AVAudioFrameCount(file.length)
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
      return ([], format.sampleRate)
    }
    try file.read(into: buffer)

    let channelCount = Int(format.channelCount)
    let count = Int(buffer.frameLength)
    guard let channels = buffer.floatChannelData, channelCount > 0, count > 0 else {
      return ([], format.sampleRate)
    }

    var mono = [Float](repeating: 0, count: count)
    if channelCount == 1 {
      let source = channels[0]
      for i in 0..<count { mono[i] = source[i] }
    } else {
      // Capture is mono; this downmix is defensive so an unexpected stereo file
      // still plays rather than reading one channel.
      let scale = 1 / Float(channelCount)
      for i in 0..<count {
        var sum: Float = 0
        for c in 0..<channelCount { sum += channels[c][i] }
        mono[i] = sum * scale
      }
    }
    return (mono, format.sampleRate)
  }
}
