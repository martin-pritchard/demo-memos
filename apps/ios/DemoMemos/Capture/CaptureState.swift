import Foundation

/// The one take view's state machine — record and playback are the same screen,
/// so they are the same state object entered at a different point.
///
///   ready → recording → stopped   (record again = resume onto the take)
///   playback                      (an existing memo reopened from the list)
///
/// Transitions are the only place capture, playback and the store meet; the
/// view reads this and emits events back, and nothing else.
@MainActor
@Observable
final class CaptureState {
  enum Status: Equatable { case ready, recording, stopped, playback }

  private(set) var status: Status
  private(set) var permission: MicPermission = .undetermined
  private(set) var elapsed: TimeInterval = 0
  /// Rolling input meter for the live waveform.
  private(set) var levels: [Float]
  /// The whole take, downsampled — what the centre-locked scrub draws.
  private(set) var takeLevels: [Float]
  private(set) var errorMessage: String?
  private(set) var isFinished = false
  private(set) var isPlaying = false

  var enhance: Double {
    didSet { if status == .playback { persistEnhance() } }
  }
  var name: String
  var progress: Double = 0

  /// Length of the take being reviewed — captured length, or the memo's.
  private(set) var takeDuration: TimeInterval = 0

  private let store: MemoStore
  private let recorder: AudioRecorder
  private let player: AudioPlayer
  private let now: () -> Date

  private let memo: Memo?
  private var recordingURL: URL?
  private var startedAt: Date?
  private var ticker: Timer?
  private var levelsSinceLastSample = 0

  /// How many meter readings make one bar of the stored take waveform. The live
  /// meter runs at 20 Hz, so this samples the take at ~4 Hz.
  private static let samplesPerTakeBar = 5
  static let liveBarCount = 48

  // MARK: - Entry points

  /// Record flow — nothing captured yet.
  init(
    store: MemoStore,
    recorder: AudioRecorder,
    player: AudioPlayer,
    now: @escaping () -> Date = Date.init
  ) {
    self.store = store
    self.recorder = recorder
    self.player = player
    self.now = now
    self.memo = nil
    self.status = .ready
    self.name = Memo.defaultName(for: now())
    self.enhance = 0.5
    // A flat resting line: ready is not capturing, so the waveform must not
    // look like it is reacting to anything.
    self.levels = Array(repeating: 0.05, count: Self.liveBarCount)
    self.takeLevels = []
    self.permission = recorder.permission
    observeRecorder()
  }

  /// Playback — an existing memo, reopened. This entry point never captures.
  init(
    memo: Memo,
    store: MemoStore,
    recorder: AudioRecorder,
    player: AudioPlayer,
    now: @escaping () -> Date = Date.init
  ) {
    self.store = store
    self.recorder = recorder
    self.player = player
    self.now = now
    self.memo = memo
    self.status = .playback
    self.name = memo.name
    self.enhance = memo.enhance
    self.levels = Array(repeating: 0, count: Self.liveBarCount)
    self.takeDuration = memo.duration
    // Level data is not part of the index, so a reopened take draws a stable
    // stand-in derived from its id. See DECISIONS.md.
    self.takeLevels = Self.placeholderLevels(seed: memo.id)
    try? player.load(url: store.fileURL(for: memo))
    player.onFinish = { [weak self] in
      MainActor.assumeIsolated { self?.handlePlaybackFinished() }
    }
  }

  // MARK: - Lifecycle

  func onAppear() async {
    guard status != .playback else { return }
    permission = await recorder.requestPermission()
  }

  func onDisappear() {
    stopTicker()
    player.pause()
    isPlaying = false
  }

  // MARK: - Derived

  var canRecord: Bool { permission == .granted }
  var canPlay: Bool { status == .playback || takeDuration > 0 }
  var isLive: Bool { status == .ready || status == .recording }

  /// The playable `.m4a` behind the share sheet.
  var shareURL: URL? {
    if let memo { return store.fileURL(for: memo) }
    return recordingURL
  }

  /// The time the transport reads: elapsed while capturing, playhead otherwise.
  var displayTime: TimeInterval {
    isLive ? elapsed : progress * takeDuration
  }

  // MARK: - Events

  func record() {
    guard status == .ready || status == .stopped else { return }
    guard canRecord else { return }
    errorMessage = nil
    if recordingURL == nil {
      let url = store.newRecordingURL()
      do {
        try recorder.prepare(url: url)
      } catch {
        errorMessage = "Couldn't start recording."
        return
      }
      recordingURL = url
      startedAt = now()
    }
    stopPlayback()
    do {
      try recorder.record()
    } catch {
      errorMessage = "Couldn't start recording."
      return
    }
    status = .recording
    startTicker()
  }

  func stop() {
    guard status == .recording else { return }
    recorder.pause()
    stopTicker()
    takeDuration = recorder.currentTime
    elapsed = takeDuration
    progress = 1
    status = .stopped
  }

  func togglePlay() {
    guard canPlay else { return }
    if isPlaying {
      stopPlayback()
      return
    }
    if progress >= 1 { progress = 0 }
    if status == .stopped {
      // Finalise so there is a readable file to preview, then reload it.
      let duration = recorder.finish()
      if duration > 0 { takeDuration = duration }
      if let recordingURL { try? player.load(url: recordingURL) }
      player.onFinish = { [weak self] in
        MainActor.assumeIsolated { self?.handlePlaybackFinished() }
      }
    }
    player.currentTime = progress * takeDuration
    player.play()
    isPlaying = true
    startTicker()
  }

  /// Drag on the waveform — the playhead is centre-locked, the take moves.
  func scrub(to value: Double) {
    progress = min(max(value, 0), 1)
    player.currentTime = progress * takeDuration
  }

  func cancel() {
    stopPlayback()
    stopTicker()
    recorder.finish()
    if let recordingURL { store.discard(recordingAt: recordingURL) }
    recordingURL = nil
    isFinished = true
  }

  func done() {
    stopPlayback()
    stopTicker()

    if status == .playback {
      commitRename()
      isFinished = true
      return
    }

    guard let recordingURL else {
      isFinished = true
      return
    }
    let duration = recorder.finish()
    do {
      try store.commit(
        recordingAt: recordingURL,
        duration: duration,
        enhance: enhance,
        createdAt: startedAt ?? now()
      )
      errorMessage = nil
      self.recordingURL = nil
      isFinished = true
    } catch {
      // Stay in `stopped` with the take intact so Done can be retried.
      status = .stopped
      errorMessage = "Couldn't save this demo. Try again."
    }
  }

  func commitRename() {
    guard let memo else { return }
    try? store.rename(memo, to: name)
    name = memo.name
  }

  /// Call, Siri, route loss — auto-stop and keep whatever was captured.
  func handleInterruption() {
    guard status == .recording else { return }
    stop()
  }

  /// Backgrounded mid-take. Same rule: stop and keep.
  func handleBackground() {
    guard status == .recording else { return }
    stop()
  }

  // MARK: - Internals

  private func observeRecorder() {
    recorder.onLevel = { [weak self] level in
      MainActor.assumeIsolated { self?.appendLevel(level) }
    }
    recorder.onInterruption = { [weak self] in
      MainActor.assumeIsolated { self?.handleInterruption() }
    }
  }

  private func appendLevel(_ level: Float) {
    levels.removeFirst()
    levels.append(level)
    elapsed = recorder.currentTime
    levelsSinceLastSample += 1
    if levelsSinceLastSample >= Self.samplesPerTakeBar {
      levelsSinceLastSample = 0
      takeLevels.append(level)
    }
  }

  private func startTicker() {
    stopTicker()
    let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    ticker = timer
  }

  private func stopTicker() {
    ticker?.invalidate()
    ticker = nil
  }

  private func tick() {
    if status == .recording {
      elapsed = recorder.currentTime
    } else if isPlaying, takeDuration > 0 {
      progress = min(player.currentTime / takeDuration, 1)
    }
  }

  private func stopPlayback() {
    guard isPlaying else { return }
    player.pause()
    isPlaying = false
    if status != .recording { stopTicker() }
  }

  private func handlePlaybackFinished() {
    isPlaying = false
    progress = 1
    stopTicker()
  }

  private func persistEnhance() {
    guard let memo else { return }
    try? store.setEnhance(enhance, on: memo)
  }

  /// A stable, take-shaped stand-in so a reopened memo has something to scrub.
  private static func placeholderLevels(seed: UUID) -> [Float] {
    var value = UInt64(truncatingIfNeeded: seed.hashValue) | 1
    let count = 220
    return (0..<count).map { index in
      value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let random = Float(value >> 40) / Float(1 << 24)
      let envelope = Float(sin(Double(index) / Double(count) * .pi))
      return 0.12 + (0.25 + random * 0.75) * (0.45 + envelope * 0.55)
    }
  }
}
