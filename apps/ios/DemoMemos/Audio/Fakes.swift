import Core
import Foundation

/// The fake halves of the audio seams, and the named scenarios that previews and
/// tests run on. See `docs/PRINCIPLES.ios.md` #3: a seam without both halves is
/// a defect, not a shortcut.
///
/// These are in the app target rather than the test target on purpose — a
/// `#Preview` cannot reach the test bundle, and every state in the screen has to
/// be reachable without a microphone.

@MainActor
final class FakeRecorder: Recording {

  var permission: MicrophonePermission
  var isRecording = false
  var onStop: ((StopReason, URL) -> Void)?

  /// Set to have `start(to:)` throw, to exercise the surfaced-failure path.
  var startFailure: (any Error)?
  /// What `requestPermission()` resolves to when permission is undetermined.
  var permissionOnRequest: MicrophonePermission = .granted
  /// Holds `requestPermission()` suspended until ``resumePrompt()``, so a test
  /// can land a second record tap while the prompt is genuinely in flight. Only
  /// the first call is held — a second returns straight away, so a regression
  /// fails an expectation instead of deadlocking the suite.
  var holdsPrompt = false

  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var permissionRequestCount = 0
  private(set) var startedURLs: [URL] = []

  private var pendingPrompt: CheckedContinuation<Void, Never>?

  init(permission: MicrophonePermission = .granted) {
    self.permission = permission
  }

  func requestPermission() async -> MicrophonePermission {
    permissionRequestCount += 1
    if holdsPrompt, permissionRequestCount == 1 {
      await withCheckedContinuation { pendingPrompt = $0 }
    }
    permission = permissionOnRequest
    return permission
  }

  /// Answers a prompt held by ``holdsPrompt``.
  func resumePrompt() {
    pendingPrompt?.resume()
    pendingPrompt = nil
  }

  func start(to url: URL) throws {
    if let startFailure { throw startFailure }
    startCount += 1
    startedURLs.append(url)
    isRecording = true
  }

  func stop() {
    finish(.user)
  }

  /// Drives the paths a microphone would otherwise be needed for. Idempotent in
  /// the same way the real recorder is, so a test can fire two events for one
  /// physical disconnect and assert a single stop.
  func simulate(_ reason: StopReason) {
    finish(reason)
  }

  private func finish(_ reason: StopReason) {
    guard isRecording, let url = startedURLs.last else { return }
    isRecording = false
    stopCount += 1
    onStop?(reason, url)
  }
}

@MainActor
final class FakePlayer: Playing {

  var isPlaying = false
  var onFinish: (() -> Void)?

  var playFailure: (any Error)?

  private(set) var playCount = 0
  private(set) var stopCount = 0
  private(set) var playedURLs: [URL] = []
  /// The last warmth pushed to the player, clamped as the real one clamps.
  private(set) var lastWarmth: Double = 0

  /// What a "decoded" take looks like here. Set it before `play` to give the
  /// fake a take with a length; the real player learns this by decoding.
  var duration: TimeInterval = 0

  private(set) var position: TimeInterval = 0
  /// Every seek the screen asked for, in order.
  private(set) var seekedTo: [TimeInterval] = []

  func play(_ url: URL) throws {
    if let playFailure { throw playFailure }
    playCount += 1
    playedURLs.append(url)
    isPlaying = true
    // Mirrors the real player: a take parked at its end restarts from the top.
    if position >= duration { position = 0 }
  }

  func seek(to position: TimeInterval) {
    let clamped = min(max(position, 0), duration)
    seekedTo.append(clamped)
    self.position = clamped
  }

  /// Advance the playhead as if the take had been playing for `interval`.
  func simulatePlaying(for interval: TimeInterval) {
    position = min(position + interval, duration)
  }

  func stop() {
    guard isPlaying else { return }
    isPlaying = false
    stopCount += 1
  }

  func setWarmth(_ value: Double) {
    lastWarmth = min(max(value, 0), 1)
  }

  /// Playback reaching the end of the take. Parks the playhead at the end, as
  /// the real player does.
  func simulateFinished() {
    guard isPlaying else { return }
    isPlaying = false
    position = duration
    onFinish?()
  }

  /// Playback cut short by a call, Siri, route loss, or media reset — the real
  /// player fires `onFinish` for all of these, the same as reaching the end.
  func simulateInterrupted() {
    guard isPlaying else { return }
    isPlaying = false
    onFinish?()
  }
}

// MARK: - Named scenarios

extension CaptureState {

  private static var sampleFolder: URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Recordings")
  }

  private static var sampleTake: URL {
    sampleFolder.appending(path: "take-20260728-135712.wav")
  }

  /// Permission granted, nothing recorded yet — the first-launch state.
  static var empty: CaptureState {
    CaptureState(recorder: FakeRecorder(), player: FakePlayer(), folder: sampleFolder)
  }

  /// One take on disk, idle.
  static var populated: CaptureState {
    CaptureState(
      recorder: FakeRecorder(), player: FakePlayer(), folder: sampleFolder,
      latestTake: sampleTake)
  }

  /// Mid-take.
  static var recording: CaptureState {
    let state = CaptureState(
      recorder: FakeRecorder(), player: FakePlayer(), folder: sampleFolder)
    Task { await state.recordTapped() }
    return state
  }

  /// Playing the most recent take back.
  static var playing: CaptureState {
    let state = populated
    state.playTapped()
    return state
  }

  /// Microphone refused — the screen still loads, record is disabled.
  static var denied: CaptureState {
    let state = CaptureState(
      recorder: FakeRecorder(permission: .denied), player: FakePlayer(), folder: sampleFolder)
    Task { await state.recordTapped() }
    return state
  }

  /// A take cut short by a phone call, and the line of text that explains it.
  static var interrupted: CaptureState {
    let recorder = FakeRecorder()
    let state = CaptureState(
      recorder: recorder, player: FakePlayer(), folder: sampleFolder)
    Task {
      await state.recordTapped()
      recorder.simulate(.interrupted)
    }
    return state
  }
}
