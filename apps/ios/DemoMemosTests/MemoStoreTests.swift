import Foundation
import SwiftData
import Testing

@testable import DemoMemos

@Suite("MemoStore")
struct MemoStoreTests {

  // MARK: - Fixture

  /// A store backed by an in-memory SwiftData container and a fresh temporary
  /// directory. Callers are responsible for removing `directory`.
  private static func makeStore() throws -> (store: SwiftDataMemoStore, directory: URL) {
    let container = try ModelContainer(
      for: Memo.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
    let store = SwiftDataMemoStore(modelContext: ModelContext(container), directory: directory)
    return (store, directory)
  }

  private static func writeRecording(in store: SwiftDataMemoStore) throws -> URL {
    let url = store.newRecordingURL()
    try Data("audio".utf8).write(to: url)
    return url
  }

  private static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  // Fixed instants so ordering never depends on wall-clock time.
  private static let t1 = Date(timeIntervalSince1970: 1_000_000)
  private static let t2 = Date(timeIntervalSince1970: 2_000_000)
  private static let t3 = Date(timeIntervalSince1970: 3_000_000)

  // MARK: - Tests

  @Test("given a committed take, when it is deleted, then the row and the file are both gone")
  func deleteRemovesRowAndFile() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let recording = try Self.writeRecording(in: store)
    let memo = try #require(
      try store.commit(recordingAt: recording, duration: 12, enhance: 0, createdAt: Self.t1)
    )
    let fileURL = store.fileURL(for: memo)
    #expect(Self.exists(fileURL))

    try store.delete(memo)

    #expect(try store.memos().isEmpty)
    #expect(Self.exists(fileURL) == false)
  }

  @Test(
    "given a committed memo, when renamed to whitespace, then the name falls back to the default")
  func blankRenameFallsBackToDefaultName() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let recording = try Self.writeRecording(in: store)
    let memo = try #require(
      try store.commit(recordingAt: recording, duration: 5, enhance: 0, createdAt: Self.t1)
    )

    try store.rename(memo, to: "   ")

    let reloaded = try #require(try store.memos().first)
    #expect(reloaded.name == Memo.defaultName(for: reloaded.createdAt))
  }

  @Test("given a committed memo, when renamed to a real name, then the new name is read back")
  func renamePersists() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let recording = try Self.writeRecording(in: store)
    let memo = try #require(
      try store.commit(recordingAt: recording, duration: 5, enhance: 0, createdAt: Self.t1)
    )

    try store.rename(memo, to: "Chorus — fast")

    let reloaded = try #require(try store.memos().first)
    #expect(reloaded.name == "Chorus — fast")
  }

  @Test("given a memo, when enhance is set, then the value survives a re-read")
  func enhanceRoundTrips() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let recording = try Self.writeRecording(in: store)
    let memo = try #require(
      try store.commit(recordingAt: recording, duration: 5, enhance: 0, createdAt: Self.t1)
    )

    try store.setEnhance(0.62, on: memo)

    let reloaded = try #require(try store.memos().first)
    #expect(reloaded.enhance == 0.62)
  }

  @Test(
    "given an orphaned file alongside a committed memo, when cleanup runs, then only the orphan is removed"
  )
  func removeOrphanedFilesDeletesOnlyUnreferencedFiles() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let keptRecording = try Self.writeRecording(in: store)
    let memo = try #require(
      try store.commit(recordingAt: keptRecording, duration: 9, enhance: 0, createdAt: Self.t1)
    )
    let keptURL = store.fileURL(for: memo)

    let orphan = try Self.writeRecording(in: store)
    #expect(Self.exists(orphan))

    try store.removeOrphanedFiles()

    #expect(Self.exists(orphan) == false)
    #expect(Self.exists(keptURL))
    #expect(try store.memos().count == 1)
  }

  @Test(
    "given a recording file, when committed with zero duration, then nothing is persisted and the file is deleted"
  )
  func zeroLengthTakeIsNotSaved() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let recording = try Self.writeRecording(in: store)

    let result = try store.commit(
      recordingAt: recording, duration: 0, enhance: 0, createdAt: Self.t1)

    #expect(result == nil)
    #expect(try store.memos().isEmpty)
    #expect(Self.exists(recording) == false)
  }

  @Test(
    "given memos committed out of order, when memos() is read, then they come back newest first")
  func memosAreReturnedNewestFirst() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    for createdAt in [Self.t2, Self.t1, Self.t3] {
      let recording = try Self.writeRecording(in: store)
      _ = try store.commit(recordingAt: recording, duration: 3, enhance: 0, createdAt: createdAt)
    }

    let dates = try store.memos().map(\.createdAt)

    #expect(dates == [Self.t3, Self.t2, Self.t1])
  }

  @Test(
    "given an uncommitted recording, when discarded, then its file is gone and the index is untouched"
  )
  func discardRemovesFileWithoutTouchingIndex() throws {
    let (store, directory) = try Self.makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }

    let committedRecording = try Self.writeRecording(in: store)
    let memo = try #require(
      try store.commit(recordingAt: committedRecording, duration: 7, enhance: 0, createdAt: Self.t1)
    )
    let keptURL = store.fileURL(for: memo)

    let uncommitted = try Self.writeRecording(in: store)

    store.discard(recordingAt: uncommitted)

    #expect(Self.exists(uncommitted) == false)
    #expect(Self.exists(keptURL))
    #expect(try store.memos().count == 1)
  }
}
