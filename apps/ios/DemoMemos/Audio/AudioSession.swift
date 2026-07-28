import AVFAudio
import Foundation

/// The only place in the app that touches `AVAudioSession` configuration.
///
/// Capture and playback each activate their own configuration through here —
/// they want opposite things, so sharing one category means one of them loses.
/// If you find yourself calling `setCategory` anywhere else, extend this
/// instead.
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

    // Each step is named so a failure says which call broke rather than leaving
    // a bare OSStatus to guess at.
    func step(_ name: String, _ work: () throws -> Void) throws {
      do {
        try work()
      } catch {
        throw Failure.configuration("\(name): \(error.localizedDescription)")
      }
    }

    try step("setCategory") {
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
    }

    // Activate *before* asking for a format. Both preferred setters below apply
    // "to the current route", and on a device there is no route until the
    // session is active — calling them first returns OSStatus -50 (paramErr).
    // The simulator tolerates the wrong order, so this only shows up on hardware.
    try step("setActive") { try session.setActive(true) }

    // A notification banner should not end a take.
    try? session.setPrefersNoInterruptionsFromSystemAlerts(true)

    try step("setPreferredSampleRate") { try session.setPreferredSampleRate(sampleRate) }

    // Asking for more channels than the route has is also -50, so check first.
    if session.maximumInputNumberOfChannels >= channelCount {
      try step("setPreferredInputNumberOfChannels") {
        try session.setPreferredInputNumberOfChannels(channelCount)
      }
    }

    let granted = Grant(
      sampleRate: session.sampleRate,
      inputChannels: session.inputNumberOfChannels)

    // Only the sample rate is a hard failure. A rate we did not ask for means
    // the capture path resamples, which is the thing `.measurement` and 48 kHz
    // exist to avoid. The route's channel count is not the file's channel
    // count — `AVNumberOfChannelsKey` makes the take mono whatever the hardware
    // exposes — so refusing to record because a mic reports two channels would
    // block capture to enforce something already guaranteed elsewhere.
    guard granted.sampleRate == sampleRate else {
      throw Failure.unexpectedFormat(granted: granted, wanted: wanted)
    }
    return granted
  }

  /// Configures and activates the session for playback.
  ///
  /// Deliberately *not* `.measurement`. That mode "disables some dynamics
  /// processing on input and output resulting in a lower output playback level"
  /// — a price worth paying to capture a raw signal, and pure loss when playing
  /// one back. Capture and playback want opposite things here, which is why
  /// this is two functions rather than one shared category.
  ///
  /// `.playback` is also what makes AirPods work. Under `.playAndRecord`,
  /// `allowBluetoothA2DP` "defaults to false", so a paired Bluetooth device
  /// never appears as an output route at all; under output-only categories it
  /// is "always implicitly true". `.defaultToSpeaker` compounded it by forcing
  /// the built-in speaker.
  static func activateForPlayback() throws {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      throw Failure.configuration("playback session: \(error.localizedDescription)")
    }
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
