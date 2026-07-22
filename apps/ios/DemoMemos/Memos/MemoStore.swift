import Foundation
import SwiftData

/// The index and the audio files are one thing, owned here. Nothing else in the
/// app touches the recordings directory, so a row can never outlive its file or
/// a file its row.
protocol MemoStore: AnyObject {
  /// Newest first.
  func memos() throws -> [Memo]

  func fileURL(for memo: Memo) -> URL

  /// A fresh, unused `.m4a` URL inside the recordings directory. Creates the
  /// directory if needed; does not create the file.
  func newRecordingURL() -> URL

  /// Promote an uncommitted recording into the index. A take shorter than
  /// `Memo.minimumDuration` is not a take: nothing is persisted, the file is
  /// removed, and this returns nil.
  @discardableResult
  func commit(
    recordingAt url: URL, duration: TimeInterval, enhance: Double, createdAt: Date
  ) throws -> Memo?

  /// Removes the row and the file.
  func delete(_ memo: Memo) throws

  /// A name that is blank after trimming falls back to the default date-stamped
  /// name rather than persisting empty.
  func rename(_ memo: Memo, to name: String) throws

  func setEnhance(_ value: Double, on memo: Memo) throws

  /// Removes an uncommitted recording. Never touches the index.
  func discard(recordingAt url: URL)

  /// Deletes any file in the recordings directory that no row points at — so a
  /// kill mid-record leaves nothing orphaned. Run at startup.
  func removeOrphanedFiles() throws
}

final class SwiftDataMemoStore: MemoStore {
  private let modelContext: ModelContext
  private let directory: URL
  private let fileManager = FileManager.default

  init(modelContext: ModelContext, directory: URL) {
    self.modelContext = modelContext
    self.directory = directory
  }

  func memos() throws -> [Memo] {
    try modelContext.fetch(
      FetchDescriptor<Memo>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    )
  }

  func fileURL(for memo: Memo) -> URL {
    directory.appending(path: memo.filename)
  }

  func newRecordingURL() -> URL {
    createDirectoryIfNeeded()
    return directory.appending(path: "\(UUID().uuidString).m4a")
  }

  @discardableResult
  func commit(
    recordingAt url: URL, duration: TimeInterval, enhance: Double, createdAt: Date
  ) throws -> Memo? {
    guard duration >= Memo.minimumDuration else {
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
    modelContext.insert(memo)
    try modelContext.save()
    return memo
  }

  func delete(_ memo: Memo) throws {
    let url = fileURL(for: memo)
    modelContext.delete(memo)
    try modelContext.save()
    try? fileManager.removeItem(at: url)
  }

  func rename(_ memo: Memo, to name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    memo.name = trimmed.isEmpty ? Memo.defaultName(for: memo.createdAt) : trimmed
    try modelContext.save()
  }

  func setEnhance(_ value: Double, on memo: Memo) throws {
    memo.enhance = min(max(value, 0), 1)
    try modelContext.save()
  }

  func discard(recordingAt url: URL) {
    try? fileManager.removeItem(at: url)
  }

  func removeOrphanedFiles() throws {
    guard fileManager.fileExists(atPath: directory.path) else { return }
    let indexed = Set(try memos().map(\.filename))
    let onDisk = try fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )
    for url in onDisk where !indexed.contains(url.lastPathComponent) {
      try? fileManager.removeItem(at: url)
    }
  }

  private func createDirectoryIfNeeded() {
    guard !fileManager.fileExists(atPath: directory.path) else { return }
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
  }
}
