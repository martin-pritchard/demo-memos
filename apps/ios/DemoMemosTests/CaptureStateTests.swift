import Foundation
import Testing

@testable import DemoMemos

@MainActor
struct CaptureStateTests {

  // MARK: - Helpers

  /// Fixed clock so nothing in these tests depends on the wall clock.
  private static func fixedNow() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

  private struct Rig {
    let store: FakeMemoStore
    let recorder: FakeAudioRecorder
    let player: FakeAudioPlayer
    let ticker: FakeCountInTicker
    let state: CaptureState

    /// Skip past the count-in to the downbeat without waiting on the clock.
    @MainActor func runCountIn() {
      for _ in 0..<CaptureState.countInBeats { state.advanceCountIn() }
    }
  }

  /// Record-flow rig: a fresh `CaptureState` starting in `.ready`.
  private func makeRecordRig(
    permission: MicPermission = .granted,
    stubbedDuration: TimeInterval = 4.2,
    failOnCommit: Bool = false
  ) -> Rig {
    let store = FakeMemoStore()
    store.failOnCommit = failOnCommit
    let recorder = FakeAudioRecorder()
    recorder.permission = permission
    recorder.stubbedDuration = stubbedDuration
    let player = FakeAudioPlayer()
    let ticker = FakeCountInTicker()
    let state = CaptureState(
      store: store,
      recorder: recorder,
      player: player,
      countInTicker: ticker,
      now: { Self.fixedNow() }
    )
    return Rig(store: store, recorder: recorder, player: player, ticker: ticker, state: state)
  }

  /// Playback-flow rig: a `CaptureState` opened on an existing memo.
  private func makePlaybackRig(memo: Memo) -> Rig {
    let store = FakeMemoStore()
    let recorder = FakeAudioRecorder()
    let player = FakeAudioPlayer()
    let ticker = FakeCountInTicker()
    let state = CaptureState(
      memo: memo,
      store: store,
      recorder: recorder,
      player: player,
      countInTicker: ticker,
      now: { Self.fixedNow() }
    )
    return Rig(store: store, recorder: recorder, player: player, ticker: ticker, state: state)
  }

  private func makeMemo() -> Memo {
    Memo(
      id: UUID(),
      name: "Riff in D",
      createdAt: Date(timeIntervalSince1970: 1_000_000),
      duration: 15,
      enhance: 0.4,
      filename: "riff.m4a"
    )
  }

  // MARK: - Permission

  @Test(
    "given microphone permission is denied, when onAppear runs, then it stays ready and cannot record"
  )
  func givenDeniedPermission_whenOnAppear_thenCannotRecord() async {
    let rig = makeRecordRig(permission: .denied)

    await rig.state.onAppear()

    #expect(rig.state.status == .ready)
    #expect(rig.state.permission == .denied)
    #expect(rig.state.canRecord == false)
  }

  @Test(
    "given microphone permission is granted, when onAppear then record runs, then it is recording")
  func givenGrantedPermission_whenRecord_thenRecording() async {
    let rig = makeRecordRig(permission: .granted)

    await rig.state.onAppear()
    rig.state.record()
    rig.runCountIn()

    #expect(rig.state.permission == .granted)
    #expect(rig.state.canRecord == true)
    #expect(rig.state.status == .recording)
  }

  // MARK: - Interruption and backgrounding

  @Test(
    "given a recording in progress, when the recorder is interrupted, then the take is stopped and kept"
  )
  func givenRecording_whenInterrupted_thenStoppedAndTakeKept() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.runCountIn()

    rig.recorder.simulateInterruption()

    #expect(rig.state.status == .stopped)
    #expect(rig.state.canPlay == true)
  }

  @Test("given a recording in progress, when the app is backgrounded, then the take is stopped")
  func givenRecording_whenBackgrounded_thenStopped() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.runCountIn()

    rig.state.handleBackground()

    #expect(rig.state.status == .stopped)
  }

  // MARK: - Done

  @Test("given a zero-length take, when done runs, then nothing is saved and the screen finishes")
  func givenZeroLengthTake_whenDone_thenNothingSaved() async {
    let rig = makeRecordRig(stubbedDuration: 0)
    await rig.state.onAppear()

    rig.state.record()
    rig.runCountIn()
    rig.state.stop()
    rig.state.done()

    #expect(rig.store.stored.isEmpty)
    #expect(rig.state.isFinished == true)
  }

  @Test(
    "given a real take with enhance set, when done runs, then one memo is persisted and the screen finishes"
  )
  func givenRealTake_whenDone_thenMemoPersisted() async throws {
    let rig = makeRecordRig(stubbedDuration: 4.2)
    await rig.state.onAppear()

    rig.state.record()
    rig.runCountIn()
    rig.state.stop()
    rig.state.enhance = 0.75
    rig.state.done()

    #expect(rig.store.stored.count == 1)
    let saved = try #require(rig.store.stored.first)
    #expect(saved.duration == 4.2)
    #expect(saved.enhance == 0.75)
    #expect(rig.state.isFinished == true)
  }

  @Test(
    "given the store fails to commit, when done runs, then the user stays in stopped with an error and a retry succeeds"
  )
  func givenCommitFails_whenDone_thenStaysStoppedAndRetrySucceeds() async throws {
    let rig = makeRecordRig(stubbedDuration: 4.2, failOnCommit: true)
    await rig.state.onAppear()

    rig.state.record()
    rig.runCountIn()
    rig.state.stop()
    rig.state.done()

    #expect(rig.state.status == .stopped)
    #expect(rig.state.errorMessage != nil)
    #expect(rig.state.isFinished == false)
    #expect(rig.store.stored.isEmpty)

    rig.store.failOnCommit = false
    rig.state.done()

    #expect(rig.store.stored.count == 1)
    let saved = try #require(rig.store.stored.first)
    #expect(saved.duration == 4.2)
    #expect(rig.state.isFinished == true)
  }

  // MARK: - Cancel

  @Test(
    "given a stopped take, when cancel runs, then the recording is discarded and nothing is saved")
  func givenStoppedTake_whenCancel_thenTakeDiscarded() async {
    let rig = makeRecordRig(stubbedDuration: 4.2)
    await rig.state.onAppear()

    rig.state.record()
    rig.runCountIn()
    rig.state.stop()
    rig.state.cancel()

    #expect(rig.store.stored.isEmpty)
    #expect(rig.store.discardedURLs.isEmpty == false)
    #expect(rig.state.isFinished == true)
  }

  // MARK: - Resume

  @Test("given a stopped take, when record runs again, then it returns to recording")
  func givenStoppedTake_whenRecordAgain_thenRecording() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()

    rig.state.record()
    rig.runCountIn()
    rig.state.stop()
    #expect(rig.state.status == .stopped)

    rig.state.record()

    #expect(rig.state.status == .recording)
  }

  // MARK: - Playback entry

  @Test(
    "given an existing memo, when the playback state is created, then it opens on that memo and can play"
  )
  func givenExistingMemo_whenPlaybackStateCreated_thenOpensOnMemo() {
    let memo = makeMemo()

    let rig = makePlaybackRig(memo: memo)

    #expect(rig.state.status == .playback)
    #expect(rig.state.name == "Riff in D")
    #expect(rig.state.canPlay == true)
  }

  @Test(
    "given a playback state, when a blank name is committed, then the memo falls back to the default name"
  )
  func givenPlayback_whenBlankRenameCommitted_thenDefaultName() {
    let memo = makeMemo()
    let rig = makePlaybackRig(memo: memo)

    rig.state.name = "   "
    rig.state.commitRename()

    #expect(memo.name == Memo.defaultName(for: memo.createdAt))
  }

  @Test("given a playback state, when a real name is committed, then the memo takes that name")
  func givenPlayback_whenRenameCommitted_thenNamePersists() {
    let memo = makeMemo()
    let rig = makePlaybackRig(memo: memo)

    rig.state.name = "Bridge hum"
    rig.state.commitRename()

    #expect(memo.name == "Bridge hum")
  }

  // MARK: - Count-in

  @Test(
    "given permission is granted, when record is tapped, then a count-in begins on beat four with one tick and no capture"
  )
  func givenPermissionGranted_whenRecordTapped_thenCountInBeginsWithoutCapturing() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()

    rig.state.record()

    #expect(rig.state.status == .countingIn)
    #expect(rig.state.countInBeat == CaptureState.countInBeats)
    #expect(rig.ticker.tickCount == 1)
    #expect(rig.recorder.isRecording == false)
  }

  @Test(
    "given a count-in has begun, when it advances three times, then the numeral steps four to one and each beat ticks"
  )
  func givenCountInBegun_whenAdvancedThreeTimes_thenNumeralStepsDownToOne() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()

    rig.state.advanceCountIn()
    #expect(rig.state.countInBeat == 3)
    #expect(rig.ticker.tickCount == 2)

    rig.state.advanceCountIn()
    #expect(rig.state.countInBeat == 2)
    #expect(rig.ticker.tickCount == 3)

    rig.state.advanceCountIn()
    #expect(rig.state.countInBeat == 1)
    #expect(rig.ticker.tickCount == 4)

    #expect(rig.state.status == .countingIn)
    #expect(rig.recorder.isRecording == false)
  }

  @Test(
    "given the count-in is on its last beat, when it advances again, then capture starts on the downbeat without a fifth tick"
  )
  func givenCountInOnLastBeat_whenAdvanced_thenCaptureStartsOnTheDownbeat() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.state.advanceCountIn()
    rig.state.advanceCountIn()
    rig.state.advanceCountIn()

    rig.state.advanceCountIn()

    #expect(rig.state.status == .recording)
    #expect(rig.recorder.isRecording)
    #expect(rig.state.countInBeat == 0)
    #expect(rig.ticker.tickCount == CaptureState.countInBeats)
  }

  @Test(
    "given a count-in is running, when it reaches the downbeat, then nothing was captured and the timer reads zero"
  )
  func givenCountInRunning_whenItReachesTheDownbeat_thenNothingWasCaptured() async {
    // A recorder stubbed at zero stands in for "no level has arrived yet".
    let rig = makeRecordRig(stubbedDuration: 0)
    await rig.state.onAppear()
    rig.state.record()

    #expect(rig.state.elapsed == 0)
    #expect(rig.state.displayTime == 0)

    rig.state.advanceCountIn()
    rig.state.advanceCountIn()
    rig.state.advanceCountIn()
    #expect(rig.state.elapsed == 0)
    #expect(rig.state.displayTime == 0)

    rig.state.advanceCountIn()

    #expect(rig.state.status == .recording)
    #expect(rig.state.elapsed == 0)
    #expect(rig.state.displayTime == 0)
  }

  @Test(
    "given a count-in is running, when the counting button is tapped, then it returns to ready and discards the prepared take"
  )
  func givenCountInRunning_whenAborted_thenReturnsToReadyAndDiscards() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.state.advanceCountIn()

    rig.state.abortCountIn()

    #expect(rig.state.status == .ready)
    #expect(rig.state.countInBeat == 0)
    #expect(rig.recorder.isRecording == false)
    #expect(rig.store.stored.isEmpty)
    #expect(!rig.store.discardedURLs.isEmpty)
  }

  @Test(
    "given a count-in is running, when cancel is tapped, then nothing is saved, the take is discarded and the screen finishes"
  )
  func givenCountInRunning_whenCancelled_thenNothingIsSavedAndScreenFinishes() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.state.advanceCountIn()

    rig.state.cancel()

    #expect(rig.state.status != .recording)
    #expect(rig.recorder.isRecording == false)
    #expect(rig.store.stored.isEmpty)
    #expect(!rig.store.discardedURLs.isEmpty)
    #expect(rig.state.isFinished)
  }

  @Test("given a count-in was aborted, when record is tapped again, then a fresh count-in begins")
  func givenCountInAborted_whenRecordTappedAgain_thenAFreshCountInBegins() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.state.advanceCountIn()
    rig.state.abortCountIn()

    rig.state.record()

    #expect(rig.state.status == .countingIn)
    #expect(rig.state.countInBeat == CaptureState.countInBeats)
    #expect(rig.recorder.isRecording == false)
  }

  @Test(
    "given a stopped take that can still be resumed, when record is tapped, then capture resumes with no second count-in"
  )
  func givenResumableTake_whenRecordTapped_thenNoSecondCountIn() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    for _ in 0..<CaptureState.countInBeats {
      rig.state.advanceCountIn()
    }
    rig.state.stop()
    #expect(rig.state.canResume)

    rig.state.record()

    #expect(rig.state.status == .recording)
    #expect(rig.state.countInBeat == 0)
    #expect(rig.ticker.tickCount == CaptureState.countInBeats)
  }

  @Test(
    "given microphone permission is denied, when record is tapped, then no count-in starts and nothing ticks"
  )
  func givenPermissionDenied_whenRecordTapped_thenNoCountInStarts() async {
    let rig = makeRecordRig(permission: .denied)
    await rig.state.onAppear()

    rig.state.record()

    #expect(rig.state.status == .ready)
    #expect(rig.state.countInBeat == 0)
    #expect(rig.ticker.tickCount == 0)
    #expect(rig.recorder.isRecording == false)
  }

  @Test(
    "given any status other than counting in, when the count-in is advanced or aborted, then nothing changes"
  )
  func givenNotCountingIn_whenAdvancedOrAborted_thenNothingChanges() async {
    let ready = makeRecordRig()
    await ready.state.onAppear()
    ready.state.advanceCountIn()
    ready.state.abortCountIn()
    #expect(ready.state.status == .ready)
    #expect(ready.ticker.tickCount == 0)

    let recording = makeRecordRig()
    await recording.state.onAppear()
    recording.state.record()
    for _ in 0..<CaptureState.countInBeats {
      recording.state.advanceCountIn()
    }
    #expect(recording.state.status == .recording)
    recording.state.advanceCountIn()
    recording.state.abortCountIn()
    #expect(recording.state.status == .recording)
    #expect(recording.ticker.tickCount == CaptureState.countInBeats)

    let stopped = makeRecordRig()
    await stopped.state.onAppear()
    stopped.state.record()
    for _ in 0..<CaptureState.countInBeats {
      stopped.state.advanceCountIn()
    }
    stopped.state.stop()
    #expect(stopped.state.status == .stopped)
    stopped.state.advanceCountIn()
    stopped.state.abortCountIn()
    #expect(stopped.state.status == .stopped)

    let playback = makePlaybackRig(memo: makeMemo())
    playback.state.advanceCountIn()
    playback.state.abortCountIn()
    #expect(playback.state.status == .playback)
    #expect(playback.ticker.tickCount == 0)
  }

  @Test(
    "given a count-in is running, when the app goes to the background, then the count-in aborts and never matures into a capture"
  )
  func givenCountInRunning_whenBackgrounded_thenCountInAborts() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.state.advanceCountIn()

    rig.state.handleBackground()

    #expect(rig.state.status == .ready)
    #expect(rig.state.countInBeat == 0)
    #expect(rig.recorder.isRecording == false)
    #expect(rig.store.stored.isEmpty)
  }

  @Test(
    "given a count-in is running, when an interruption arrives, then the count-in aborts back to ready"
  )
  func givenCountInRunning_whenInterrupted_thenCountInAborts() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()
    rig.state.advanceCountIn()

    rig.state.handleInterruption()

    #expect(rig.state.status == .ready)
    #expect(rig.state.countInBeat == 0)
    #expect(rig.recorder.isRecording == false)
    #expect(rig.store.stored.isEmpty)
  }

  @Test(
    "given a count-in is running, when the screen is inspected, then it is live but has nothing to play"
  )
  func givenCountInRunning_whenInspected_thenLiveButNothingToPlay() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()

    rig.state.record()

    #expect(rig.state.isLive)
    #expect(rig.state.canPlay == false)
  }
}
