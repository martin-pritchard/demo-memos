import AVFoundation
import Foundation

enum MicPermission {
  case undetermined, granted, denied
}

/// Capture for one take. `pause` and `record` bracket a take without closing the
/// file, which is what makes Resume possible; `finish` finalises it and reports
/// the length actually captured.
protocol AudioRecorder: AnyObject {
  var permission: MicPermission { get }
  func requestPermission() async -> MicPermission

  var isRecording: Bool { get }
  /// Length captured so far.
  var currentTime: TimeInterval { get }

  /// Normalised 0...1 input level, emitted while capturing.
  var onLevel: ((Float) -> Void)? { get set }
  /// Call, Siri, route loss. The take must be kept, not dropped.
  var onInterruption: (() -> Void)? { get set }

  func prepare(url: URL) throws
  /// Start, or resume onto the same take.
  func record() throws
  /// Stop capturing without closing the file.
  func pause()
  /// Finalise the file. Idempotent; returns the captured length.
  @discardableResult func finish() -> TimeInterval
}

final class AVAudioRecorderAdapter: NSObject, AudioRecorder, AVAudioRecorderDelegate {
  private var recorder: AVAudioRecorder?
  private var meterTimer: Timer?
  private var finishedDuration: TimeInterval?

  var onLevel: ((Float) -> Void)?
  var onInterruption: (() -> Void)?

  var permission: MicPermission {
    switch AVAudioApplication.shared.recordPermission {
    case .granted: .granted
    case .denied: .denied
    default: .undetermined
    }
  }

  var isRecording: Bool { recorder?.isRecording ?? false }
  var currentTime: TimeInterval { finishedDuration ?? recorder?.currentTime ?? 0 }

  override init() {
    super.init()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSessionInterruption),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  func requestPermission() async -> MicPermission {
    if permission != .undetermined { return permission }
    let granted = await AVAudioApplication.requestRecordPermission()
    return granted ? .granted : .denied
  }

  func prepare(url: URL) throws {
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 44_100.0,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
    let recorder = try AVAudioRecorder(url: url, settings: settings)
    recorder.delegate = self
    recorder.isMeteringEnabled = true
    recorder.prepareToRecord()
    self.recorder = recorder
    finishedDuration = nil
  }

  func record() throws {
    try AudioSession.configureForRecording()
    recorder?.record()
    startMetering()
  }

  func pause() {
    recorder?.pause()
    stopMetering()
  }

  @discardableResult
  func finish() -> TimeInterval {
    if let finishedDuration { return finishedDuration }
    let duration = recorder?.currentTime ?? 0
    recorder?.stop()
    stopMetering()
    finishedDuration = duration
    return duration
  }

  // MARK: - Metering

  private func startMetering() {
    stopMetering()
    let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self, let recorder = self.recorder, recorder.isRecording else { return }
      recorder.updateMeters()
      self.onLevel?(Self.normalised(recorder.averagePower(forChannel: 0)))
    }
    RunLoop.main.add(timer, forMode: .common)
    meterTimer = timer
  }

  private func stopMetering() {
    meterTimer?.invalidate()
    meterTimer = nil
  }

  /// dBFS is roughly -60…0 for usable input; map that onto 0...1 with a curve
  /// that keeps quiet material visible.
  private static func normalised(_ decibels: Float) -> Float {
    let floor: Float = -55
    guard decibels > floor else { return 0 }
    return pow((decibels - floor) / -floor, 1.6)
  }

  // MARK: - Interruption

  @objc private func handleSessionInterruption(_ note: Notification) {
    guard
      let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      AVAudioSession.InterruptionType(rawValue: raw) == .began
    else { return }
    reportInterruption()
  }

  @objc private func handleRouteChange(_ note: Notification) {
    guard
      let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
    else { return }
    reportInterruption()
  }

  private func reportInterruption() {
    guard isRecording else { return }
    DispatchQueue.main.async { [weak self] in self?.onInterruption?() }
  }
}

/// One owner of session configuration, so record and playback can't fight over
/// the category.
enum AudioSession {
  static func configureForRecording() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    try session.setActive(true)
  }

  static func configureForPlayback() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)
  }
}
