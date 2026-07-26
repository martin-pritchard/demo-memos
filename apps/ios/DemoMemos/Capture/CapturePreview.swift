import Foundation

/// Named scenarios that put the take screen into each state in 1d without a
/// microphone, a file or a database — the previews' only source of data.
@MainActor
enum CapturePreview {
  static func state(
    _ status: CaptureState.Status,
    permission: MicPermission = .granted,
    enhance: Double = 0.5
  ) -> CaptureState {
    let recorder = FakeAudioRecorder()
    recorder.permission = permission
    recorder.stubbedDuration = 37
    let state = CaptureState(
      store: FakeMemoStore(),
      recorder: recorder,
      player: FakeAudioPlayer(),
      countInTicker: FakeCountInTicker(),
      now: { Date(timeIntervalSince1970: 1_753_200_000) }
    )
    state.enhance = enhance

    switch status {
    case .ready, .playback:
      break
    case .countingIn:
      // Left running, so the preview counts 4·3·2·1 for real and the beat
      // animation can be checked against 8a — it just does it silently.
      state.record()
    case .recording, .stopped:
      state.record()
      runCountIn(state)
      for level in sampleLevels(count: 240) { recorder.simulateLevel(level) }
      if status == .stopped { state.stop() }
    }
    return state
  }

  /// Skip past the count-in to the downbeat without waiting on the clock.
  private static func runCountIn(_ state: CaptureState) {
    for _ in 0..<CaptureState.countInBeats { state.advanceCountIn() }
  }

  static func playbackState(enhance: Double = 0.5) -> CaptureState {
    let memo = PreviewScenario.sampleMemo
    memo.enhance = enhance
    let state = CaptureState(
      memo: memo,
      store: FakeMemoStore(memos: [memo]),
      recorder: FakeAudioRecorder(),
      player: FakeAudioPlayer(),
      countInTicker: FakeCountInTicker(),
      now: { Date(timeIntervalSince1970: 1_753_200_000) }
    )
    state.progress = 0.32
    return state
  }

  /// The disk-write failure: still in `stopped`, with the inline error.
  static func failedSaveState() -> CaptureState {
    let store = FakeMemoStore()
    store.failOnCommit = true
    let recorder = FakeAudioRecorder()
    recorder.stubbedDuration = 37
    let state = CaptureState(
      store: store,
      recorder: recorder,
      player: FakeAudioPlayer(),
      countInTicker: FakeCountInTicker(),
      now: { Date(timeIntervalSince1970: 1_753_200_000) }
    )
    state.record()
    runCountIn(state)
    for level in sampleLevels(count: 240) { recorder.simulateLevel(level) }
    state.stop()
    state.done()
    return state
  }

  /// A take-shaped level series — deterministic, so previews never flicker.
  private static func sampleLevels(count: Int) -> [Float] {
    var value: UInt64 = 7
    return (0..<count).map { index in
      value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let random = Float(value >> 40) / Float(1 << 24)
      let envelope = Float(sin(Double(index) / Double(count) * .pi))
      return 0.12 + (0.25 + random * 0.75) * (0.45 + envelope * 0.55)
    }
  }
}
