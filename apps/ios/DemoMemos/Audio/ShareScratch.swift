import CryptoKit
import Foundation

/// Where a rendered share payload lives while a share is in flight.
///
/// Split out from `TakeExporter` for the same reason `RecordingsFolder` was split
/// out of `AudioRecorder`: the launch sweep needs the folder before any exporter
/// exists, and a crash mid-share is exactly the case that leaves one behind.
///
/// **Nothing here is persistence.** The dry take in `Documents/` is the
/// recording; this is a scratch copy that exists for the length of one share and
/// is swept at launch. One slot per `(take, warmth)` pair, which is what lets a
/// second share of an unchanged take skip the render entirely (`#17e`, row 1)
/// while a moved dial invalidates it.
nonisolated enum ShareScratch {

  /// The scratch area — `share/` under the temporary directory it is given,
  /// created on first use.
  static func directory(inTemporary temporary: URL) throws -> URL {
    let folder = temporary.appending(path: "share", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  /// The slot for one take at one dial position. A directory rather than a
  /// filename so the payload inside can carry the demo's own name — the
  /// recipient sees "New Demo 3.m4a", not a hash.
  static func slotURL(in directory: URL, take: URL, warmth: Double) -> URL {
    directory.appending(path: key(take: take, warmth: warmth), directoryHint: .isDirectory)
  }

  /// The payload inside that slot.
  static func fileURL(in directory: URL, take: URL, warmth: Double, named name: String) -> URL {
    slotURL(in: directory, take: take, warmth: warmth)
      .appending(path: "\(safeName(name)).m4a")
  }

  /// The payload if it has already been rendered, otherwise nil. Creates nothing.
  static func cached(in directory: URL, take: URL, warmth: Double, named name: String) -> URL? {
    let url = fileURL(in: directory, take: take, warmth: warmth, named: name)
    return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
  }

  /// Drop every slot but this one. Called before a render, so at most one take's
  /// worth of processed audio is on disk at a time and a moved dial cannot leave
  /// its predecessor behind.
  static func prune(in directory: URL, keeping take: URL, warmth: Double) {
    let keep = slotURL(in: directory, take: take, warmth: warmth).lastPathComponent
    for entry in contents(of: directory) where entry.lastPathComponent != keep {
      try? FileManager.default.removeItem(at: entry)
    }
  }

  /// Empty the area. Never throws — a scratch directory that was never created
  /// is the state this wants to reach, not a failure to reach it.
  static func sweep(in directory: URL) {
    for entry in contents(of: directory) {
      try? FileManager.default.removeItem(at: entry)
    }
  }

  // MARK: - Naming

  /// A slot name that collides only for the same take at the same dial position.
  ///
  /// The take is hashed by its *whole path*: two takes can share a last path
  /// component in different folders, and a copy of a demo sharing its original's
  /// render would be the kind of bug nobody looks for. SHA-256 rather than
  /// `hashValue`, which is seeded per process — a slot name has to mean the same
  /// thing to the sweep as it did to the render.
  private static func key(take: URL, warmth: Double) -> String {
    let path = take.standardizedFileURL.path(percentEncoded: false)
    let digest = SHA256.hash(data: Data(path.utf8))
    let stem = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    // Quantised to 3dp: finer than the dial's 40 steps, so every position the
    // user can actually stop on gets its own slot, and float noise does not.
    return "\(stem)-w\(Int((warmth * 1000).rounded()))"
  }

  /// The demo's name, made safe to be a file name. `/` ends a path component and
  /// `:` is the classic Finder separator; both become a space rather than being
  /// dropped, so two names that differ only there stay legible.
  private static func safeName(_ name: String) -> String {
    let cleaned =
      name
      .replacingOccurrences(of: "/", with: " ")
      .replacingOccurrences(of: ":", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "Demo" : cleaned
  }

  private static func contents(of directory: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []
  }
}
