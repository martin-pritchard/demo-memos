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

  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var permissionRequestCount = 0
  private(set) var startedURLs: [URL] = []

  init(permission: MicrophonePermission = .granted) {
    self.permission = permission
  }

  func requestPermission() async -> MicrophonePermission {
    permissionRequestCount += 1
    permission = permissionOnRequest
    return permission
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

  func play(_ url: URL) throws {
    if let playFailure { throw playFailure }
    playCount += 1
    playedURLs.append(url)
    isPlaying = true
  }

  func stop() {
    guard isPlaying else { return }
    isPlaying = false
    stopCount += 1
  }

  /// Playback reaching the end of the take.
  func simulateFinished() {
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
