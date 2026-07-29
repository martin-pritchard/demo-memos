import Foundation

/// Everything `TakeScreen` draws, as one value.
///
/// **Stub state, not a domain model.** `meta` is a formatted string and there is
/// no `Demo`, no `URL` and no `Date` here, for the same reason `DemoRow` takes
/// strings: persistence is a decision this ticket defers, and a domain model
/// invented inside a screen is that decision made in passing.
///
/// The screen owns no clock, no recorder and no player. `bars`, `elapsed` and
/// `progress` are values handed in — the roll, the count and the playhead are
/// whatever fills them later.
struct TakeScreenState: Equatable {

  var mode: TakeMode = .ready

  /// Defaults to `New Demo {n}` in the design; the counter is the list's job.
  var title: String = "New Demo 3"

  /// Already formatted — "Today · 3:14 PM".
  var meta: String = "Today · 3:14 PM"

  /// Bar levels, `0…1`, newest last. Empty until something is captured.
  var bars: [Float] = []

  var elapsed: TimeInterval = 0

  /// The playhead, `0…1`.
  var progress: Double = 0

  /// The single audio control. The design's default.
  var enhance: Double = 0.5

  var isPlaying: Bool = false

  /// What the live meter has to say about the input. Only rendered while
  /// recording — `TakePresentation.showsCoaching` is the gate.
  var coaching: CoachingLevel = .clear

  /// The §4 table, resolved for this state.
  var presentation: TakePresentation {
    TakePresentation(mode: mode, isPlaying: isPlaying)
  }
}

// MARK: - Scenarios

/// One named value per state in `docs/design/screen-states.md` §4 and its
/// sub-state table, so every documented state is one initialiser away from a
/// `#Preview`.
extension TakeScreenState {

  /// 4.1 — nothing captured yet. Flat waveform, greyed timer, Play dimmed.
  static let ready = TakeScreenState()

  /// 4.2 — the count-in, mid-beat. Still `00:00`, still flat.
  static func countIn(beat: Int = 3) -> TakeScreenState {
    var state = TakeScreenState()
    state.mode = .countIn(beat)
    return state
  }

  /// 4.3 — rolling. Live meter, counting up, coaching slot reserved and empty.
  static let recording = TakeScreenState(
    mode: .recording,
    bars: Bars.live,
    elapsed: 37.42
  )

  /// 4.3 with the low-input hint.
  static let recordingQuiet = TakeScreenState(
    mode: .recording,
    bars: Bars.quiet,
    elapsed: 12.08,
    coaching: .low
  )

  /// 4.3 with the hot warning *and* the clipping bars that go with it — two
  /// bars over the 0.9 threshold, which is the only place the red top segment
  /// appears.
  static let recordingHot = TakeScreenState(
    mode: .recording,
    bars: Bars.hot,
    elapsed: 22.71,
    coaching: .hot
  )

  /// 4.4 — the take just stopped. Playhead parked at the end.
  static let stopped = TakeScreenState(
    mode: .stopped,
    bars: Bars.take,
    elapsed: 37.0,
    progress: 1
  )

  /// 4.5 — opened from the list, paused partway in.
  static let playback = TakeScreenState(
    mode: .playback,
    bars: Bars.take,
    elapsed: 14.6,
    progress: 0.4
  )

  /// 4.5 while playing — Play flips to Pause and Resume dims.
  static let playing = TakeScreenState(
    mode: .playback,
    bars: Bars.take,
    elapsed: 14.6,
    progress: 0.4,
    isPlaying: true
  )

  /// A take recorded with Enhance wound to the top — the warm ramp and the
  /// bloom at full.
  static let playbackHall = TakeScreenState(
    mode: .playback,
    bars: Bars.take,
    elapsed: 14.6,
    progress: 0.4,
    enhance: 1
  )

  /// Record then Stop immediately. `screen-states.md` lists the zero-length take
  /// as undesigned; this is what the assembled screen does with one today —
  /// the waveform falls back to its resting line rather than drawing a blank
  /// box.
  static let zeroLength = TakeScreenState(mode: .stopped, elapsed: 0)
}

/// Fixture bar levels. The screen owns no time, so a state is just an array —
/// which is what makes every one of these previewable.
private enum Bars {

  /// A take with a shape to it: quiet start, loud middle, a tail.
  static let take: [Float] = (0..<420).map { index in
    let position = Double(index) / 419
    return Float(max(0.06, sin(position * .pi) * (0.55 + 0.45 * sin(position * 47)) * 0.92))
  }

  /// A live meter caught mid-roll.
  static let live: [Float] = (0..<48).map { Float(0.25 + 0.5 * abs(sin(Double($0) * 0.7))) }

  /// Barely reaching the meter — the case the "move a little closer" hint is for.
  static let quiet: [Float] = (0..<48).map { Float(0.08 + 0.06 * abs(sin(Double($0) * 0.7))) }

  /// Two bars over the 0.9 clip threshold.
  static let hot: [Float] = (0..<48).map { index in
    index == 19 || index == 32 ? 0.95 : Float(0.45 + 0.4 * abs(sin(Double(index) * 0.7)))
  }
}
