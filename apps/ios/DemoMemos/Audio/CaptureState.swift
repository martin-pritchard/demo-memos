import Core
import Foundation
import Observation

/// The screen's view model, and nothing more.
///
/// Every transition lives in `CaptureMachine.next` over in `Core`; this holds the
/// current state, exposes it in the shape SwiftUI wants, turns taps and seam
/// callbacks into events, and performs the effects the machine asks for. It
/// decides nothing — which is what lets the whole transport be tested with
/// `swift test`, no simulator (see `CaptureMachineTests`).
///
/// What is left here is exactly the part that cannot be pure: building take URLs
/// from a folder and a clock, driving the recorder and player, and wording
/// notices.
@MainActor
@Observable
final class CaptureState {

  private var machine: CaptureMachine.State

  private let recorder: any Recording
  private let player: any Playing
  private let folder: URL
  private let now: () -> Date

  // MARK: - What the screen reads

  var mode: CaptureMode { machine.mode }
  var permission: MicrophonePermission { machine.permission }
  var latestTake: URL? { machine.latestTake }

  /// One line of plain text explaining whatever just happened. Nil when there is
  /// nothing to say.
  var notice: String? { machine.notice?.wording }

  var canRecord: Bool { machine.canRecord }
  var canPlay: Bool { machine.canPlay }
  var isDenied: Bool { machine.isDenied }

  /// The Enhance dial, `0...1`. In-memory for the session — resets on relaunch,
  /// no persistence (#21 non-goal). Writing it is an event like any other, so the
  /// clamp and the forward to the player happen in one place: the machine clamps,
  /// and `.setWarmth` carries the clamped value. The `Slider` binds this over
  /// `0...1`; an out-of-range write still reaches the DSP in range.
  var warmth: Double {
    get { machine.warmth }
    set { send(.warmthChanged(newValue)) }
  }

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
    self.now = now
    self.machine = CaptureMachine.State(
      permission: recorder.permission,
      latestTake: latestTake)

    recorder.onStop = { [weak self] reason, url in
      self?.send(.recordingStopped(reason, url))
    }
    player.onFinish = { [weak self] in
      self?.send(.playbackFinished)
    }
  }

  // MARK: - Events in

  /// Async only because the permission prompt is. Everything else the tap sets
  /// off is synchronous, so the suspension stays confined to the one place it
  /// genuinely exists — see `send(_:)`.
  func recordTapped() async {
    guard send(.recordTapped) == .awaitingPermission else { return }
    // Asked on the first tap on record — the moment the user has shown they want
    // it — never on launch.
    send(.permissionResolved(await recorder.requestPermission()))
  }

  func playTapped() {
    send(.playTapped)
  }

  // MARK: - Reducing

  /// Feed one event through the machine, adopt the new state, and perform what it
  /// asks for. Returns the resulting mode so `recordTapped()` can tell whether a
  /// prompt is owed without re-deriving that decision here.
  ///
  /// Synchronous on purpose. `.requestPermission` is the only effect that has to
  /// await, and it is handled by the one caller that can — so the effects below
  /// stay a plain switch, and a callback arriving from `AVAudioRecorder` needs no
  /// `Task` to be applied.
  @discardableResult
  private func send(_ event: CaptureMachine.Event) -> CaptureMode {
    let (next, effects) = CaptureMachine.next(machine, event)
    machine = next
    for effect in effects { perform(effect) }
    return machine.mode
  }

  private func perform(_ effect: CaptureMachine.Effect) {
    switch effect {
    case .requestPermission:
      // Owed to `recordTapped()`, the only caller that can await it. Nothing to
      // do here; the mode `send` returns is what tells it.
      break

    case .startRecording:
      // The take's destination is a folder and a clock the machine deliberately
      // does not know about, so the URL is minted here.
      do {
        try recorder.start(to: RecordingsFolder.newTakeURL(in: folder, at: now()))
        send(.recordingStarted)
      } catch {
        send(.recordingFailed(.describing(error)))
      }

    case .stopRecording:
      recorder.stop()

    case .startPlayback(let url):
      do {
        try player.play(url)
      } catch {
        send(.playbackFailed(.describing(error)))
      }

    case .stopPlayback:
      player.stop()

    case .setWarmth(let value):
      player.setWarmth(value)
    }
  }
}
