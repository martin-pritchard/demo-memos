import Core
import Foundation
import SwiftUI

/// The join between the designed `TakeScreen` and the real recorder and player.
///
/// `TakeScreen` is a pure view: it takes a `TakeScreenState` in and reports taps
/// out. `CaptureState` performs what `Core`'s `CaptureMachine` decides. Neither
/// knows about the other, and this is the only thing that knows about both — so
/// the screen still reaches no recorder, no player and no disk.
///
/// Two directions, deliberately different mechanisms:
/// - **Taps** arrive through `onTransport` and become `CaptureState` calls.
/// - **Edits** arrive through the screen's `@Binding` and are diffed against the
///   current projection by ``edits(from:to:)``, so only what the user actually
///   changed becomes an effect. Everything else in the value is projection-owned
///   and a write to it is ignored rather than trusted.
///
/// ``project(mode:hasTake:elapsed:position:duration:enhance:title:notice:coaching:)``
/// is `static` and takes plain values for the same reason `TakePresentation` is
/// a type rather than a pile of `switch`es in a view body: it is the contract,
/// and a contract that lives in a `body` cannot be tested without a simulator
/// (`docs/PRINCIPLES.md` #3).
@MainActor
@Observable
final class TakeScreenModel {

  private let capture: CaptureState
  private let exporter: any Exporting
  private let now: () -> Date

  /// Set when a share's render fails, cleared when the user asks to try again.
  /// A second notice source, which is why the projection now has to resolve
  /// precedence rather than just forward the capture layer's (`#16`).
  private(set) var shareNotice: TakeNotice?

  /// Time captured so far, counted from a stamp rather than accumulated per
  /// tick — a dropped tick then costs nothing.
  private(set) var elapsed: TimeInterval = 0

  /// The playhead, mirrored from the player so it is observable. Reading
  /// `capture.position` directly would move without telling SwiftUI.
  private(set) var playhead: TimeInterval = 0

  /// The take's length. Two writers, because two things know it at different
  /// moments: the recorder knows it the instant capture stops, and the player
  /// knows it once a take is decoded. Nothing else has it in between — a take
  /// is not decoded until it is played.
  private(set) var takeDuration: TimeInterval = 0

  /// The screen's own editable copy of the title. Naming is a later ticket; this
  /// exists so a rename does not silently vanish on the next projection.
  private var editedTitle: String = "New Demo 3"

  private var recordingStartedAt: Date?
  @ObservationIgnored private var tick: Timer?

  init(
    capture: CaptureState,
    exporter: any Exporting = TakeExporter(),
    now: @escaping () -> Date = Date.init
  ) {
    self.capture = capture
    self.exporter = exporter
    self.now = now
    startTick()
  }

  deinit {
    tick?.invalidate()
  }

  // MARK: - Out: what the screen draws

  var state: TakeScreenState {
    Self.project(
      mode: capture.mode,
      hasTake: capture.latestTake != nil,
      elapsed: elapsed,
      position: playhead,
      duration: takeDuration,
      enhance: capture.warmth,
      title: editedTitle,
      notice: TakeNotice.precedent(capture.captureNotice.flatMap(TakeNotice.init), shareNotice),
      coaching: .clear)  // live levels are #17; nothing measures input yet
  }

  /// The promise the header's Share button hands to the system sheet, or nil
  /// when there is no take to share — which dims the control, per the one
  /// transport rule (`#16f`): never enabled-and-inert.
  var sharedTake: SharedTake? {
    guard let take = capture.latestTake else { return nil }
    return SharedTake(
      take: take,
      warmth: capture.warmth,
      name: editedTitle,
      exporter: exporter,
      onFailure: { [weak self] in
        // The render resolves wherever the system chose to resolve it; the
        // notice is screen state, so it hops back.
        guard let self else { return }
        Task { @MainActor in self.shareFailed() }
      })
  }

  /// The promised file could not be rendered.
  ///
  /// Separate from the closure above so the resulting screen state is reachable
  /// without a share sheet, an exporter or a thread hop.
  func shareFailed() {
    shareNotice = .couldNotPrepare
  }

  /// The binding `TakeScreen` writes through. Reads the projection; writes are
  /// diffed into effects.
  var binding: Binding<TakeScreenState> {
    Binding(get: { self.state }, set: { self.apply($0) })
  }

  // MARK: - In: taps and edits

  /// A transport button was tapped. The screen has no opinion on what recording
  /// or playing *does*, so the mapping lives here.
  ///
  /// `.resume` and `.countIn` are inert this unit and dimmed on screen to say so
  /// (`#16f`: a transport button is dim whenever it cannot act) — #4 and #3.
  func transport(_ role: TransportRole) {
    switch role {
    case .record, .stop:
      Task { await capture.recordTapped() }
    case .play, .pause:
      capture.playTapped()
    case .resume, .countIn:
      break
    }
  }

  func apply(_ incoming: TakeScreenState) {
    for edit in Self.edits(from: state, to: incoming) {
      switch edit {
      case .enhance(let value):
        capture.warmth = value
      case .scrub(let position):
        capture.scrub(to: position)
        playhead = position  // don't wait a tick to redraw the marker
      case .rename(let title):
        editedTitle = title
      }
    }
  }

  /// The notice's capsule.
  func perform(_ action: TakeNoticeAction) {
    switch action {
    case .openSettings:
      guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
      UIApplication.shared.open(url)
    case .tryAgain:
      // Clears the line so Share is the obvious next move. It cannot re-raise
      // the sheet itself: `ShareLink` owns its own presentation, and nothing in
      // SwiftUI asks it to open. See `DECISIONS.md`.
      shareNotice = nil
    }
  }

  // MARK: - The clock

  /// One tick drives both the elapsed counter and the playhead — the model owns
  /// it, nothing else does. 40ms is the design's playhead cadence.
  private func startTick() {
    tick = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.advance() }
    }
  }

  /// One step of the clock. Internal rather than private so the elapsed/playhead
  /// arithmetic can be driven a tick at a time in tests, with no real `Timer`
  /// and no simulator.
  func advance() {
    if capture.mode == .recording {
      if let started = recordingStartedAt {
        elapsed = now().timeIntervalSince(started)
      } else {
        // A new take replaces the last one wholesale: its length and playhead
        // are not yet facts, and showing the previous take's are worse than
        // showing nothing.
        recordingStartedAt = now()
        elapsed = 0
        playhead = 0
        takeDuration = 0
      }
    } else if let started = recordingStartedAt {
      // Capture just stopped. Until the take is decoded, the recorder is the
      // only thing that knows how long it is, so snapshot it here.
      recordingStartedAt = nil
      elapsed = now().timeIntervalSince(started)
      takeDuration = elapsed
      // §4.4 — a stopped take opens with its playhead parked at the end.
      playhead = elapsed
    }

    // Only ever the *current* take's length; `CaptureState` returns 0 while the
    // player's playhead still belongs to a previous one.
    if capture.duration > 0 { takeDuration = capture.duration }
    if capture.mode == .playing { playhead = capture.position }
  }

  // MARK: - The pure half

  static func project(
    mode: CaptureMode,
    hasTake: Bool,
    elapsed: TimeInterval,
    position: TimeInterval,
    duration: TimeInterval,
    enhance: Double,
    title: String,
    notice: TakeNotice?,
    coaching: CoachingLevel
  ) -> TakeScreenState {
    TakeScreenState(
      mode: takeMode(for: mode, hasTake: hasTake),
      title: title,
      meta: "Today · 3:14 PM",  // placeholder: dates arrive with persistence
      bars: [],  // live levels are #17
      elapsed: elapsed,
      duration: duration,
      progress: progress(position: position, duration: duration),
      enhance: enhance,
      isPlaying: mode == .playing,
      coaching: coaching,
      notice: notice)
  }

  /// `.countIn` and `.playback` are never produced: the count-in is undriven
  /// (#3) and a take opened from the list needs a list (#5x).
  private static func takeMode(for mode: CaptureMode, hasTake: Bool) -> TakeMode {
    switch mode {
    case .recording:
      return .recording
    case .idle, .awaitingPermission, .playing:
      // The prompt being up does not change the screen behind it, so
      // `.awaitingPermission` reads as whatever it was before the tap.
      return hasTake ? .stopped : .ready
    }
  }

  /// `0` rather than `NaN` when there is nothing to be a fraction of — a take
  /// that has not been decoded yet has no duration, and the playhead sits at the
  /// start rather than nowhere.
  private static func progress(position: TimeInterval, duration: TimeInterval) -> Double {
    guard duration > 0 else { return 0 }
    return min(max(position / duration, 0), 1)
  }

  /// What a write through the binding should cause.
  ///
  /// Only three fields are user-writable — the dial, the playhead and the title.
  /// A change to anything else is the projection being handed back, not an edit.
  static func edits(from current: TakeScreenState, to incoming: TakeScreenState) -> [TakeEdit] {
    var edits: [TakeEdit] = []
    if incoming.enhance != current.enhance {
      edits.append(.enhance(incoming.enhance))
    }
    // A fraction is only a time when there is a take to be a fraction of.
    if incoming.progress != current.progress, current.duration > 0 {
      edits.append(.scrub(to: incoming.progress * current.duration))
    }
    if incoming.title != current.title {
      edits.append(.rename(incoming.title))
    }
    return edits
  }
}

/// The only three things a user can change by writing through the binding.
enum TakeEdit: Equatable {
  case enhance(Double)
  case scrub(to: TimeInterval)
  case rename(String)
}
