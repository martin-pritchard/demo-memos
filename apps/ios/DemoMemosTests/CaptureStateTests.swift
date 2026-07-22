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
    let state: CaptureState
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
    let state = CaptureState(
      store: store,
      recorder: recorder,
      player: player,
      now: { Self.fixedNow() }
    )
    return Rig(store: store, recorder: recorder, player: player, state: state)
  }

  /// Playback-flow rig: a `CaptureState` opened on an existing memo.
  private func makePlaybackRig(memo: Memo) -> Rig {
    let store = FakeMemoStore()
    let recorder = FakeAudioRecorder()
    let player = FakeAudioPlayer()
    let state = CaptureState(
      memo: memo,
      store: store,
      recorder: recorder,
      player: player,
      now: { Self.fixedNow() }
    )
    return Rig(store: store, recorder: recorder, player: player, state: state)
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

    rig.recorder.simulateInterruption()

    #expect(rig.state.status == .stopped)
    #expect(rig.state.canPlay == true)
  }

  @Test("given a recording in progress, when the app is backgrounded, then the take is stopped")
  func givenRecording_whenBackgrounded_thenStopped() async {
    let rig = makeRecordRig()
    await rig.state.onAppear()
    rig.state.record()

    rig.state.handleBackground()

    #expect(rig.state.status == .stopped)
  }

  // MARK: - Done

  @Test("given a zero-length take, when done runs, then nothing is saved and the screen finishes")
  func givenZeroLengthTake_whenDone_thenNothingSaved() async {
    let rig = makeRecordRig(stubbedDuration: 0)
    await rig.state.onAppear()

    rig.state.record()
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
}
