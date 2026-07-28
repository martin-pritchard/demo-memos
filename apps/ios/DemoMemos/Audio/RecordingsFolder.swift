import Foundation

/// Where takes live on disk, and what they are called.
///
/// Split out from `AudioRecorder` because the repair pass needs the same folder
/// at launch, before any recorder exists.
nonisolated enum RecordingsFolder {

  /// `Documents/Recordings`, created on first use.
  static func url(inDocuments documents: URL) throws -> URL {
    let folder = documents.appending(path: "Recordings", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  static func defaultURL() throws -> URL {
    let documents = try FileManager.default.url(
      for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return try url(inDocuments: documents)
  }

  /// A take name that sorts chronologically as a string: `take-20260728-135712.wav`.
  static func newTakeURL(in folder: URL, at date: Date, calendar: Calendar = .current) -> URL {
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let stamp = String(
      format: "%04d%02d%02d-%02d%02d%02d",
      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    return folder.appending(path: "take-\(stamp).wav")
  }

  /// Existing takes, newest last.
  static func takes(in folder: URL) -> [URL] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)) ?? []
    return contents
      .filter { $0.pathExtension.lowercased() == "wav" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }
}
