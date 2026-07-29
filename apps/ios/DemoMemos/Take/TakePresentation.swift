import Foundation

/// Which of the Take screen's five modes is showing.
///
/// `docs/design/screen-states.md` §4 counts five where the handoff's own table
/// counts four: `countIn` is a real mode with its own timer, waveform and button
/// rendering, and that table simply omits it.
///
/// The beat rides inside the case rather than beside it, so "counting in" and
/// "counting in from 3" cannot disagree.
enum TakeMode: Equatable {
  case ready
  case countIn(Int)
  case recording
  case stopped
  case playback
}

/// What the Take screen's header-left control does.
///
/// Two cases rather than a `Bool` because they are different actions, not two
/// labels for one: `cancel` discards the take, `backToDemos` leaves a saved one
/// alone.
enum TakeLeadingAction: Equatable {
  case cancel
  case backToDemos
}

/// Everything the Take screen's chrome resolves to for a given mode — the §4
/// table as a value.
///
/// Pure, and derived only from the mode and whether playback is under way. It is
/// a type rather than ten `switch`es scattered through a view body for the same
/// reason `TransportAppearance` is: the table is the design's contract, and a
/// contract that lives in a `body` cannot be tested without a simulator
/// (`docs/PRINCIPLES.md` #3 at component scale).
///
/// `isPlaying` is deliberately ignored outside `.stopped` and `.playback`.
/// Playback cannot be under way while the count-in runs or the recorder is
/// rolling, so the impossible combination resolves to the same value as the
/// possible one rather than to a sixth rendering nobody designed.
struct TakePresentation: Equatable {

  /// Header left. `Cancel` everywhere in the record flow; `‹ Demos` only for a
  /// take opened from the list.
  let leading: TakeLeadingAction

  /// Header right. Share and Done arrive together, once a take exists.
  let showsShareAndDone: Bool

  /// The left transport button — always Play or Pause, never the main action.
  /// The tray keeps a fixed two-button layout in every mode, so it is present
  /// and dimmed rather than absent before a take exists.
  let leftRole: TransportRole
  let isLeftEnabled: Bool

  /// The right transport button — the main action for the mode.
  let rightRole: TransportRole
  let isRightEnabled: Bool

  /// `false` greys the whole readout to `text4`: capture has not started.
  let isTimerActive: Bool

  let waveformMode: WaveformMode

  /// The coaching line speaks about live input level, so it speaks only while
  /// there is live input.
  let showsCoaching: Bool

  /// The title is an inline field on playback and static text everywhere else.
  let isTitleEditable: Bool

  /// The recorder cannot work at all — the `#15a` treatment. Drives the grey
  /// disc on Record and dims the dial with it: there is nothing to shape.
  let isRecordBlocked: Bool

  /// The dial stops accepting input along with the recorder (`#15a`).
  var isEnhanceEnabled: Bool { !isRecordBlocked }

  init(mode: TakeMode, isPlaying: Bool = false, isRecordBlocked: Bool = false) {
    self.isRecordBlocked = isRecordBlocked
    switch mode {
    case .ready:
      leading = .cancel
      showsShareAndDone = false
      leftRole = .play
      isLeftEnabled = false
      rightRole = .record
      // The one transport rule (`#16f`): dim whenever it cannot act. Here the
      // reason is "no microphone" rather than "no take yet", and it gets the
      // same treatment.
      isRightEnabled = !isRecordBlocked
      isTimerActive = false
      waveformMode = .resting
      showsCoaching = false
      isTitleEditable = false

    case .countIn(let beat):
      // Not yet capture: the timer starts on the first captured beat, and the
      // waveform has nothing to roll. Everything else matches `.ready`, so the
      // button cannot resize as the count-in begins.
      leading = .cancel
      showsShareAndDone = false
      leftRole = .play
      isLeftEnabled = false
      rightRole = .countIn(beat)
      isRightEnabled = true
      isTimerActive = false
      waveformMode = .resting
      showsCoaching = false
      isTitleEditable = false

    case .recording:
      leading = .cancel
      showsShareAndDone = false
      leftRole = .play
      isLeftEnabled = false
      rightRole = .stop
      isRightEnabled = true
      isTimerActive = true
      waveformMode = .live
      showsCoaching = true
      isTitleEditable = false

    case .stopped:
      leading = .cancel
      showsShareAndDone = true
      leftRole = isPlaying ? .pause : .play
      isLeftEnabled = true
      rightRole = .resume
      // Dim, not enabled-and-inert (`#16f`). Resuming onto a take is #4 and is
      // not built, so the button cannot act for *any* take yet — "an enabled
      // control that does nothing is a lie the user has to test to disbelieve".
      // When #4 lands this becomes `!isPlaying` again: resuming while playing
      // would record over the thing being listened to.
      isRightEnabled = false
      isTimerActive = true
      waveformMode = .scrub
      showsCoaching = false
      isTitleEditable = false

    case .playback:
      leading = .backToDemos
      showsShareAndDone = true
      leftRole = isPlaying ? .pause : .play
      isLeftEnabled = true
      rightRole = .resume
      // Dim for the same reason as `.stopped`: #4 is not built.
      isRightEnabled = false
      isTimerActive = true
      waveformMode = .scrub
      showsCoaching = false
      isTitleEditable = true
    }
  }
}
