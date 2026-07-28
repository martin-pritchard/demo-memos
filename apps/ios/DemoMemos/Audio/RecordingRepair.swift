import Foundation

/// Rewrites the size fields of a WAV whose header was never finalised.
///
/// `AVAudioRecorder.stop()` patches the RIFF and `data` chunk sizes when a take
/// ends on a path we control. A jetsam kill or a crash skips that: the samples
/// are on disk but the header still claims the length it had when recording
/// started, so nothing will open the file. Recording continues while the app is
/// backgrounded, which is exactly when iOS reclaims memory, so this is the
/// expected failure rather than an exotic one.
///
/// Deliberately walks the chunk list instead of assuming the canonical 44-byte
/// header. The assumption holds for every file this app writes today, but it is
/// a silent, file-destroying wrong answer if it ever stops holding.
///
/// Pure byte arithmetic over `FileHandle` — no AVFoundation, and the file is
/// never read into memory, because a long take is tens of megabytes.
nonisolated enum RecordingRepair {

  enum Outcome: Equatable {
    /// The declared size already matches the bytes on disk. Nothing written.
    case alreadyValid
    /// The header was rewritten to declare this many bytes of sample data.
    case repaired(declaredBytes: UInt32)
    /// Left untouched — see `Reason`.
    case skipped(Reason)
  }

  enum Reason: Equatable {
    case notRIFFWave
    case noFormatChunk
    case noDataChunk
    /// Another chunk follows `data`, so the trailing bytes are not samples and
    /// the declared size is somebody else's business.
    case dataChunkNotLast
    /// `blockAlign` is absent or zero, so whole frames cannot be computed.
    case unusableBlockAlign
  }

  /// Repairs `url` in place if its `data` chunk under-declares the file.
  ///
  /// Idempotent: running it on an already-valid file writes nothing and returns
  /// `.alreadyValid`.
  static func repairIfNeeded(at url: URL) throws -> Outcome {
    let handle = try FileHandle(forUpdating: url)
    defer { try? handle.close() }

    let fileSize = try handle.seekToEnd()
    guard fileSize >= 12 else { return .skipped(.notRIFFWave) }

    try handle.seek(toOffset: 0)
    guard let header = try handle.read(upToCount: 12), header.count == 12 else {
      return .skipped(.notRIFFWave)
    }
    let head = [UInt8](header)
    guard matches(head[0..<4], "RIFF"), matches(head[8..<12], "WAVE") else {
      return .skipped(.notRIFFWave)
    }

    var blockAlign: UInt32?
    var dataHeaderOffset: UInt64?
    var declaredDataSize: UInt32 = 0

    var offset: UInt64 = 12
    while offset + 8 <= fileSize {
      try handle.seek(toOffset: offset)
      guard let raw = try handle.read(upToCount: 8), raw.count == 8 else { break }
      let chunk = [UInt8](raw)
      let id = chunk[0..<4]
      let size = littleEndianUInt32(chunk[4..<8])

      if matches(id, "fmt ") {
        // blockAlign sits 12 bytes into the fmt payload: audioFormat (2),
        // numChannels (2), sampleRate (4), byteRate (4), then blockAlign (2).
        try handle.seek(toOffset: offset + 8)
        if let fmt = try handle.read(upToCount: 16), fmt.count >= 14 {
          let bytes = [UInt8](fmt)
          blockAlign = UInt32(bytes[12]) | UInt32(bytes[13]) << 8
        }
      } else if matches(id, "data") {
        dataHeaderOffset = offset
        declaredDataSize = size
        break  // `data` is last in everything this app writes; stop walking.
      }

      // Chunk payloads are padded to an even length.
      let advance = UInt64(size) + (size % 2 == 1 ? 1 : 0)
      guard advance > 0 || matches(id, "data") else { break }
      offset += 8 + advance
    }

    guard let dataOffset = dataHeaderOffset else { return .skipped(.noDataChunk) }
    guard let frameSize = blockAlign, frameSize > 0 else {
      return .skipped(blockAlign == nil ? .noFormatChunk : .unusableBlockAlign)
    }

    let payloadStart = dataOffset + 8
    guard payloadStart <= fileSize else { return .skipped(.noDataChunk) }

    // Trailing bytes are only samples if nothing follows the declared payload.
    if declaredDataSize > 0, try chunkFollows(declaredDataSize, from: payloadStart, in: handle, fileSize: fileSize) {
      return .skipped(.dataChunkNotLast)
    }

    // Floor to a whole frame: a kill mid-write can leave a partial one, and a
    // partial frame at the end of a 24-bit file shifts every channel after it.
    let available = fileSize - payloadStart
    let usable = UInt32(available - (available % UInt64(frameSize)))

    guard usable != declaredDataSize else { return .alreadyValid }

    try handle.seek(toOffset: dataOffset + 4)
    try handle.write(contentsOf: littleEndianBytes(usable))
    try handle.seek(toOffset: 4)
    try handle.write(contentsOf: littleEndianBytes(UInt32(fileSize - 8)))
    try handle.synchronize()

    return .repaired(declaredBytes: usable)
  }

  /// Repairs every `.wav` in `folder`, returning what happened to each.
  ///
  /// A file that cannot be repaired is reported, never deleted — a take we
  /// cannot read is still the user's take.
  static func repairAll(in folder: URL) -> [URL: Result<Outcome, Error>] {
    let contents =
      (try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)) ?? []
    var results: [URL: Result<Outcome, Error>] = [:]
    for url in contents where url.pathExtension.lowercased() == "wav" {
      results[url] = Result { try repairIfNeeded(at: url) }
    }
    return results
  }

  // MARK: - Bytes

  private static func chunkFollows(
    _ declaredSize: UInt32, from payloadStart: UInt64, in handle: FileHandle, fileSize: UInt64
  ) throws -> Bool {
    let padded = UInt64(declaredSize) + (declaredSize % 2 == 1 ? 1 : 0)
    let next = payloadStart + padded
    guard next + 8 <= fileSize else { return false }
    try handle.seek(toOffset: next)
    guard let raw = try handle.read(upToCount: 4), raw.count == 4 else { return false }
    // A chunk id is four printable ASCII characters.
    return raw.allSatisfy { (0x20...0x7E).contains($0) }
  }

  private static func matches(_ bytes: ArraySlice<UInt8>, _ ascii: String) -> Bool {
    bytes.elementsEqual(Array(ascii.utf8))
  }

  private static func littleEndianUInt32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
    let b = Array(bytes)
    return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
  }

  private static func littleEndianBytes(_ value: UInt32) -> [UInt8] {
    [
      UInt8(value & 0xFF),
      UInt8((value >> 8) & 0xFF),
      UInt8((value >> 16) & 0xFF),
      UInt8((value >> 24) & 0xFF),
    ]
  }
}
