import Foundation
import SwiftUI
import Testing

@testable import DemoMemos

/// One row of the Take-screen chrome table from `docs/design/screen-states.md` §4.
typealias Row = (
  mode: TakeMode,
  leading: TakeLeadingAction,
  showsShareAndDone: Bool,
  leftRole: TransportRole,
  isLeftEnabled: Bool,
  rightRole: TransportRole,
  isRightEnabled: Bool,
  isTimerActive: Bool,
  waveformMode: WaveformMode,
  showsCoaching: Bool,
  isTitleEditable: Bool
)

/// The table as it resolves when nothing is playing.
let restingRows: [Row] = [
  (.ready, .cancel, false, .play, false, .record, true, false, .resting, false, false),
  (.countIn(3), .cancel, false, .play, false, .countIn(3), true, false, .resting, false, false),
  (.recording, .cancel, false, .play, false, .stop, true, true, .live, true, false),
  // Resume is dim in both rows: `#16f` dims a transport button whenever it
  // cannot act, and resuming onto a take is #4.
  (.stopped, .cancel, true, .play, true, .resume, false, true, .scrub, false, false),
  (.playback, .backToDemos, true, .play, true, .resume, false, true, .scrub, false, true),
]

/// The same table with playback under way: the left button becomes Pause. Resume
/// is already dim, so playing changes nothing on the right.
let playingRows: [Row] = [
  (.ready, .cancel, false, .play, false, .record, true, false, .resting, false, false),
  (.countIn(3), .cancel, false, .play, false, .countIn(3), true, false, .resting, false, false),
  (.recording, .cancel, false, .play, false, .stop, true, true, .live, true, false),
  (.stopped, .cancel, true, .pause, true, .resume, false, true, .scrub, false, false),
  (.playback, .backToDemos, true, .pause, true, .resume, false, true, .scrub, false, true),
]

private let allModes: [TakeMode] = [.ready, .countIn(3), .recording, .stopped, .playback]
private let recordFlowModes: [TakeMode] = [.ready, .countIn(3), .recording]
private let takeExistsModes: [TakeMode] = [.stopped, .playback]

struct TakePresentationTests {

  // MARK: - Helpers

  private func expect(_ presentation: TakePresentation, matches row: Row, _ context: String) {
    #expect(presentation.leading == row.leading, "leading, \(context)")
    #expect(
      presentation.showsShareAndDone == row.showsShareAndDone, "showsShareAndDone, \(context)")
    #expect(presentation.leftRole == row.leftRole, "leftRole, \(context)")
    #expect(presentation.isLeftEnabled == row.isLeftEnabled, "isLeftEnabled, \(context)")
    #expect(presentation.rightRole == row.rightRole, "rightRole, \(context)")
    #expect(presentation.isRightEnabled == row.isRightEnabled, "isRightEnabled, \(context)")
    #expect(presentation.isTimerActive == row.isTimerActive, "isTimerActive, \(context)")
    #expect(presentation.waveformMode == row.waveformMode, "waveformMode, \(context)")
    #expect(presentation.showsCoaching == row.showsCoaching, "showsCoaching, \(context)")
    #expect(presentation.isTitleEditable == row.isTitleEditable, "isTitleEditable, \(context)")
  }

  // MARK: - The five rows, one test each

  // §4 row 1 — nothing captured yet: Cancel, a dead Play, an armed Record.
  @Test func readyResolvesToTheReadyRow() {
    let presentation = TakePresentation(mode: .ready)
    #expect(presentation.leading == .cancel)
    #expect(presentation.showsShareAndDone == false)
    #expect(presentation.leftRole == .play)
    #expect(presentation.isLeftEnabled == false)
    #expect(presentation.rightRole == .record)
    #expect(presentation.isRightEnabled == true)
    #expect(presentation.isTimerActive == false)
    #expect(presentation.waveformMode == .resting)
    #expect(presentation.showsCoaching == false)
    #expect(presentation.isTitleEditable == false)
  }

  // §4 row 2 — the count-in is still pre-capture chrome, only the right role changes.
  @Test func countInResolvesToTheCountInRow() {
    let presentation = TakePresentation(mode: .countIn(4))
    #expect(presentation.leading == .cancel)
    #expect(presentation.showsShareAndDone == false)
    #expect(presentation.leftRole == .play)
    #expect(presentation.isLeftEnabled == false)
    #expect(presentation.rightRole == .countIn(4))
    #expect(presentation.isRightEnabled == true)
    #expect(presentation.isTimerActive == false)
    #expect(presentation.waveformMode == .resting)
    #expect(presentation.showsCoaching == false)
    #expect(presentation.isTitleEditable == false)
  }

  // §4 row 3 — the only mode with a live meter and a coaching line.
  @Test func recordingResolvesToTheRecordingRow() {
    let presentation = TakePresentation(mode: .recording)
    #expect(presentation.leading == .cancel)
    #expect(presentation.showsShareAndDone == false)
    #expect(presentation.leftRole == .play)
    #expect(presentation.isLeftEnabled == false)
    #expect(presentation.rightRole == .stop)
    #expect(presentation.isRightEnabled == true)
    #expect(presentation.isTimerActive == true)
    #expect(presentation.waveformMode == .live)
    #expect(presentation.showsCoaching == true)
    #expect(presentation.isTitleEditable == false)
  }

  // §4 row 4 — a take exists, so Share and Done arrive, but the flow is not finished:
  // still Cancel, still a static title.
  @Test func stoppedResolvesToTheStoppedRow() {
    let presentation = TakePresentation(mode: .stopped)
    #expect(presentation.leading == .cancel)
    #expect(presentation.showsShareAndDone == true)
    #expect(presentation.leftRole == .play)
    #expect(presentation.isLeftEnabled == true)
    #expect(presentation.rightRole == .resume)
    // Dim, not enabled-and-inert (`#16f`): resuming onto a take is #4.
    #expect(presentation.isRightEnabled == false)
    #expect(presentation.isTimerActive == true)
    #expect(presentation.waveformMode == .scrub)
    #expect(presentation.showsCoaching == false)
    #expect(presentation.isTitleEditable == false)
  }

  // §4 row 5 — the saved take: back to Demos, and the title becomes editable.
  @Test func playbackResolvesToThePlaybackRow() {
    let presentation = TakePresentation(mode: .playback)
    #expect(presentation.leading == .backToDemos)
    #expect(presentation.showsShareAndDone == true)
    #expect(presentation.leftRole == .play)
    #expect(presentation.isLeftEnabled == true)
    #expect(presentation.rightRole == .resume)
    // Dim, not enabled-and-inert (`#16f`): resuming onto a take is #4.
    #expect(presentation.isRightEnabled == false)
    #expect(presentation.isTimerActive == true)
    #expect(presentation.waveformMode == .scrub)
    #expect(presentation.showsCoaching == false)
    #expect(presentation.isTitleEditable == true)
  }

  // MARK: - The whole table, walked

  @Test("every mode resolves to its table row when not playing", arguments: restingRows)
  func theTableHoldsWhenNotPlaying(_ row: Row) {
    expect(TakePresentation(mode: row.mode, isPlaying: false), matches: row, "\(row.mode) idle")
  }

  @Test("every mode resolves to its table row when playing", arguments: playingRows)
  func theTableHoldsWhenPlaying(_ row: Row) {
    expect(TakePresentation(mode: row.mode, isPlaying: true), matches: row, "\(row.mode) playing")
  }

  // MARK: - Rule 1 — isPlaying is inert in the record-flow modes

  @Test("isPlaying changes nothing before a take exists", arguments: recordFlowModes)
  func isPlayingIsIgnoredInTheRecordFlowModes(_ mode: TakeMode) {
    #expect(TakePresentation(mode: mode, isPlaying: true) == TakePresentation(mode: mode))
  }

  @Test("the left button stays a disabled Play before a take exists", arguments: recordFlowModes)
  func leftButtonIsAlwaysADisabledPlayInTheRecordFlow(_ mode: TakeMode) {
    for isPlaying in [false, true] {
      let presentation = TakePresentation(mode: mode, isPlaying: isPlaying)
      #expect(presentation.leftRole == .play, "\(mode) isPlaying: \(isPlaying)")
      #expect(presentation.isLeftEnabled == false, "\(mode) isPlaying: \(isPlaying)")
    }
  }

  // MARK: - Rule 2 — Play flips to Pause

  @Test("Play becomes Pause while playing, once a take exists", arguments: takeExistsModes)
  func leftRoleFlipsBetweenPlayAndPause(_ mode: TakeMode) {
    #expect(TakePresentation(mode: mode, isPlaying: false).leftRole == .play, "\(mode)")
    #expect(TakePresentation(mode: mode, isPlaying: true).leftRole == .pause, "\(mode)")
  }

  @Test("the left button is enabled either way once a take exists", arguments: takeExistsModes)
  func leftButtonIsEnabledRegardlessOfIsPlaying(_ mode: TakeMode) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).isLeftEnabled,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  // MARK: - Rule 3 — Resume is dim, because it cannot act

  /// `#16f`'s one transport rule: a transport button is dim whenever it cannot
  /// act. Resuming onto a take is #4 and is not built, so Resume cannot act for
  /// *any* take yet — an enabled control that does nothing is a lie the user has
  /// to test to disbelieve. When #4 lands this becomes `!isPlaying`.
  @Test("Resume is dim whether or not a take is playing", arguments: takeExistsModes)
  func resumeIsDimWhetherOrNotATakeIsPlaying(_ mode: TakeMode) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).isRightEnabled == false,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  // MARK: - Rule 4 — a blocked recorder dims Record and the dial

  @Test("a blocked recorder dims Record and stops the dial taking input")
  func aBlockedRecorderDimsRecordAndStopsTheDialTakingInput() {
    let blocked = TakePresentation(mode: .ready, isRecordBlocked: true)

    #expect(blocked.rightRole == .record)
    #expect(blocked.isRightEnabled == false)
    #expect(blocked.isEnhanceEnabled == false)
  }

  @Test("leaves Record and the dial alone when the recorder is fine")
  func leavesRecordAndTheDialAloneWhenTheRecorderIsFine() {
    let ready = TakePresentation(mode: .ready)

    #expect(ready.isRightEnabled == true)
    #expect(ready.isEnhanceEnabled == true)
  }

  @Test("the right button is always enabled in the record flow", arguments: recordFlowModes)
  func rightButtonIsAlwaysEnabledInTheRecordFlow(_ mode: TakeMode) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).isRightEnabled,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  // MARK: - Rule 4 — the count-in beat rides through

  @Test("the count-in beat passes through unchanged", arguments: [4, 3, 2, 1, 0, 12])
  func countInBeatRidesThrough(_ beat: Int) {
    for isPlaying in [false, true] {
      let presentation = TakePresentation(mode: .countIn(beat), isPlaying: isPlaying)
      #expect(presentation.rightRole == .countIn(beat), "beat \(beat) isPlaying: \(isPlaying)")
      #expect(presentation.rightRole != .record, "beat \(beat) must not collapse to .record")
    }
  }

  @Test func countInBeatsResolveToDistinctPresentations() {
    #expect(TakePresentation(mode: .countIn(4)) != TakePresentation(mode: .countIn(3)))
    #expect(TakePresentation(mode: .countIn(0)) != TakePresentation(mode: .countIn(12)))
  }

  // MARK: - Rule 5 — the count-in is not yet capture

  @Test("the count-in keeps Ready's greyed timer and resting waveform", arguments: [4, 1, 0, 12])
  func countInSharesReadysTimerAndWaveform(_ beat: Int) {
    let ready = TakePresentation(mode: .ready)
    let countIn = TakePresentation(mode: .countIn(beat))
    #expect(countIn.isTimerActive == false, "beat \(beat)")
    #expect(countIn.waveformMode == .resting, "beat \(beat)")
    #expect(countIn.isTimerActive == ready.isTimerActive, "beat \(beat)")
    #expect(countIn.waveformMode == ready.waveformMode, "beat \(beat)")
  }

  // MARK: - Rules 6 to 9 — the one-mode-only flags

  @Test(
    "coaching shows only while recording",
    arguments: [
      (TakeMode.ready, false),
      (TakeMode.countIn(3), false),
      (TakeMode.recording, true),
      (TakeMode.stopped, false),
      (TakeMode.playback, false),
    ])
  func coachingIsRecordingOnly(_ mode: TakeMode, _ expected: Bool) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).showsCoaching == expected,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  @Test(
    "the title is editable only in playback",
    arguments: [
      (TakeMode.ready, false),
      (TakeMode.countIn(3), false),
      (TakeMode.recording, false),
      (TakeMode.stopped, false),
      (TakeMode.playback, true),
    ])
  func titleIsEditableInPlaybackOnly(_ mode: TakeMode, _ expected: Bool) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).isTitleEditable == expected,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  @Test(
    "only playback leads with a back control to Demos",
    arguments: [
      (TakeMode.ready, TakeLeadingAction.cancel),
      (TakeMode.countIn(3), TakeLeadingAction.cancel),
      (TakeMode.recording, TakeLeadingAction.cancel),
      (TakeMode.stopped, TakeLeadingAction.cancel),
      (TakeMode.playback, TakeLeadingAction.backToDemos),
    ])
  func backToDemosAppearsInPlaybackOnly(_ mode: TakeMode, _ expected: TakeLeadingAction) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).leading == expected,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  @Test(
    "Share and Done appear only once a take exists",
    arguments: [
      (TakeMode.ready, false),
      (TakeMode.countIn(3), false),
      (TakeMode.recording, false),
      (TakeMode.stopped, true),
      (TakeMode.playback, true),
    ])
  func shareAndDoneAppearOnlyOnceATakeExists(_ mode: TakeMode, _ expected: Bool) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).showsShareAndDone == expected,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  @Test(
    "the timer runs from the first captured beat onwards",
    arguments: [
      (TakeMode.ready, false),
      (TakeMode.countIn(3), false),
      (TakeMode.recording, true),
      (TakeMode.stopped, true),
      (TakeMode.playback, true),
    ])
  func timerIsActiveOnlyOnceCaptureHasStarted(_ mode: TakeMode, _ expected: Bool) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).isTimerActive == expected,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  @Test(
    "the waveform rests, goes live, then scrubs",
    arguments: [
      (TakeMode.ready, WaveformMode.resting),
      (TakeMode.countIn(3), WaveformMode.resting),
      (TakeMode.recording, WaveformMode.live),
      (TakeMode.stopped, WaveformMode.scrub),
      (TakeMode.playback, WaveformMode.scrub),
    ])
  func waveformModeFollowsTheMode(_ mode: TakeMode, _ expected: WaveformMode) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying).waveformMode == expected,
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  // MARK: - Rule 10 — the tray keeps two buttons in every mode

  @Test("the right button always carries a right-hand role", arguments: allModes)
  func rightRoleIsNeverALeftHandRole(_ mode: TakeMode) {
    for isPlaying in [false, true] {
      let role = TakePresentation(mode: mode, isPlaying: isPlaying).rightRole
      #expect(role != .play, "\(mode) isPlaying: \(isPlaying)")
      #expect(role != .pause, "\(mode) isPlaying: \(isPlaying)")
    }
  }

  @Test("the left button always carries a left-hand role", arguments: allModes)
  func leftRoleIsAlwaysPlayOrPause(_ mode: TakeMode) {
    for isPlaying in [false, true] {
      let role = TakePresentation(mode: mode, isPlaying: isPlaying).leftRole
      #expect(role == .play || role == .pause, "\(mode) isPlaying: \(isPlaying)")
    }
  }

  // MARK: - Rule 11 — purity and value semantics

  @Test("the same arguments always produce an equal value", arguments: allModes)
  func constructionIsPure(_ mode: TakeMode) {
    for isPlaying in [false, true] {
      #expect(
        TakePresentation(mode: mode, isPlaying: isPlaying)
          == TakePresentation(mode: mode, isPlaying: isPlaying),
        "\(mode) isPlaying: \(isPlaying)")
    }
  }

  @Test func repeatedConstructionCarriesNoMemoryOfPreviousValues() {
    let first = TakePresentation(mode: .playback, isPlaying: true)
    _ = TakePresentation(mode: .recording)
    _ = TakePresentation(mode: .countIn(2))
    let second = TakePresentation(mode: .playback, isPlaying: true)
    #expect(first == second)
  }

  @Test func isPlayingDefaultsToFalse() {
    for mode in allModes {
      #expect(
        TakePresentation(mode: mode) == TakePresentation(mode: mode, isPlaying: false), "\(mode)")
    }
  }

  @Test(
    "no two modes resolve to the same presentation",
    arguments: [
      (TakeMode.ready, TakeMode.countIn(3)),
      (TakeMode.ready, TakeMode.recording),
      (TakeMode.ready, TakeMode.stopped),
      (TakeMode.ready, TakeMode.playback),
      (TakeMode.countIn(3), TakeMode.recording),
      (TakeMode.countIn(3), TakeMode.stopped),
      (TakeMode.countIn(3), TakeMode.playback),
      (TakeMode.recording, TakeMode.stopped),
      (TakeMode.recording, TakeMode.playback),
      (TakeMode.stopped, TakeMode.playback),
    ])
  func differentModesProduceDifferentValues(_ one: TakeMode, _ other: TakeMode) {
    #expect(TakePresentation(mode: one) != TakePresentation(mode: other), "\(one) vs \(other)")
  }

  @Test("playing changes the presentation once a take exists", arguments: takeExistsModes)
  func isPlayingIsObservableOnceATakeExists(_ mode: TakeMode) {
    #expect(
      TakePresentation(mode: mode, isPlaying: false)
        != TakePresentation(mode: mode, isPlaying: true), "\(mode)")
  }
}
