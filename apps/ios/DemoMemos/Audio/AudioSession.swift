import AVFAudio
import Foundation

/// The only place in the app that touches `AVAudioSession` configuration.
///
/// Record and playback share one category so they cannot fight over the
/// session. If you find yourself calling `setCategory` anywhere else, extend
/// this instead.
///
/// `nonisolated` because the app target defaults to `MainActor` isolation and
/// none of this is main-actor business — `AVAudioSession` is safe to configure
/// from anywhere, and `Grant` has to cross into tests.
nonisolated enum AudioSession {

  /// What the take is asked to be. Not what it will necessarily get — see `Grant`.
  static let sampleRate: Double = 48_000
  static let channelCount: Int = 1
  static let bitDepth: Int = 24

  /// What the hardware actually granted after activation.
  ///
  /// Every "preferred" setter on `AVAudioSession` is a request; the OS grants
  /// what the current route allows. Recording without reading these back is how
  /// you ship a file that claims 48 kHz and holds a resampled 44.1.
  struct Grant: Equatable {
    var sampleRate: Double
    var inputChannels: Int
  }

  enum Failure: Error, Equatable {
    case configuration(String)
    /// The route granted something other than what was asked for.
    case unexpectedFormat(granted: Grant, wanted: Grant)
  }

  static var wanted: Grant {
    Grant(sampleRate: sampleRate, inputChannels: channelCount)
  }

  /// Configures and activates the session for capture, returning what was granted.
  ///
  /// `.measurement` is the strongest documented lever for an unprocessed input.
  /// Note what Apple actually claims for it: it suits apps that "wish to
  /// minimize the effect of system-supplied signal processing" and it "disables
  /// some dynamics processing on input and output resulting in a lower output
  /// playback level". That is *minimise*, not *disable* — there is no API that
  /// promises no AGC, no EQ and no noise suppression. Two consequences: input
  /// is quieter than `.default`, and with dynamics processing off, clipping is
  /// ours to avoid.
  @discardableResult
  static func activateForCapture() throws -> Grant {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
      try session.setPreferredSampleRate(sampleRate)
      try session.setPreferredInputNumberOfChannels(channelCount)
      // A notification banner should not end a take.
      try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
      try session.setActive(true)
    } catch {
      throw Failure.configuration(error.localizedDescription)
    }

    let granted = Grant(
      sampleRate: session.sampleRate,
      inputChannels: session.inputNumberOfChannels)
    guard granted == wanted else {
      throw Failure.unexpectedFormat(granted: granted, wanted: wanted)
    }
    return granted
  }

  /// Settings for a 48 kHz / mono / 24-bit linear PCM WAV.
  ///
  /// Keys and the permitted bit depths verified against the iOS 26.5 SDK
  /// (`AVFAudio/AVAudioSettings.h`) rather than recalled. The container is
  /// inferred from the `.wav` path extension.
  static var recorderSettings: [String: Any] {
    [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: channelCount,
      AVLinearPCMBitDepthKey: bitDepth,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]
  }
}
