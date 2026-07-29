import Foundation
import Testing

@testable import Core

private let takeURL = URL(fileURLWithPath: "/tmp/demo-memos/take-1.m4a")
private let otherTakeURL = URL(fileURLWithPath: "/tmp/demo-memos/take-2.m4a")

@Suite("CaptureMachine: record tap")
struct CaptureMachineRecordTappedTests {

  @Test func recordTapFromIdleWhenGrantedStartsRecording() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted),
      .recordTapped
    )

    #expect(state.mode == .recording)
    #expect(effects == [.startRecording])
  }

  @Test func recordTapFromIdleWhenUndeterminedAsksForPermissionWithoutRecording() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .undetermined),
      .recordTapped
    )

    #expect(state.mode == .awaitingPermission)
    #expect(effects == [.requestPermission])
    #expect(!effects.contains(.startRecording))
  }

  @Test func recordTapFromIdleWhenDeniedNoticesTheDenialAndDoesNotReprompt() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .denied),
      .recordTapped
    )

    #expect(state.mode == .idle)
    #expect(state.notice == .permissionDenied)
    #expect(effects.isEmpty)
  }

  @Test func recordTapWhileAwaitingPermissionIsIgnoredSoOnlyOnePromptIsInFlight() {
    let before = CaptureMachine.State(mode: .awaitingPermission, permission: .undetermined)

    let (state, effects) = CaptureMachine.next(before, .recordTapped)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func recordTapWhileRecordingStopsButStaysRecordingUntilTheStopArrives() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordTapped
    )

    #expect(state.mode == .recording)
    #expect(effects == [.stopRecording])
  }

  @Test func recordTapWhilePlayingWhenGrantedStopsPlaybackThenStartsRecording() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .granted, latestTake: takeURL),
      .recordTapped
    )

    #expect(state.mode == .recording)
    #expect(effects == [.stopPlayback, .startRecording])
  }

  @Test func recordTapWhilePlayingWhenUndeterminedStopsPlaybackThenRequestsPermission() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .undetermined, latestTake: takeURL),
      .recordTapped
    )

    #expect(state.mode == .awaitingPermission)
    #expect(effects == [.stopPlayback, .requestPermission])
  }

  @Test func recordTapWhilePlayingWhenDeniedStopsPlaybackAndReturnsToIdleDenied() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .denied, latestTake: takeURL),
      .recordTapped
    )

    #expect(state.mode == .idle)
    #expect(state.notice == .permissionDenied)
    #expect(effects == [.stopPlayback])
  }

  @Test func recordTapWhenGrantedClearsAnExistingNotice() {
    let (state, _) = CaptureMachine.next(
      CaptureMachine.State(
        mode: .idle,
        permission: .granted,
        notice: .stopped(.interrupted)
      ),
      .recordTapped
    )

    #expect(state.notice == nil)
  }

  @Test func recordTapWhenDeniedReplacesAnExistingNoticeWithPermissionDenied() {
    let (state, _) = CaptureMachine.next(
      CaptureMachine.State(
        mode: .idle,
        permission: .denied,
        notice: .stopped(.routeLost)
      ),
      .recordTapped
    )

    #expect(state.notice == .permissionDenied)
  }
}

@Suite("CaptureMachine: permission resolved")
struct CaptureMachinePermissionResolvedTests {

  @Test func grantedPermissionWhileAwaitingStartsRecording() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .awaitingPermission, permission: .undetermined),
      .permissionResolved(.granted)
    )

    #expect(state.permission == .granted)
    #expect(state.mode == .recording)
    #expect(effects == [.startRecording])
  }

  @Test func deniedPermissionWhileAwaitingReturnsToIdleWithADeniedNotice() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .awaitingPermission, permission: .undetermined),
      .permissionResolved(.denied)
    )

    #expect(state.permission == .denied)
    #expect(state.mode == .idle)
    #expect(state.notice == .permissionDenied)
    #expect(effects.isEmpty)
  }

  @Test func dismissedPromptWhileAwaitingReturnsToIdleWithoutANotice() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .awaitingPermission, permission: .undetermined),
      .permissionResolved(.undetermined)
    )

    #expect(state.permission == .undetermined)
    #expect(state.mode == .idle)
    #expect(state.notice == nil)
    #expect(effects.isEmpty)
  }

  @Test func permissionResolvedWhileIdleIsStoredWithoutStartingAnything() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .undetermined),
      .permissionResolved(.granted)
    )

    #expect(state.permission == .granted)
    #expect(state.mode == .idle)
    #expect(effects.isEmpty)
  }

  @Test func permissionResolvedWhileRecordingIsStoredWithoutChangingTheMode() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .undetermined),
      .permissionResolved(.denied)
    )

    #expect(state.permission == .denied)
    #expect(state.mode == .recording)
    #expect(effects.isEmpty)
  }

  @Test func permissionResolvedWhilePlayingIsStoredWithoutChangingTheMode() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .undetermined, latestTake: takeURL),
      .permissionResolved(.granted)
    )

    #expect(state.permission == .granted)
    #expect(state.mode == .playing)
    #expect(effects.isEmpty)
  }
}

@Suite("CaptureMachine: recording lifecycle")
struct CaptureMachineRecordingLifecycleTests {

  @Test func recordingStartedIsAnAcknowledgementThatChangesNothingWhileRecording() {
    let before = CaptureMachine.State(
      mode: .recording,
      permission: .granted,
      latestTake: takeURL,
      notice: .stopped(.routeLost),
      warmth: 0.4
    )

    let (state, effects) = CaptureMachine.next(before, .recordingStarted)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func recordingStartedChangesNothingFromIdle() {
    let before = CaptureMachine.State(mode: .idle, permission: .granted)

    let (state, effects) = CaptureMachine.next(before, .recordingStarted)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func recordingStartedChangesNothingWhileAwaitingPermission() {
    let before = CaptureMachine.State(mode: .awaitingPermission, permission: .undetermined)

    let (state, effects) = CaptureMachine.next(before, .recordingStarted)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func recordingStartedChangesNothingWhilePlaying() {
    let before = CaptureMachine.State(mode: .playing, permission: .granted, latestTake: takeURL)

    let (state, effects) = CaptureMachine.next(before, .recordingStarted)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func recordingFailedReturnsToIdleAndSurfacesTheNotice() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordingFailed(.startFailed("no input"))
    )

    #expect(state.mode == .idle)
    #expect(state.notice == .startFailed("no input"))
    #expect(effects.isEmpty)
  }

  @Test func recordingFailedWithAnUnexpectedFormatSurfacesBothSampleRates() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordingFailed(.unexpectedFormat(granted: 16_000, wanted: 48_000))
    )

    #expect(state.mode == .idle)
    #expect(state.notice == .unexpectedFormat(granted: 16_000, wanted: 48_000))
    #expect(effects.isEmpty)
  }

  @Test func recordingStoppedByTheUserKeepsTheTakeAndRaisesNoNotice() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordingStopped(.user, takeURL)
    )

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(state.notice == nil)
    #expect(effects.isEmpty)
  }

  @Test func recordingStoppedByAnInterruptionKeepsTheTakeAndNoticesTheReason() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordingStopped(.interrupted, takeURL)
    )

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(state.notice == .stopped(.interrupted))
    #expect(effects.isEmpty)
  }

  @Test func recordingStoppedByARouteLossKeepsTheTakeAndNoticesTheReason() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordingStopped(.routeLost, takeURL)
    )

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(state.notice == .stopped(.routeLost))
    #expect(effects.isEmpty)
  }

  @Test func recordingStoppedByAMediaServicesResetKeepsTheTakeAndNoticesTheReason() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordingStopped(.mediaServicesReset, takeURL)
    )

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(state.notice == .stopped(.mediaServicesReset))
    #expect(effects.isEmpty)
  }

  @Test func recordingStoppedByAFailureKeepsTheTakeAndNoticesTheReason() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .recordingStopped(.failed("disk full"), takeURL)
    )

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(state.notice == .stopped(.failed("disk full")))
    #expect(effects.isEmpty)
  }

  @Test func recordingStoppedReplacesAnOlderTake() {
    let (state, _) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted, latestTake: otherTakeURL),
      .recordingStopped(.user, takeURL)
    )

    #expect(state.latestTake == takeURL)
  }

  @Test func recordingStoppedArrivingWhileIdleStillLandsTheTake() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted),
      .recordingStopped(.interrupted, takeURL)
    )

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(state.notice == .stopped(.interrupted))
    #expect(effects.isEmpty)
  }

  @Test func recordingStoppedArrivingWhilePlayingStillLandsTheTake() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .granted, latestTake: otherTakeURL),
      .recordingStopped(.user, takeURL)
    )

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(effects.isEmpty)
  }
}

@Suite("CaptureMachine: playback")
struct CaptureMachinePlaybackTests {

  @Test func playTapFromIdleWithATakeStartsPlayback() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted, latestTake: takeURL),
      .playTapped
    )

    #expect(state.mode == .playing)
    #expect(effects == [.startPlayback(takeURL)])
  }

  @Test func playTapFromIdleWithNoTakeDoesNothing() {
    let before = CaptureMachine.State(mode: .idle, permission: .granted, latestTake: nil)

    let (state, effects) = CaptureMachine.next(before, .playTapped)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func playTapWhilePlayingStopsPlayback() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .granted, latestTake: takeURL),
      .playTapped
    )

    #expect(state.mode == .idle)
    #expect(effects == [.stopPlayback])
  }

  @Test func playTapWhileRecordingNeverInterruptsTheTake() {
    let before = CaptureMachine.State(mode: .recording, permission: .granted, latestTake: takeURL)

    let (state, effects) = CaptureMachine.next(before, .playTapped)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func playTapWhileAwaitingPermissionDoesNothing() {
    let before = CaptureMachine.State(
      mode: .awaitingPermission,
      permission: .undetermined,
      latestTake: takeURL
    )

    let (state, effects) = CaptureMachine.next(before, .playTapped)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func playTapThatStartsPlaybackClearsAnExistingNotice() {
    let (state, _) = CaptureMachine.next(
      CaptureMachine.State(
        mode: .idle,
        permission: .granted,
        latestTake: takeURL,
        notice: .stopped(.interrupted)
      ),
      .playTapped
    )

    #expect(state.notice == nil)
  }

  @Test func playTapThatStopsPlaybackClearsAnExistingNotice() {
    let (state, _) = CaptureMachine.next(
      CaptureMachine.State(
        mode: .playing,
        permission: .granted,
        latestTake: takeURL,
        notice: .stopped(.routeLost)
      ),
      .playTapped
    )

    #expect(state.notice == nil)
  }

  @Test func playbackFailedReturnsToIdleAndSurfacesTheNotice() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .granted, latestTake: takeURL),
      .playbackFailed(.startFailed("file missing"))
    )

    #expect(state.mode == .idle)
    #expect(state.notice == .startFailed("file missing"))
    #expect(effects.isEmpty)
  }

  @Test func playbackFinishedWhilePlayingReturnsToIdleAndLeavesTheNoticeAlone() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(
        mode: .playing,
        permission: .granted,
        latestTake: takeURL,
        notice: .stopped(.interrupted)
      ),
      .playbackFinished
    )

    #expect(state.mode == .idle)
    #expect(state.notice == .stopped(.interrupted))
    #expect(effects.isEmpty)
  }

  @Test func latePlaybackFinishedWhileRecordingDoesNotKnockTheTakeBackToIdle() {
    let before = CaptureMachine.State(mode: .recording, permission: .granted, latestTake: takeURL)

    let (state, effects) = CaptureMachine.next(before, .playbackFinished)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func playbackFinishedWhileIdleChangesNothing() {
    let before = CaptureMachine.State(mode: .idle, permission: .granted, latestTake: takeURL)

    let (state, effects) = CaptureMachine.next(before, .playbackFinished)

    #expect(state == before)
    #expect(effects.isEmpty)
  }

  @Test func playbackFinishedWhileAwaitingPermissionChangesNothing() {
    let before = CaptureMachine.State(mode: .awaitingPermission, permission: .undetermined)

    let (state, effects) = CaptureMachine.next(before, .playbackFinished)

    #expect(state == before)
    #expect(effects.isEmpty)
  }
}

@Suite("CaptureMachine: warmth")
struct CaptureMachineWarmthTests {

  @Test func warmthInRangeIsStoredAndEmitted() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted, warmth: 0),
      .warmthChanged(0.35)
    )

    #expect(state.warmth == 0.35)
    #expect(effects == [.setWarmth(0.35)])
  }

  @Test func warmthAboveOneIsClampedInBothTheStateAndTheEffect() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted),
      .warmthChanged(1.8)
    )

    #expect(state.warmth == 1)
    #expect(effects == [.setWarmth(1)])
  }

  @Test func warmthBelowZeroIsClampedInBothTheStateAndTheEffect() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted, warmth: 0.5),
      .warmthChanged(-0.4)
    )

    #expect(state.warmth == 0)
    #expect(effects == [.setWarmth(0)])
  }

  @Test func warmthAtTheBoundsIsKeptExactly() {
    let (low, lowEffects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted, warmth: 0.5),
      .warmthChanged(0)
    )
    #expect(low.warmth == 0)
    #expect(lowEffects == [.setWarmth(0)])

    let (high, highEffects) = CaptureMachine.next(
      CaptureMachine.State(mode: .idle, permission: .granted, warmth: 0.5),
      .warmthChanged(1)
    )
    #expect(high.warmth == 1)
    #expect(highEffects == [.setWarmth(1)])
  }

  @Test func warmthChangeWhileRecordingKeepsTheModeAndStillEmits() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .recording, permission: .granted),
      .warmthChanged(0.7)
    )

    #expect(state.mode == .recording)
    #expect(state.warmth == 0.7)
    #expect(effects == [.setWarmth(0.7)])
  }

  @Test func warmthChangeWhilePlayingKeepsTheModeAndStillEmits() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .playing, permission: .granted, latestTake: takeURL),
      .warmthChanged(0.25)
    )

    #expect(state.mode == .playing)
    #expect(state.warmth == 0.25)
    #expect(effects == [.setWarmth(0.25)])
  }

  @Test func warmthChangeWhileAwaitingPermissionKeepsTheModeAndStillEmits() {
    let (state, effects) = CaptureMachine.next(
      CaptureMachine.State(mode: .awaitingPermission, permission: .undetermined),
      .warmthChanged(0.9)
    )

    #expect(state.mode == .awaitingPermission)
    #expect(state.warmth == 0.9)
    #expect(effects == [.setWarmth(0.9)])
  }
}

@Suite("CaptureMachine: purity, derived state and round trip")
struct CaptureMachinePurityAndDerivedStateTests {

  @Test func nextLeavesItsInputStateUntouched() {
    let original = CaptureMachine.State(
      mode: .playing,
      permission: .granted,
      latestTake: takeURL,
      notice: .stopped(.interrupted),
      warmth: 0.5
    )
    let snapshot = original

    _ = CaptureMachine.next(original, .recordTapped)
    _ = CaptureMachine.next(original, .warmthChanged(2))
    _ = CaptureMachine.next(original, .recordingStopped(.routeLost, otherTakeURL))

    #expect(original == snapshot)
    #expect(original.mode == .playing)
    #expect(original.permission == .granted)
    #expect(original.latestTake == takeURL)
    #expect(original.notice == .stopped(.interrupted))
    #expect(original.warmth == 0.5)
  }

  @Test func canRecordIsTrueUnlessPermissionIsDenied() {
    #expect(CaptureMachine.State(permission: .granted).canRecord)
    #expect(CaptureMachine.State(permission: .undetermined).canRecord)
    #expect(!CaptureMachine.State(permission: .denied).canRecord)
  }

  @Test func isDeniedReflectsTheStoredPermission() {
    #expect(CaptureMachine.State(permission: .denied).isDenied)
    #expect(!CaptureMachine.State(permission: .granted).isDenied)
    #expect(!CaptureMachine.State(permission: .undetermined).isDenied)
  }

  @Test func canPlayNeedsATakeAndIsFalseMidRecordingEvenWithOne() {
    #expect(
      CaptureMachine.State(mode: .idle, permission: .granted, latestTake: takeURL).canPlay
    )
    #expect(
      CaptureMachine.State(mode: .playing, permission: .granted, latestTake: takeURL).canPlay
    )
    #expect(
      CaptureMachine.State(
        mode: .awaitingPermission, permission: .undetermined, latestTake: takeURL
      )
      .canPlay
    )
    #expect(
      !CaptureMachine.State(mode: .recording, permission: .granted, latestTake: takeURL).canPlay
    )
    #expect(
      !CaptureMachine.State(mode: .idle, permission: .granted, latestTake: nil).canPlay
    )
  }

  @Test func aFirstTakeFromColdPermissionEndsIdleWithATakeAndNoNotice() {
    var state = CaptureMachine.State()

    let (afterTap, tapEffects) = CaptureMachine.next(state, .recordTapped)
    state = afterTap
    #expect(state.mode == .awaitingPermission)
    #expect(tapEffects == [.requestPermission])

    let (afterGrant, grantEffects) = CaptureMachine.next(state, .permissionResolved(.granted))
    state = afterGrant
    #expect(state.mode == .recording)
    #expect(state.permission == .granted)
    #expect(grantEffects == [.startRecording])

    let (afterStarted, startedEffects) = CaptureMachine.next(state, .recordingStarted)
    state = afterStarted
    #expect(state.mode == .recording)
    #expect(startedEffects.isEmpty)

    let (afterStop, stopEffects) = CaptureMachine.next(
      state,
      .recordingStopped(.user, takeURL)
    )
    state = afterStop

    #expect(state.mode == .idle)
    #expect(state.latestTake == takeURL)
    #expect(state.notice == nil)
    #expect(stopEffects.isEmpty)
    #expect(state.canPlay)
  }
}
