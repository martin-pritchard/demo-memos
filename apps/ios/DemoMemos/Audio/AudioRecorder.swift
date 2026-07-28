import AVFAudio
import Foundation

nonisolated enum MicrophonePermission: Equatable {
  case undetermined
  case denied
  case granted
}

/// Why a take ended. Every one of these leaves a finalised, playable file.
nonisolated enum StopReason: Equatable {
  /// The user tapped stop.
  case user
  /// A call, Siri, or an alarm took the session.
  case interrupted
  /// Headphones or an interface went away mid-take.
  case routeLost
  /// The media server died and took the session, recorder and player with it.
  case mediaServicesReset
  case failed(String)
}

/// The capture seam. See `docs/PRINCIPLES.ios.md` #3 — the fake half lives in
/// `Fakes.swift` and is what every test and preview runs on.
@MainActor
protocol Recording: AnyObject {
  var permission: MicrophonePermission { get }
  var isRecording: Bool { get }
  /// Fires exactly once per take, whatever ended it.
  var onStop: ((StopReason, URL) -> Void)? { get set }

  func requestPermission() async -> MicrophonePermission
  func start(to url: URL) throws
  func stop()
}

/// `AVAudioRecorder` over a `.measurement` session.
///
/// Rung 2 of the `ios-audio` ladder, chosen deliberately: nothing here needs
/// sample access, and `AVAudioRecorder` has no realtime callback at all, so the
/// hazards in `docs/PRINCIPLES.ios.md` #1 cannot arise. It is also the safer
/// choice for "never corrupt" — `stop()` finalises the RIFF header for us,
/// where a hand-rolled engine tap would have to patch it by hand.
@MainActor
final class AudioRecorder: NSObject, Recording {

  var onStop: ((StopReason, URL) -> Void)?

  private var recorder: AVAudioRecorder?
  private var takeURL: URL?
  private var observers: [NSObjectProtocol] = []

  var isRecording: Bool { recorder != nil }

  var permission: MicrophonePermission {
    switch AVAudioApplication.shared.recordPermission {
    case .granted: .granted
    case .denied: .denied
    default: .undetermined
    }
  }

  /// iOS 17+ API. The `AVAudioSession` equivalents are deprecated.
  func requestPermission() async -> MicrophonePermission {
    let granted = await AVAudioApplication.requestRecordPermission()
    return granted ? .granted : .denied
  }

  func start(to url: URL) throws {
    guard recorder == nil else { return }

    try AudioSession.activateForCapture()

    let recorder = try AVAudioRecorder(url: url, settings: AudioSession.recorderSettings)
    recorder.delegate = self
    guard recorder.record() else {
      throw AudioSession.Failure.configuration("AVAudioRecorder refused to start")
    }

    self.recorder = recorder
    self.takeURL = url
    observeSessionEvents()
  }

  func stop() {
    finish(.user)
  }

  /// The single exit. Idempotent by construction, which matters more than it
  /// looks: unplugging headphones raises *both* an interruption (reason
  /// `.routeDisconnected`) and a route change (reason `.oldDeviceUnavailable`)
  /// for one physical event, so this is called twice for one take.
  private func finish(_ reason: StopReason) {
    guard let recorder, let takeURL else { return }
    self.recorder = nil
    self.takeURL = nil

    recorder.stop()  // writes the real RIFF and data chunk sizes
    stopObserving()
    onStop?(reason, takeURL)
  }

  // MARK: - Session events

  private func observeSessionEvents() {
    let centre = NotificationCenter.default
    observers = [
      centre.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated { self?.handleInterruption(note) }
      },
      centre.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated { self?.handleRouteChange(note) }
      },
      centre.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.finish(.mediaServicesReset) }
      },
    ]
  }

  private func stopObserving() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
  }

  private func handleInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      let type = AVAudioSession.InterruptionType(rawValue: raw)
    else { return }

    // `.ended` is deliberately ignored: an interruption ends the take, and the
    // user starts a new one. Auto-resuming risks silently failing to reactivate
    // while the UI still says "recording", which is worse than a short take.
    guard type == .began else { return }

    let reason = (note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt)
      .flatMap(AVAudioSession.InterruptionReason.init(rawValue:))
    finish(reason == .routeDisconnected ? .routeLost : .interrupted)
  }

  private func handleRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
      reason == .oldDeviceUnavailable
    else { return }
    finish(.routeLost)
  }
}

extension AudioRecorder: AVAudioRecorderDelegate {

  nonisolated func audioRecorderEncodeErrorDidOccur(
    _ recorder: AVAudioRecorder, error: (any Error)?
  ) {
    let message = error?.localizedDescription ?? "unknown encoding error"
    Task { @MainActor [weak self] in self?.finish(.failed(message)) }
  }
}
