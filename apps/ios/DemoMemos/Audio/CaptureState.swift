import Foundation
import Observation

/// The state machine the screen binds to. Imports no UI framework, so all of it
/// is testable in `DemoMemosTests` with no simulator audio and no files.
@MainActor
@Observable
final class CaptureState {

  enum Mode: Equatable {
    case idle
    case recording
    case playing
  }

  private(set) var mode: Mode = .idle
  private(set) var permission: MicrophonePermission
  private(set) var latestTake: URL?
  /// One line of plain text explaining whatever just happened. Nil when there
  /// is nothing to say.
  private(set) var notice: String?

  /// The Enhance dial, `0...1`. In-memory for the session — resets on relaunch,
  /// no persistence (#21 non-goal). Every change is forwarded to the player, so
  /// the dial moves the take live during playback and is remembered for the next
  /// one. `0` is a true bypass. The `Slider` binds this over `0...1`; the player
  /// clamps too, so an out-of-range write still reaches the DSP in range.
  var warmth: Double = 0 {
    didSet { player.setWarmth(warmth) }
  }

  private let recorder: any Recording
  private let player: any Playing
  private let folder: URL
  private let now: () -> Date

  var canRecord: Bool { permission != .denied }
  var canPlay: Bool { latestTake != nil && mode != .recording }
  var isDenied: Bool { permission == .denied }

  init(
    recorder: any Recording,
    player: any Playing,
    folder: URL,
    latestTake: URL? = nil,
    now: @escaping () -> Date = Date.init
  ) {
    self.recorder = recorder
    self.player = player
    self.folder = folder
    self.latestTake = latestTake
    self.now = now
    self.permission = recorder.permission

    recorder.onStop = { [weak self] reason, url in
      guard let self else { return }
      self.mode = .idle
      self.latestTake = url
      self.notice = Self.notice(for: reason)
    }
    player.onFinish = { [weak self] in
      guard let self, self.mode == .playing else { return }
      self.mode = .idle
    }
  }

  // MARK: - Events in

  func recordTapped() async {
    notice = nil

    if mode == .recording {
      recorder.stop()
      return
    }
    if mode == .playing {
      player.stop()
      mode = .idle
    }

    // Asked on the first tap on record — the moment the user has shown they
    // want it — never on launch.
    var permission = recorder.permission
    if permission == .undetermined {
      permission = await recorder.requestPermission()
    }
    self.permission = permission

    guard permission == .granted else {
      notice = "Microphone access is off. Turn it on in Settings to record."
      return
    }

    do {
      try recorder.start(to: RecordingsFolder.newTakeURL(in: folder, at: now()))
      mode = .recording
    } catch {
      notice = Self.describe(error)
    }
  }

  func playTapped() {
    notice = nil

    if mode == .playing {
      player.stop()
      mode = .idle
      return
    }
    guard mode == .idle, let latestTake else { return }

    do {
      try player.play(latestTake)
      mode = .playing
    } catch {
      notice = Self.describe(error)
    }
  }

  // MARK: - Wording

  private static func notice(for reason: StopReason) -> String? {
    switch reason {
    case .user:
      nil
    case .interrupted:
      "Interrupted. Your take was saved."
    case .routeLost:
      "Audio device disconnected. Your take was saved."
    case .mediaServicesReset:
      "The audio system restarted. Your take was saved."
    case .failed(let message):
      "Recording stopped: \(message). Your take was saved."
    }
  }

  /// A format we did not ask for is surfaced, never swallowed — recording a
  /// resampled 44.1 while claiming 48 kHz is the outcome the read-back exists
  /// to prevent.
  private static func describe(_ error: any Error) -> String {
    guard let failure = error as? AudioSession.Failure else {
      return error.localizedDescription
    }
    switch failure {
    case .configuration(let message):
      return "Could not start recording: \(message)"
    case .unexpectedFormat(let granted, let wanted):
      return """
        This route runs at \(Int(granted.sampleRate)) Hz, but takes are \
        \(Int(wanted.sampleRate)) Hz. Recording would resample. \
        Not recording rather than saving something else.
        """
    }
  }
}
