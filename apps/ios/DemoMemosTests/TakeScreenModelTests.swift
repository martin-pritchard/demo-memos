import Core
import Foundation
import Testing

@testable import DemoMemos

// MARK: - Helpers

/// One base state every `edits` test mutates a copy of.
private func makeState(
  mode: TakeMode = .stopped,
  title: String = "Take 1",
  meta: String = "Today · 0:10",
  bars: [Float] = [],
  elapsed: TimeInterval = 3,
  duration: TimeInterval = 10,
  progress: Double = 0,
  enhance: Double = 0.5,
  isPlaying: Bool = false,
  coaching: CoachingLevel = .clear,
  notice: TakeNotice? = nil
) -> TakeScreenState {
  TakeScreenState(
    mode: mode,
    title: title,
    meta: meta,
    bars: bars,
    elapsed: elapsed,
    duration: duration,
    progress: progress,
    enhance: enhance,
    isPlaying: isPlaying,
    coaching: coaching,
    notice: notice
  )
}

/// Calls the projection with defaults for everything the test does not care about.
@MainActor
private func project(
  mode: CaptureMode = .idle,
  hasTake: Bool = false,
  elapsed: TimeInterval = 0,
  position: TimeInterval = 0,
  duration: TimeInterval = 0,
  enhance: Double = 0,
  title: String = "Take 1",
  notice: TakeNotice? = nil,
  coaching: CoachingLevel = .clear
) -> TakeScreenState {
  TakeScreenModel.project(
    mode: mode,
    hasTake: hasTake,
    elapsed: elapsed,
    position: position,
    duration: duration,
    enhance: enhance,
    title: title,
    notice: notice,
    coaching: coaching
  )
}

private func isCountIn(_ mode: TakeMode) -> Bool {
  if case .countIn = mode { return true }
  return false
}

private let tolerance = 1e-9

// MARK: - project: mode mapping

@MainActor
@Suite("Projecting a capture mode onto the Take screen")
struct TakeScreenModelProjectionModeTests {

  /// The whole contract table, shared by the mapping tests below.
  private static let table: [(capture: CaptureMode, hasTake: Bool, expected: TakeMode)] = [
    (.idle, false, .ready),
    (.awaitingPermission, false, .ready),
    (.recording, false, .recording),
    (.recording, true, .recording),
    (.idle, true, .stopped),
    (.playing, true, .stopped),
    (.awaitingPermission, true, .stopped),
  ]

  @Test("maps every capture mode and take presence to the screen mode the table names")
  func mapsEveryCaptureModeAndTakePresenceToTheScreenModeTheTableNames() {
    for row in Self.table {
      let state = project(mode: row.capture, hasTake: row.hasTake)
      #expect(
        state.mode == row.expected,
        "\(row.capture) with hasTake=\(row.hasTake) should project as \(row.expected)"
      )
    }
  }

  @Test("never produces the playback mode, whatever the capture mode and take presence")
  func neverProducesThePlaybackModeWhateverTheCaptureModeAndTakePresence() {
    for row in Self.table {
      let state = project(mode: row.capture, hasTake: row.hasTake)
      #expect(
        state.mode != .playback,
        "\(row.capture) with hasTake=\(row.hasTake) should not project as .playback"
      )
    }
  }

  @Test("never produces the count-in mode, whatever the capture mode and take presence")
  func neverProducesTheCountInModeWhateverTheCaptureModeAndTakePresence() {
    for row in Self.table {
      let state = project(mode: row.capture, hasTake: row.hasTake)
      #expect(
        isCountIn(state.mode) == false,
        "\(row.capture) with hasTake=\(row.hasTake) should not project as .countIn"
      )
    }
  }

  @Test("leaves the screen behind the microphone prompt unchanged")
  func leavesTheScreenBehindTheMicrophonePromptUnchanged() {
    #expect(project(mode: .awaitingPermission, hasTake: false).mode == .ready)
    #expect(project(mode: .awaitingPermission, hasTake: true).mode == .stopped)
  }
}

// MARK: - project: isPlaying

@MainActor
@Suite("Projecting whether the take is playing")
struct TakeScreenModelProjectionIsPlayingTests {

  @Test("reports playing only while the capture mode is playing")
  func reportsPlayingOnlyWhileTheCaptureModeIsPlaying() {
    let modes: [CaptureMode] = [.idle, .awaitingPermission, .recording, .playing]
    for hasTake in [false, true] {
      for mode in modes {
        let state = project(mode: mode, hasTake: hasTake)
        #expect(
          state.isPlaying == (mode == .playing),
          "\(mode) with hasTake=\(hasTake) should report isPlaying == \(mode == .playing)"
        )
      }
    }
  }
}

// MARK: - project: progress

@MainActor
@Suite("Projecting playback progress")
struct TakeScreenModelProjectionProgressTests {

  @Test("reports progress as the position's fraction of the duration")
  func reportsProgressAsThePositionsFractionOfTheDuration() {
    let cases: [(position: TimeInterval, duration: TimeInterval, expected: Double)] = [
      (0, 10, 0),
      (2.5, 10, 0.25),
      (5, 10, 0.5),
      (10, 10, 1),
      (1, 4, 0.25),
    ]
    for row in cases {
      let state = project(
        mode: .playing, hasTake: true, position: row.position, duration: row.duration)
      #expect(
        abs(state.progress - row.expected) < tolerance,
        "position \(row.position) of \(row.duration) should be \(row.expected)"
      )
    }
  }

  @Test("reports zero progress rather than NaN when the duration is zero")
  func reportsZeroProgressRatherThanNaNWhenTheDurationIsZero() {
    let state = project(mode: .playing, hasTake: true, position: 4.2, duration: 0)
    #expect(state.progress == 0)
    #expect(state.progress.isNaN == false)
    #expect(state.progress.isInfinite == false)
  }

  @Test("clamps a position past the end of the take to full progress")
  func clampsAPositionPastTheEndOfTheTakeToFullProgress() {
    let state = project(mode: .playing, hasTake: true, position: 30, duration: 10)
    #expect(state.progress == 1)
  }

  @Test("clamps a negative position to no progress")
  func clampsANegativePositionToNoProgress() {
    let state = project(mode: .playing, hasTake: true, position: -5, duration: 10)
    #expect(state.progress == 0)
  }
}

// MARK: - project: pass-through

@MainActor
@Suite("Passing values straight through the projection")
struct TakeScreenModelProjectionPassThroughTests {

  @Test("passes the elapsed time, duration, enhance and title through unchanged")
  func passesTheElapsedTimeDurationEnhanceAndTitleThroughUnchanged() {
    let state = project(
      mode: .recording,
      hasTake: true,
      elapsed: 12.5,
      position: 3,
      duration: 42,
      enhance: 0.73,
      title: "Bridge idea"
    )
    #expect(abs(state.elapsed - 12.5) < tolerance)
    #expect(abs(state.duration - 42) < tolerance)
    #expect(abs(state.enhance - 0.73) < tolerance)
    #expect(state.title == "Bridge idea")
  }

  @Test("passes every coaching level through unchanged")
  func passesEveryCoachingLevelThroughUnchanged() {
    for level in CoachingLevel.allCases {
      #expect(project(mode: .recording, coaching: level).coaching == level)
    }
  }

  @Test("passes a notice through unchanged, and an absent notice stays absent")
  func passesANoticeThroughUnchangedAndAnAbsentNoticeStaysAbsent() {
    let notice = TakeNotice(.permissionDenied)
    #expect(notice != nil)
    #expect(project(mode: .idle, notice: notice).notice == notice)
    #expect(project(mode: .idle, notice: nil).notice == nil)
  }

  @Test("passes the extremes of the enhance range through unchanged")
  func passesTheExtremesOfTheEnhanceRangeThroughUnchanged() {
    #expect(project(enhance: 0).enhance == 0)
    #expect(project(enhance: 1).enhance == 1)
  }

  @Test("passes an empty title through unchanged")
  func passesAnEmptyTitleThroughUnchanged() {
    #expect(project(title: "").title == "")
  }

  @Test("projects no bars, whatever the mode")
  func projectsNoBarsWhateverTheMode() {
    let modes: [CaptureMode] = [.idle, .awaitingPermission, .recording, .playing]
    for hasTake in [false, true] {
      for mode in modes {
        let state = project(mode: mode, hasTake: hasTake, elapsed: 5, position: 2, duration: 10)
        #expect(state.bars.isEmpty, "\(mode) with hasTake=\(hasTake) should project no bars")
      }
    }
  }
}

// MARK: - edits

@MainActor
@Suite("Diffing a write through the Take screen's binding")
struct TakeScreenModelEditsTests {

  @Test("reports no edits when nothing changed")
  func reportsNoEditsWhenNothingChanged() {
    let state = makeState()
    #expect(TakeScreenModel.edits(from: state, to: state).isEmpty)
  }

  @Test("reports an enhance edit when only the enhance value changed")
  func reportsAnEnhanceEditWhenOnlyTheEnhanceValueChanged() {
    let current = makeState(enhance: 0.5)
    var incoming = current
    incoming.enhance = 0.7
    #expect(TakeScreenModel.edits(from: current, to: incoming) == [.enhance(0.7)])
  }

  @Test("reports an enhance edit at each end of the range")
  func reportsAnEnhanceEditAtEachEndOfTheRange() {
    let current = makeState(enhance: 0.5)
    var toZero = current
    toZero.enhance = 0
    #expect(TakeScreenModel.edits(from: current, to: toZero) == [.enhance(0)])

    var toOne = current
    toOne.enhance = 1
    #expect(TakeScreenModel.edits(from: current, to: toOne) == [.enhance(1)])
  }

  @Test("reports a rename when only the title changed")
  func reportsARenameWhenOnlyTheTitleChanged() {
    let current = makeState(title: "Take 1")
    var incoming = current
    incoming.title = "Chorus idea"
    #expect(TakeScreenModel.edits(from: current, to: incoming) == [.rename("Chorus idea")])
  }

  @Test("reports a rename to an empty title")
  func reportsARenameToAnEmptyTitle() {
    let current = makeState(title: "Take 1")
    var incoming = current
    incoming.title = ""
    #expect(TakeScreenModel.edits(from: current, to: incoming) == [.rename("")])
  }

  @Test("reports a scrub in seconds, not as a fraction, when the progress changed")
  func reportsAScrubInSecondsNotAsAFractionWhenTheProgressChanged() {
    let current = makeState(duration: 10, progress: 0)
    var incoming = current
    incoming.progress = 0.25
    #expect(TakeScreenModel.edits(from: current, to: incoming) == [.scrub(to: 2.5)])
  }

  @Test("reports a scrub to each end of the take")
  func reportsAScrubToEachEndOfTheTake() {
    let current = makeState(duration: 10, progress: 0.5)
    var toStart = current
    toStart.progress = 0
    #expect(TakeScreenModel.edits(from: current, to: toStart) == [.scrub(to: 0)])

    var toEnd = current
    toEnd.progress = 1
    #expect(TakeScreenModel.edits(from: current, to: toEnd) == [.scrub(to: 10)])
  }

  @Test("reports no scrub when there is no duration to scrub through")
  func reportsNoScrubWhenThereIsNoDurationToScrubThrough() {
    let current = makeState(duration: 0, progress: 0)
    var incoming = current
    incoming.progress = 0.25
    #expect(TakeScreenModel.edits(from: current, to: incoming).isEmpty)
  }

  @Test("reports both edits when two writable fields changed at once")
  func reportsBothEditsWhenTwoWritableFieldsChangedAtOnce() {
    let current = makeState(title: "Take 1", enhance: 0.5)
    var incoming = current
    incoming.enhance = 0.7
    incoming.title = "Chorus idea"

    let edits = TakeScreenModel.edits(from: current, to: incoming)
    #expect(edits.count == 2)
    #expect(edits.contains(.enhance(0.7)))
    #expect(edits.contains(.rename("Chorus idea")))
  }

  @Test("reports all three edits when every writable field changed at once")
  func reportsAllThreeEditsWhenEveryWritableFieldChangedAtOnce() {
    let current = makeState(title: "Take 1", duration: 10, progress: 0, enhance: 0.5)
    var incoming = current
    incoming.enhance = 0.7
    incoming.title = "Chorus idea"
    incoming.progress = 0.25

    let edits = TakeScreenModel.edits(from: current, to: incoming)
    #expect(edits.count == 3)
    #expect(edits.contains(.enhance(0.7)))
    #expect(edits.contains(.rename("Chorus idea")))
    #expect(edits.contains(.scrub(to: 2.5)))
  }

  @Test("reports no edits when a field the user cannot write changed")
  func reportsNoEditsWhenAFieldTheUserCannotWriteChanged() {
    let mutations: [(field: String, apply: (inout TakeScreenState) -> Void)] = [
      ("mode", { $0.mode = .recording }),
      ("elapsed", { $0.elapsed = 7 }),
      ("duration", { $0.duration = 20 }),
      ("isPlaying", { $0.isPlaying = true }),
      ("coaching", { $0.coaching = .hot }),
      ("bars", { $0.bars = [0.25, 0.5] }),
      ("meta", { $0.meta = "Yesterday · 1:20" }),
    ]

    let current = makeState()
    for mutation in mutations {
      var incoming = current
      mutation.apply(&incoming)
      #expect(
        TakeScreenModel.edits(from: current, to: incoming).isEmpty,
        "changing \(mutation.field) is not a user edit"
      )
    }
  }

  @Test("reports no edits when a notice appeared without a user edit")
  func reportsNoEditsWhenANoticeAppearedWithoutAUserEdit() {
    let current = makeState()
    var incoming = current
    incoming.notice = TakeNotice(.permissionDenied)
    #expect(TakeScreenModel.edits(from: current, to: incoming).isEmpty)
  }
}
