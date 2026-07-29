import Foundation
import Testing

@testable import DemoMemos

/// Runs `body` against a freshly made scratch area, and takes the whole
/// temporary tree away afterwards — these tests touch a real filesystem, so
/// nothing may leak between them.
private func withScratch(_ body: (URL, URL) throws -> Void) throws {
  let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: temporary) }
  let directory = try ShareScratch.directory(inTemporary: temporary)
  try body(directory, temporary)
}

/// A stand-in for a dry capture in Documents. Given real bytes so a test can
/// prove they were left alone.
@discardableResult
private func makeTake(
  named name: String,
  in folder: URL,
  contents: String = "dry take"
) throws -> URL {
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let take = folder.appending(path: name)
  try Data(contents.utf8).write(to: take)
  return take
}

/// Stands in for a completed render: the slot directory plus a payload in it.
@discardableResult
private func writePayload(
  in directory: URL,
  take: URL,
  warmth: Double,
  named name: String,
  contents: String = "rendered"
) throws -> URL {
  let slot = ShareScratch.slotURL(in: directory, take: take, warmth: warmth)
  try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
  let file = ShareScratch.fileURL(in: directory, take: take, warmth: warmth, named: name)
  try Data(contents.utf8).write(to: file)
  return file
}

private func isDirectory(_ url: URL) -> Bool {
  var directory: ObjCBool = false
  let exists = FileManager.default.fileExists(
    atPath: url.path(percentEncoded: false), isDirectory: &directory)
  return exists && directory.boolValue
}

@Suite("ShareScratch: the scratch area")
struct ShareScratchDirectoryTests {

  @Test("the scratch area is a share directory inside the temporary directory it is given")
  func directoryIsMade() throws {
    try withScratch { directory, temporary in
      #expect(directory.lastPathComponent == "share")
      #expect(
        directory.deletingLastPathComponent().lastPathComponent
          == temporary.lastPathComponent)
      #expect(isDirectory(directory))
    }
  }

  @Test("asking for the scratch area twice returns the same directory and keeps its contents")
  func directoryIsIdempotent() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let payload = try writePayload(in: directory, take: take, warmth: 0.4, named: "Demo")

      let again = try ShareScratch.directory(inTemporary: temporary)

      #expect(again.path(percentEncoded: false) == directory.path(percentEncoded: false))
      #expect(FileManager.default.fileExists(atPath: payload.path(percentEncoded: false)))
    }
  }
}

@Suite("ShareScratch: slots")
struct ShareScratchSlotTests {

  @Test("the same take at the same warmth always lands in the same slot")
  func slotIsStable() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let first = ShareScratch.slotURL(in: directory, take: take, warmth: 0.62)
      let second = ShareScratch.slotURL(in: directory, take: take, warmth: 0.62)

      #expect(first == second)
    }
  }

  @Test("a moved dial invalidates the previous render")
  func differentWarmthIsADifferentSlot() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let quiet = ShareScratch.slotURL(in: directory, take: take, warmth: 0.5)
      let warmer = ShareScratch.slotURL(in: directory, take: take, warmth: 0.51)

      #expect(quiet != warmer)
    }
  }

  @Test("warmth is quantised, so a dial nudge too small to hear reuses the slot")
  func warmthIsQuantised() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let exact = ShareScratch.slotURL(in: directory, take: take, warmth: 0.5)
      let nudged = ShareScratch.slotURL(in: directory, take: take, warmth: 0.5004)

      #expect(exact == nudged)
    }
  }

  @Test("the ends of the warmth range are valid and distinct")
  func warmthEndsAreDistinct() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let none = ShareScratch.slotURL(in: directory, take: take, warmth: 0)
      let full = ShareScratch.slotURL(in: directory, take: take, warmth: 1)

      #expect(none != full)
      #expect(none.deletingLastPathComponent() == directory)
      #expect(full.deletingLastPathComponent() == directory)
    }
  }

  @Test("two different takes at the same warmth do not share a slot")
  func differentTakesDoNotCollide() throws {
    try withScratch { directory, temporary in
      let documents = temporary.appending(path: "Documents")
      let one = try makeTake(named: "take-1.wav", in: documents)
      let two = try makeTake(named: "take-2.wav", in: documents)

      let first = ShareScratch.slotURL(in: directory, take: one, warmth: 0.3)
      let second = ShareScratch.slotURL(in: directory, take: two, warmth: 0.3)

      #expect(first != second)
    }
  }

  // Takes are minted from a clock, so two folders can easily hold the same
  // file name; keying the slot on the name alone would serve one take's
  // render for another.
  @Test("takes with the same file name in different folders do not share a slot")
  func sameFileNameInDifferentFoldersDoesNotCollide() throws {
    try withScratch { directory, temporary in
      let one = try makeTake(named: "take.wav", in: temporary.appending(path: "A"))
      let two = try makeTake(named: "take.wav", in: temporary.appending(path: "B"))

      let first = ShareScratch.slotURL(in: directory, take: one, warmth: 0.3)
      let second = ShareScratch.slotURL(in: directory, take: two, warmth: 0.3)

      #expect(first != second)
    }
  }
}

@Suite("ShareScratch: the payload file")
struct ShareScratchFileURLTests {

  @Test(
    "the payload is named after the demo, with .m4a appended",
    arguments: [
      ("New Demo 3", "New Demo 3.m4a"),
      ("Bridge idea", "Bridge idea.m4a"),
      ("Demo", "Demo.m4a"),
    ]
  )
  func payloadIsNamedAfterTheDemo(name: String, expected: String) throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let file = ShareScratch.fileURL(in: directory, take: take, warmth: 0.4, named: name)

      #expect(file.lastPathComponent == expected)
      #expect(file.pathExtension == "m4a")
    }
  }

  // `/` and `:` are the two characters a file name cannot carry; a demo name
  // is free text, so a date-ish or a "verse/chorus" name must not break the URL.
  @Test(
    "characters that cannot appear in a file name become spaces",
    arguments: [
      ("verse/chorus", "verse chorus.m4a"),
      ("12:04 idea", "12 04 idea.m4a"),
      ("a/b:c", "a b c.m4a"),
    ]
  )
  func unsafeCharactersAreReplaced(name: String, expected: String) throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let file = ShareScratch.fileURL(in: directory, take: take, warmth: 0.4, named: name)

      #expect(file.lastPathComponent == expected)
      #expect(!file.lastPathComponent.contains("/"))
      #expect(!file.lastPathComponent.contains(":"))
    }
  }

  @Test(
    "an empty or blank demo name falls back to Demo",
    arguments: ["", " ", "   ", "\t", "\n", " \t\n "]
  )
  func blankNamesFallBack(name: String) throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let file = ShareScratch.fileURL(in: directory, take: take, warmth: 0.4, named: name)

      #expect(file.lastPathComponent == "Demo.m4a")
    }
  }

  @Test("the payload sits inside the slot for its take and warmth")
  func payloadSitsInItsSlot() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let slot = ShareScratch.slotURL(in: directory, take: take, warmth: 0.4)
      let file = ShareScratch.fileURL(in: directory, take: take, warmth: 0.4, named: "Demo")

      #expect(file.deletingLastPathComponent() == slot)
    }
  }

  @Test("renaming a demo does not move the render to another slot")
  func nameDoesNotAffectTheSlot() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      let first = ShareScratch.fileURL(in: directory, take: take, warmth: 0.4, named: "One")
      let second = ShareScratch.fileURL(in: directory, take: take, warmth: 0.4, named: "Two")

      #expect(first.deletingLastPathComponent() == second.deletingLastPathComponent())
    }
  }
}

@Suite("ShareScratch: cached renders")
struct ShareScratchCachedTests {

  @Test("nothing rendered yet means nothing cached")
  func cachedIsNilWhenEmpty() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      #expect(ShareScratch.cached(in: directory, take: take, warmth: 0.4, named: "Demo") == nil)
    }
  }

  // Asking whether a render exists is what decides between reuse and re-run,
  // so it must not be the thing that creates the slot.
  @Test("asking for a cached render creates nothing on disk")
  func cachedDoesNotCreateAnything() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let slot = ShareScratch.slotURL(in: directory, take: take, warmth: 0.4)

      _ = ShareScratch.cached(in: directory, take: take, warmth: 0.4, named: "Demo")

      #expect(!FileManager.default.fileExists(atPath: slot.path(percentEncoded: false)))
      let contents = try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      #expect(contents.isEmpty)
    }
  }

  @Test("an existing render is offered back for reuse")
  func cachedReturnsTheWrittenPayload() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let payload = try writePayload(in: directory, take: take, warmth: 0.4, named: "New Demo 3")

      let cached = try #require(
        ShareScratch.cached(in: directory, take: take, warmth: 0.4, named: "New Demo 3"))

      #expect(cached == payload)
      #expect(cached.lastPathComponent == "New Demo 3.m4a")
    }
  }

  @Test("a render at one warmth is not offered for another")
  func cachedIsPerWarmth() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      try writePayload(in: directory, take: take, warmth: 0.4, named: "Demo")

      #expect(ShareScratch.cached(in: directory, take: take, warmth: 0.7, named: "Demo") == nil)
      #expect(ShareScratch.cached(in: directory, take: take, warmth: 0.4, named: "Demo") != nil)
    }
  }

  @Test("a render is offered back for a warmth that quantises the same")
  func cachedFollowsQuantisation() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let payload = try writePayload(in: directory, take: take, warmth: 0.5, named: "Demo")

      let cached = ShareScratch.cached(in: directory, take: take, warmth: 0.5004, named: "Demo")

      #expect(cached == payload)
    }
  }

  @Test("one take's render is never offered for another take")
  func cachedIsPerTake() throws {
    try withScratch { directory, temporary in
      let one = try makeTake(named: "take.wav", in: temporary.appending(path: "A"))
      let two = try makeTake(named: "take.wav", in: temporary.appending(path: "B"))
      try writePayload(in: directory, take: one, warmth: 0.4, named: "Demo")

      #expect(ShareScratch.cached(in: directory, take: two, warmth: 0.4, named: "Demo") == nil)
    }
  }
}

@Suite("ShareScratch: pruning")
struct ShareScratchPruneTests {

  @Test("pruning drops the renders for every other warmth")
  func pruneDropsOtherWarmths() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let stale = try writePayload(in: directory, take: take, warmth: 0.2, named: "Demo")
      let kept = try writePayload(in: directory, take: take, warmth: 0.8, named: "Demo")

      ShareScratch.prune(in: directory, keeping: take, warmth: 0.8)

      #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
      #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
    }
  }

  @Test("pruning drops the renders for every other take")
  func pruneDropsOtherTakes() throws {
    try withScratch { directory, temporary in
      let one = try makeTake(named: "take-1.wav", in: temporary.appending(path: "Documents"))
      let two = try makeTake(named: "take-2.wav", in: temporary.appending(path: "Documents"))
      let stale = try writePayload(in: directory, take: one, warmth: 0.4, named: "Demo")
      let kept = try writePayload(in: directory, take: two, warmth: 0.4, named: "Demo")

      ShareScratch.prune(in: directory, keeping: two, warmth: 0.4)

      #expect(!FileManager.default.fileExists(atPath: stale.path(percentEncoded: false)))
      #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
    }
  }

  // A share can be in flight while the prune runs, so the kept payload has to
  // survive byte for byte, not merely still exist.
  @Test("the kept render survives pruning intact")
  func keptPayloadKeepsItsContents() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let kept = try writePayload(
        in: directory, take: take, warmth: 0.8, named: "Demo", contents: "rendered bytes")
      try writePayload(in: directory, take: take, warmth: 0.2, named: "Demo")

      ShareScratch.prune(in: directory, keeping: take, warmth: 0.8)

      #expect(try String(decoding: Data(contentsOf: kept), as: UTF8.self) == "rendered bytes")
      #expect(ShareScratch.cached(in: directory, take: take, warmth: 0.8, named: "Demo") == kept)
    }
  }

  @Test("pruning a slot that quantises to the kept one leaves it alone")
  func pruneFollowsQuantisation() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let kept = try writePayload(in: directory, take: take, warmth: 0.5, named: "Demo")

      ShareScratch.prune(in: directory, keeping: take, warmth: 0.5004)

      #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
    }
  }

  @Test("pruning with nothing else to drop is harmless")
  func pruneWithNothingElse() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      let kept = try writePayload(in: directory, take: take, warmth: 0.4, named: "Demo")

      ShareScratch.prune(in: directory, keeping: take, warmth: 0.4)

      #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
    }
  }

  @Test("pruning an empty scratch area is harmless")
  func pruneAnEmptyArea() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))

      ShareScratch.prune(in: directory, keeping: take, warmth: 0.4)

      #expect(ShareScratch.cached(in: directory, take: take, warmth: 0.4, named: "Demo") == nil)
      #expect(isDirectory(directory))
    }
  }

  @Test("pruning never touches the dry capture")
  func pruneLeavesTheTakeAlone() throws {
    try withScratch { directory, temporary in
      let documents = temporary.appending(path: "Documents")
      let take = try makeTake(named: "take.wav", in: documents, contents: "the dry capture")
      let other = try makeTake(named: "other.wav", in: documents, contents: "another capture")
      try writePayload(in: directory, take: take, warmth: 0.4, named: "Demo")
      try writePayload(in: directory, take: other, warmth: 0.4, named: "Demo")

      ShareScratch.prune(in: directory, keeping: take, warmth: 0.4)

      #expect(try String(decoding: Data(contentsOf: take), as: UTF8.self) == "the dry capture")
      #expect(try String(decoding: Data(contentsOf: other), as: UTF8.self) == "another capture")
    }
  }
}

@Suite("ShareScratch: sweeping")
struct ShareScratchSweepTests {

  @Test("a sweep leaves no render behind")
  func sweepEmptiesTheArea() throws {
    try withScratch { directory, temporary in
      let documents = temporary.appending(path: "Documents")
      let one = try makeTake(named: "take-1.wav", in: documents)
      let two = try makeTake(named: "take-2.wav", in: documents)
      try writePayload(in: directory, take: one, warmth: 0.2, named: "Demo")
      try writePayload(in: directory, take: two, warmth: 0.9, named: "Another Demo")

      ShareScratch.sweep(in: directory)

      #expect(ShareScratch.cached(in: directory, take: one, warmth: 0.2, named: "Demo") == nil)
      #expect(
        ShareScratch.cached(in: directory, take: two, warmth: 0.9, named: "Another Demo") == nil)
      #expect(!isDirectory(ShareScratch.slotURL(in: directory, take: one, warmth: 0.2)))
      #expect(!isDirectory(ShareScratch.slotURL(in: directory, take: two, warmth: 0.9)))
    }
  }

  @Test("the scratch area is usable again after a sweep")
  func sweepLeavesTheAreaUsable() throws {
    try withScratch { directory, temporary in
      let take = try makeTake(named: "take.wav", in: temporary.appending(path: "Documents"))
      try writePayload(in: directory, take: take, warmth: 0.4, named: "Demo")

      ShareScratch.sweep(in: directory)
      let again = try ShareScratch.directory(inTemporary: temporary)
      let payload = try writePayload(in: again, take: take, warmth: 0.4, named: "Demo")

      #expect(ShareScratch.cached(in: again, take: take, warmth: 0.4, named: "Demo") == payload)
    }
  }

  // The sweep runs at launch, before anything has had a reason to make the
  // area — a first launch must not be an error path.
  @Test("sweeping an area that was never created is success, not failure")
  func sweepAnAbsentArea() throws {
    let temporary = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }

    ShareScratch.sweep(in: temporary.appending(path: "share"))

    #expect(!isDirectory(temporary.appending(path: "share")))
  }

  @Test("a sweep never touches the dry capture")
  func sweepLeavesTheTakeAlone() throws {
    try withScratch { directory, temporary in
      let documents = temporary.appending(path: "Documents")
      let take = try makeTake(named: "take.wav", in: documents, contents: "the dry capture")
      try writePayload(in: directory, take: take, warmth: 0.4, named: "Demo")

      ShareScratch.sweep(in: directory)

      #expect(try String(decoding: Data(contentsOf: take), as: UTF8.self) == "the dry capture")
    }
  }
}
