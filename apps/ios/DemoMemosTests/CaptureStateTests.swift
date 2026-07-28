import Foundation
import Testing

@testable import DemoMemos

/// Runs entirely on the fakes: no session, no microphone, no files.
@MainActor
struct CaptureStateTests {

  private static func make(
    permission: MicrophonePermission = .granted,
    latestTake: URL? = nil
  ) -> (CaptureState, FakeRecorder, FakePlayer) {
    let recorder = FakeRecorder(permission: permission)
    let player = FakePlayer()
    let state = CaptureState(
      recorder: recorder,
      player: player,
      folder: URL.temporaryDirectory.appending(path: "Recordings"),
      latestTake: latestTake,
      now: { Date(timeIntervalSince1970: 1_785_000_000) })
    return (state, recorder, player)
  }

  // MARK: - Recording

  @Test func recordTapStartsATake() async {
    let (state, recorder, _) = Self.make()

    await state.recordTapped()

    #expect(state.mode == .recording)
    #expect(recorder.startCount == 1)
    #expect(recorder.startedURLs.first?.pathExtension == "wav")
  }

  @Test func recordTapWhileRecordingStopsAndKeepsTheTake() async {
    let (state, recorder, _) = Self.make()
    await state.recordTapped()

    await state.recordTapped()

    #expect(state.mode == .idle)
    #expect(recorder.stopCount == 1)
    #expect(state.latestTake != nil)
    #expect(state.notice == nil, "a take the user ended needs no explanation")
  }

  /// Given a take in progress, when a call arrives, then the take is kept and
  /// the screen says so.
  @Test func interruptionEndsTheTakeAndKeepsTheFile() async {
    let (state, recorder, _) = Self.make()
    await state.recordTapped()

    recorder.simulate(.interrupted)

    #expect(state.mode == .idle)
    #expect(state.latestTake != nil)
    #expect(state.notice == "Interrupted. Your take was saved.")
  }

  /// Unplugging headphones raises *both* an interruption with reason
  /// `.routeDisconnected` and a route change with reason `.oldDeviceUnavailable`.
  /// One physical event must end one take, once.
  @Test func oneDisconnectEndsOneTakeOnce() async {
    let (state, recorder, _) = Self.make()
    await state.recordTapped()

    recorder.simulate(.routeLost)
    recorder.simulate(.routeLost)

    #expect(recorder.stopCount == 1)
    #expect(state.mode == .idle)
    #expect(state.notice == "Audio device disconnected. Your take was saved.")
  }

  @Test func mediaServicesResetKeepsTheTake() async {
    let (state, recorder, _) = Self.make()
    await state.recordTapped()

    recorder.simulate(.mediaServicesReset)

    #expect(state.mode == .idle)
    #expect(state.latestTake != nil)
    #expect(state.notice == "The audio system restarted. Your take was saved.")
  }

  // MARK: - Permission

  @Test func deniedPermissionBlocksRecordingAndExplains() async {
    let (state, recorder, _) = Self.make(permission: .denied)

    await state.recordTapped()

    #expect(recorder.startCount == 0)
    #expect(state.mode == .idle)
    #expect(state.canRecord == false)
    #expect(state.isDenied)
    #expect(state.notice?.contains("Settings") == true)
  }

  /// The prompt belongs on the first tap on record, not on launch.
  @Test func permissionIsRequestedOnFirstRecordTapOnly() async {
    let (state, recorder, _) = Self.make(permission: .undetermined)
    #expect(recorder.permissionRequestCount == 0, "nothing asked at construction")

    await state.recordTapped()
    #expect(recorder.permissionRequestCount == 1)
    #expect(recorder.startCount == 1)

    await state.recordTapped()  // stop
    await state.recordTapped()  // start again
    #expect(recorder.permissionRequestCount == 1, "already answered")
  }

  @Test func refusedPromptDoesNotRecord() async {
    let (state, recorder, _) = Self.make(permission: .undetermined)
    recorder.permissionOnRequest = .denied

    await state.recordTapped()

    #expect(recorder.startCount == 0)
    #expect(state.isDenied)
  }

  // MARK: - Format

  /// A route that grants something other than 48 kHz mono must be surfaced, not
  /// silently recorded — that is the whole point of reading the grant back.
  @Test func unexpectedFormatIsSurfacedAndNothingIsRecorded() async {
    let (state, recorder, _) = Self.make()
    recorder.startFailure = AudioSession.Failure.unexpectedFormat(
      granted: .init(sampleRate: 44_100, inputChannels: 1),
      wanted: AudioSession.wanted)

    await state.recordTapped()

    #expect(state.mode == .idle)
    #expect(state.latestTake == nil)
    #expect(state.notice?.contains("44100") == true)
    #expect(state.notice?.contains("48000") == true)
  }

  // MARK: - Playback

  @Test func playIsUnavailableUntilThereIsATake() async {
    let (state, _, player) = Self.make()

    #expect(state.canPlay == false)
    state.playTapped()
    #expect(player.playCount == 0)
  }

  @Test func playPlaysTheLatestTakeAndReturnsToIdleAtTheEnd() async {
    let take = URL.temporaryDirectory.appending(path: "take-20260728-135712.wav")
    let (state, _, player) = Self.make(latestTake: take)

    state.playTapped()
    #expect(state.mode == .playing)
    #expect(player.playedURLs == [take])

    player.simulateFinished()
    #expect(state.mode == .idle)
  }

  @Test func recordingIsNotOfferedPlaybackMidTake() async {
    let (state, _, _) = Self.make(latestTake: URL.temporaryDirectory.appending(path: "old.wav"))

    await state.recordTapped()

    #expect(state.canPlay == false, "no playing over a live take")
  }

  @Test func playTapWhilePlayingStops() async {
    let take = URL.temporaryDirectory.appending(path: "take.wav")
    let (state, _, player) = Self.make(latestTake: take)
    state.playTapped()

    state.playTapped()

    #expect(state.mode == .idle)
    #expect(player.stopCount == 1)
  }
}
