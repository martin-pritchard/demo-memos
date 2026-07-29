import Core
import Testing

@testable import DemoMemos

@Suite("TakeNotice routes a capture fact to the way the user meets it")
struct TakeNoticeRoutingTests {

  /// Every `CaptureNotice` named by the contract, so the shape rules can sweep all of them.
  private static let everyNotice: [CaptureNotice] = [
    .permissionDenied,
    .stopped(.user),
    .stopped(.interrupted),
    .stopped(.routeLost),
    .stopped(.mediaServicesReset),
    .stopped(.failed("disk full")),
    .startFailed("no input"),
    .unexpectedFormat(granted: 44100, wanted: 48000),
  ]

  @Test("shows a denied microphone as a line with a Settings action and no alert title")
  func showsADeniedMicrophoneAsALineWithASettingsAction() throws {
    let notice = try #require(TakeNotice(.permissionDenied), "a denied microphone must be said")

    #expect(notice.line == "Microphone access is off")
    #expect(notice.sub == nil)
    #expect(notice.action == .openSettings)
    #expect(notice.form == .line)
    #expect(notice.rank == .micState)
    #expect(notice.alertTitle == nil)
  }

  @Test("treats a denied microphone as a state rather than an error, so never as an alert")
  func treatsADeniedMicrophoneAsAStateRatherThanAnAlert() throws {
    let notice = try #require(TakeNotice(.permissionDenied), "a denied microphone must be said")

    #expect(notice.form != .alert)
    #expect(notice.alertTitle == nil)
  }

  @Test("leaves Settings out of the permission prose, because the button is the way out")
  func leavesSettingsOutOfThePermissionProse() throws {
    let notice = try #require(TakeNotice(.permissionDenied), "a denied microphone must be said")

    #expect(notice.line.contains("Settings") == false)
  }

  @Test("says nothing about a stop the user asked for or lived through")
  func saysNothingAboutAStopTheUserAskedForOrLivedThrough() {
    let silent: [StopReason] = [.user, .interrupted, .routeLost]

    for reason in silent {
      #expect(TakeNotice(.stopped(reason)) == nil, "\(reason) should produce no notice at all")
    }
  }

  @Test("raises an alert titled for what failed, carrying the payload in its message")
  func raisesAnAlertTitledForWhatFailedCarryingThePayload() throws {
    let expectations: [(input: CaptureNotice, title: String, fragments: [String])] = [
      (.stopped(.mediaServicesReset), "Recording Stopped", []),
      (.stopped(.failed("disk full")), "Recording Stopped", ["disk full"]),
      (.startFailed("no input"), "Couldn't Start Recording", ["no input"]),
      (
        .unexpectedFormat(granted: 44100, wanted: 48000), "Couldn't Start Recording",
        ["44100", "48000"]
      ),
    ]

    for expectation in expectations {
      let notice = try #require(
        TakeNotice(expectation.input), "\(expectation.input) should produce a notice")

      #expect(notice.form == .alert, "\(expectation.input) should reach the user as an alert")
      #expect(
        notice.alertTitle == expectation.title,
        "\(expectation.input) should be titled \(expectation.title)")

      for fragment in expectation.fragments {
        #expect(
          notice.line.contains(fragment),
          "\(expectation.input) should say \(fragment) in its message, got \(notice.line)")
      }
    }
  }

  @Test("offers no action when the media server died, because there is nothing to open")
  func offersNoActionWhenTheMediaServerDied() throws {
    let notice = try #require(
      TakeNotice(.stopped(.mediaServicesReset)), "a media services reset must be said")

    #expect(notice.action == nil)
  }

  @Test("gives every alert a title and never gives a line one")
  func givesEveryAlertATitleAndNeverGivesALineOne() {
    for input in Self.everyNotice {
      guard let notice = TakeNotice(input) else { continue }

      switch notice.form {
      case .alert:
        #expect(notice.alertTitle != nil, "the alert for \(input) needs a title")
      case .line:
        #expect(notice.alertTitle == nil, "the line for \(input) should carry no alert title")
      }
    }
  }
}

@Suite("TakeSlot resolves the screen's one reserved message slot")
struct TakeSlotResolutionTests {

  private func lineNotice() throws -> TakeNotice {
    try #require(TakeNotice(.permissionDenied), "a denied microphone must produce a line notice")
  }

  private func alertNotice() throws -> TakeNotice {
    try #require(TakeNotice(.startFailed("x")), "a failed start must produce an alert notice")
  }

  @Test("shows nothing when there is no notice and coaching is clear")
  func showsNothingWhenThereIsNoNoticeAndCoachingIsClear() {
    #expect(TakeSlot.resolve(notice: nil, coaching: .clear) == .empty)
  }

  @Test("shows the coaching level when there is no notice and coaching has something to say")
  func showsTheCoachingLevelWhenThereIsNoNotice() {
    let speaking: [CoachingLevel] = [.low, .hot]

    for level in speaking {
      #expect(
        TakeSlot.resolve(notice: nil, coaching: level) == .coaching(level),
        "coaching \(level) should hold the slot when nothing else wants it")
    }
  }

  @Test("lets a line notice take the slot from coaching at every level")
  func letsALineNoticeTakeTheSlotFromCoachingAtEveryLevel() throws {
    let notice = try lineNotice()
    #expect(notice.form == .line, "this test needs a line notice to be meaningful")

    for level in CoachingLevel.allCases {
      #expect(
        TakeSlot.resolve(notice: notice, coaching: level) == .notice(notice),
        "a line notice should outrank coaching \(level)")
    }
  }

  @Test("leaves the slot to coaching when the notice is an alert")
  func leavesTheSlotToCoachingWhenTheNoticeIsAnAlert() throws {
    let notice = try alertNotice()
    #expect(notice.form == .alert, "this test needs an alert notice to be meaningful")

    #expect(TakeSlot.resolve(notice: notice, coaching: .low) == .coaching(.low))
    #expect(TakeSlot.resolve(notice: notice, coaching: .clear) == .empty)
  }
}

@Suite("TakeNoticeRank orders what wins the slot")
struct TakeNoticeRankTests {

  @Test("puts the microphone state ahead of a playback failure, and that ahead of capacity")
  func putsTheMicrophoneStateAheadOfPlaybackFailureAndCapacity() {
    #expect(TakeNoticeRank.micState < TakeNoticeRank.playbackFailure)
    #expect(TakeNoticeRank.playbackFailure < TakeNoticeRank.capacity)
  }

  @Test("sorts ascending into microphone state, playback failure, then capacity")
  func sortsAscendingIntoMicrophoneStatePlaybackFailureThenCapacity() {
    let shuffled: [TakeNoticeRank] = [.capacity, .micState, .playbackFailure]

    #expect(shuffled.sorted() == [.micState, .playbackFailure, .capacity])
  }
}
