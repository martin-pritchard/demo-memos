import Foundation

/// In-memory stand-ins for every service, so each state in the design is
/// reachable in a preview with no microphone, no files and no database — and so
/// the state machine can be tested without any of them either.

// MARK: - Recorder

final class FakeAudioRecorder: AudioRecorder {
  var permission: MicPermission = .granted
  /// What `finish()` reports, and what `currentTime` reads once recording.
  var stubbedDuration: TimeInterval = 4.2

  private(set) var isRecording = false
  private(set) var preparedURL: URL?
  private var didRecord = false

  var onLevel: ((Float) -> Void)?
  var onInterruption: (() -> Void)?

  var currentTime: TimeInterval { didRecord ? stubbedDuration : 0 }

  func requestPermission() async -> MicPermission { permission }

  func prepare(url: URL) throws { preparedURL = url }

  func record() throws {
    isRecording = true
    didRecord = true
  }

  func pause() { isRecording = false }

  @discardableResult
  func finish() -> TimeInterval {
    isRecording = false
    return didRecord ? stubbedDuration : 0
  }

  func simulateInterruption() { onInterruption?() }

  func simulateLevel(_ level: Float) { onLevel?(level) }
}

// MARK: - Player

final class FakeAudioPlayer: AudioPlayer {
  var stubbedDuration: TimeInterval = 4.2

  private(set) var isPlaying = false
  var currentTime: TimeInterval = 0
  var duration: TimeInterval { stubbedDuration }
  var onFinish: (() -> Void)?

  func load(url: URL) throws {}
  func play() { isPlaying = true }
  func pause() { isPlaying = false }

  func simulateFinish() {
    isPlaying = false
    onFinish?()
  }
}

// MARK: - Store

final class FakeMemoStore: MemoStore {
  private(set) var stored: [Memo] = []
  var failOnCommit = false
  private(set) var discardedURLs: [URL] = []

  private let directory = URL.temporaryDirectory.appending(path: "FakeMemoStore")

  init() {}

  init(memos: [Memo]) {
    stored = memos.sorted { $0.createdAt > $1.createdAt }
  }

  func memos() throws -> [Memo] { stored }

  func fileURL(for memo: Memo) -> URL { directory.appending(path: memo.filename) }

  func newRecordingURL() -> URL { directory.appending(path: "\(UUID().uuidString).m4a") }

  @discardableResult
  func commit(
    recordingAt url: URL, duration: TimeInterval, enhance: Double, createdAt: Date
  ) throws -> Memo? {
    if failOnCommit { throw FakeStoreError.commitFailed }
    guard duration > 0 else {
      discard(recordingAt: url)
      return nil
    }
    let memo = Memo(
      id: UUID(),
      name: Memo.defaultName(for: createdAt),
      createdAt: createdAt,
      duration: duration,
      enhance: enhance,
      filename: url.lastPathComponent
    )
    stored.insert(memo, at: 0)
    return memo
  }

  func delete(_ memo: Memo) throws {
    stored.removeAll { $0 === memo }
  }

  func rename(_ memo: Memo, to name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    memo.name = trimmed.isEmpty ? Memo.defaultName(for: memo.createdAt) : trimmed
  }

  func setEnhance(_ value: Double, on memo: Memo) throws {
    memo.enhance = min(max(value, 0), 1)
  }

  func discard(recordingAt url: URL) { discardedURLs.append(url) }

  func removeOrphanedFiles() throws {}
}

enum FakeStoreError: Error {
  case commitFailed
}

// MARK: - Named preview scenarios

enum PreviewScenario {
  /// 4a / the empty Demos list.
  static var emptyStore: FakeMemoStore { FakeMemoStore() }

  /// 1a / 2a — the populated list, matching the design's sample takes.
  static var populatedStore: FakeMemoStore {
    // Relative to now, so the list's Today / Yesterday / weekday labels are
    // actually exercised rather than falling through to a bare date.
    let day: TimeInterval = 86_400
    let now = Date.now
    return FakeMemoStore(memos: [
      memo("New Demo 3", now, 37, 0.62),
      memo("Chorus — fast", now - 14_500, 21, 0.5),
      memo("Bridge hum", now - day, 72, 0),
      memo("Verse idea 2", now - 3 * day, 48, 0),
      memo("Riff in D", now - 5 * day, 15, 0.8),
    ])
  }

  static var sampleMemo: Memo {
    memo("New Demo 3", .now, 37, 0.5)
  }

  static func grantedRecorder(duration: TimeInterval = 0) -> FakeAudioRecorder {
    let recorder = FakeAudioRecorder()
    recorder.permission = .granted
    recorder.stubbedDuration = duration
    return recorder
  }

  static var deniedRecorder: FakeAudioRecorder {
    let recorder = FakeAudioRecorder()
    recorder.permission = .denied
    return recorder
  }

  static func memo(
    _ name: String, _ createdAt: Date, _ duration: TimeInterval, _ enhance: Double
  ) -> Memo {
    Memo(
      id: UUID(),
      name: name,
      createdAt: createdAt,
      duration: duration,
      enhance: enhance,
      filename: "\(name).m4a"
    )
  }
}
