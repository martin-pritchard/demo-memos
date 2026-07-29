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

  /// The same thing as a domain fact rather than a sentence. The screen routes
  /// it to a form (`TakeNotice`); the flattened `notice` above stays for callers
  /// that only want the words.
  var captureNotice: CaptureNotice? { machine.notice }

  var canRecord: Bool { machine.canRecord }
  var canPlay: Bool { machine.canPlay }
  var isDenied: Bool { machine.isDenied }

  // MARK: - The playhead

  /// Where the loaded take is up to, in seconds. `0` when nothing is loaded.
  var position: TimeInterval { player.position }

  /// The loaded take's length, `0` if none. Only known once a take has been
  /// decoded — a take that has just been recorded has not been.
  var duration: TimeInterval { player.duration }

  /// Move the playhead. Applied live if playing, remembered for the next `play`
  /// otherwise, so scrubbing a paused take is not lost.
  ///
  /// Not an event: the machine decides *transitions*, and a scrub is not one —
  /// it changes neither the mode, the take, nor what a tap would do next.
  func scrub(to position: TimeInterval) {
    player.seek(to: position)
  }

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
    warmth: Double = 0,
    now: @escaping () -> Date = Date.init
  ) {
    self.recorder = recorder
    self.player = player
    self.folder = folder
    self.now = now
    self.machine = CaptureMachine.State(
      permission: recorder.permission,
      latestTake: latestTake,
      warmth: warmth)
    // The dial's starting value has to reach the player too, or the first take
    // plays dry while the screen says otherwise.
    player.setWarmth(warmth)

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
    // The *effect*, not the resulting mode: a tap that arrives while the prompt
    // is already up leaves the mode at `.awaitingPermission` too, so reading the
    // mode here would prompt a second time. `.requestPermission` is emitted
    // once, by the tap that actually raised it.
    guard send(.recordTapped).contains(.requestPermission) else { return }
    // Asked on the first tap on record — the moment the user has shown they want
    // it — never on launch.
    send(.permissionResolved(await recorder.requestPermission()))
  }

  func playTapped() {
    send(.playTapped)
  }

  // MARK: - Reducing

  /// Feed one event through the machine, adopt the new state, and perform what it
  /// asks for. Returns the effects so `recordTapped()` can tell whether a prompt
  /// is owed without re-deriving that decision here.
  ///
  /// Synchronous on purpose. `.requestPermission` is the only effect that has to
  /// await, and it is handled by the one caller that can — so the effects below
  /// stay a plain switch, and a callback arriving from `AVAudioRecorder` needs no
  /// `Task` to be applied.
  @discardableResult
  private func send(_ event: CaptureMachine.Event) -> [CaptureMachine.Effect] {
    let (next, effects) = CaptureMachine.next(machine, event)
    machine = next
    for effect in effects { perform(effect) }
    return effects
  }

  private func perform(_ effect: CaptureMachine.Effect) {
    switch effect {
    case .requestPermission:
      // Owed to `recordTapped()`, the only caller that can await it. Nothing to
      // do here; its presence in what `send` returns is what tells it.
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
