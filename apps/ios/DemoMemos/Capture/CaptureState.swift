import Foundation

/// The one take view's state machine — record and playback are the same screen,
/// so they are the same state object entered at a different point.
///
///   ready → countingIn → recording → stopped   (record again = resume onto the take)
///   playback                                   (an existing memo reopened from the list)
///
/// Transitions are the only place capture, playback and the store meet; the
/// view reads this and emits events back, and nothing else.
@MainActor
@Observable
final class CaptureState {
  enum Status: Equatable { case ready, countingIn, recording, stopped, playback }

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
  /// True once the recording file has been closed and can no longer be appended to.
  private(set) var isFinalised = false
  /// The numeral the record button is showing — 4·3·2·1 while counting in, 0 otherwise.
  private(set) var countInBeat = 0

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
  private let countInTicker: CountInTicker
  private let now: () -> Date

  private let memo: Memo?
  private var recordingURL: URL?
  private var startedAt: Date?
  private var ticker: Timer?
  private var countInTimer: Timer?
  private var levelsSinceLastSample = 0

  /// How many meter readings make one bar of the stored take waveform. The live
  /// meter runs at 20 Hz, so this samples the take at ~4 Hz.
  private static let samplesPerTakeBar = 5
  static let liveBarCount = 48

  /// One bar of 4/4 at one beat a second, counted down inside the ring (8a).
  static let countInBeats = 4
  static let countInInterval: TimeInterval = 1

  // MARK: - Entry points

  /// Record flow — nothing captured yet.
  init(
    store: MemoStore,
    recorder: AudioRecorder,
    player: AudioPlayer,
    countInTicker: CountInTicker,
    now: @escaping () -> Date = Date.init
  ) {
    self.store = store
    self.recorder = recorder
    self.player = player
    self.countInTicker = countInTicker
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
    countInTicker: CountInTicker,
    now: @escaping () -> Date = Date.init
  ) {
    self.store = store
    self.recorder = recorder
    self.player = player
    self.countInTicker = countInTicker
    self.now = now
    self.memo = memo
    self.status = .playback
    self.name = memo.name
    self.enhance = memo.enhance
    self.levels = Array(repeating: 0, count: Self.liveBarCount)
    self.takeDuration = memo.duration
    // Level data is not part of the index, so a reopened take draws a stable
    // stand-in derived from its id. See docs/DECISIONS.md.
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
    // "Commit on return or dismiss" includes an interactive swipe-back, which
    // never touches the Demos button.
    if status == .playback { commitRename() }
    stopTicker()
    stopCountInTimer()
    player.pause()
    isPlaying = false
  }

  // MARK: - Derived

  var canRecord: Bool { permission == .granted }
  var canPlay: Bool { status == .playback || takeDuration > 0 }
  var isLive: Bool { status == .ready || status == .countingIn || status == .recording }

  /// Resume appends to the take by un-pausing the recorder, so it is only
  /// available while the file is still open. Previewing the take closes it —
  /// appending to a finalised file would mean stitching segments together, and
  /// that is 3a's job, not this issue's. Playback never captures at all.
  var canResume: Bool { status == .stopped && !isFinalised }

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

  /// Tapping the record button. A fresh take is counted in first; Resume is
  /// not — it is appending to a take already under way, and being counted in
  /// again would put four silent beats in the middle of it.
  func record() {
    guard status == .ready || canResume else { return }
    guard canRecord else { return }
    errorMessage = nil
    if canResume {
      beginCapture()
      return
    }
    // Prepared up front so the take starts on the beat rather than after the
    // file is opened — and so a failure surfaces now, not four beats later.
    guard prepareRecording() else { return }
    status = .countingIn
    countInBeat = Self.countInBeats
    countInTicker.tick()
    startCountInTimer()
  }

  /// One beat of the count-in — 4·3·2·1, then the downbeat, which is the first
  /// captured moment. Driven by a 1 s timer; a plain method so the whole
  /// count-in is testable without waiting on the clock.
  func advanceCountIn() {
    guard status == .countingIn else { return }
    if countInBeat > 1 {
      countInBeat -= 1
      countInTicker.tick()
      return
    }
    // The downbeat is the take, not a fifth tick.
    stopCountInTimer()
    countInBeat = 0
    if !beginCapture() { status = .ready }
  }

  /// Tapping the counting button — abort with nothing captured and nothing left
  /// on disk, back to where the tap came from.
  func abortCountIn() {
    guard status == .countingIn else { return }
    endCountIn()
    discardPreparedRecording()
    status = .ready
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
    if status == .stopped, !isFinalised {
      // A part-written `.m4a` is not readable, so previewing has to close the
      // file. That is what ends the window for Resume — see `canResume`.
      let duration = recorder.finish()
      isFinalised = true
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
    endCountIn()
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
    // The file is closed now, so a failed save cannot be followed by a Resume.
    isFinalised = true
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

  /// Call, Siri, route loss — auto-stop and keep whatever was captured. Nothing
  /// is captured yet during a count-in, so that just aborts.
  func handleInterruption() {
    if status == .countingIn {
      abortCountIn()
      return
    }
    guard status == .recording else { return }
    stop()
  }

  /// Backgrounded mid-take. Same rule: stop and keep — and a count-in must
  /// never mature into a capture behind the user's back.
  func handleBackground() {
    if status == .countingIn {
      abortCountIn()
      return
    }
    guard status == .recording else { return }
    stop()
  }

  // MARK: - Internals

  /// Opens the file for a fresh take. Reused as-is if one is already prepared.
  private func prepareRecording() -> Bool {
    guard recordingURL == nil else { return true }
    let url = store.newRecordingURL()
    do {
      try recorder.prepare(url: url)
    } catch {
      errorMessage = "Couldn't start recording."
      return false
    }
    recordingURL = url
    return true
  }

  /// The downbeat, and the resume path — the only place capture actually starts.
  @discardableResult
  private func beginCapture() -> Bool {
    stopPlayback()
    do {
      try recorder.record()
    } catch {
      errorMessage = "Couldn't start recording."
      return false
    }
    if startedAt == nil { startedAt = now() }
    status = .recording
    startTicker()
    return true
  }

  private func endCountIn() {
    stopCountInTimer()
    countInBeat = 0
  }

  /// A take that was counted in but never started leaves an empty file behind.
  private func discardPreparedRecording() {
    recorder.finish()
    if let recordingURL { store.discard(recordingAt: recordingURL) }
    recordingURL = nil
    startedAt = nil
  }

  private func startCountInTimer() {
    stopCountInTimer()
    let timer = Timer(timeInterval: Self.countInInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.advanceCountIn() }
    }
    RunLoop.main.add(timer, forMode: .common)
    countInTimer = timer
  }

  private func stopCountInTimer() {
    countInTimer?.invalidate()
    countInTimer = nil
  }

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
