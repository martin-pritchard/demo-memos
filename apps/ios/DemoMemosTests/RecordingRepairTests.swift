import AVFAudio
import Foundation
import Testing

@testable import DemoMemos

/// The repair pass is pure byte arithmetic, so it is the one part of the capture
/// path that can be verified properly without a device.
struct RecordingRepairTests {

  // MARK: - Fixtures

  /// A canonical 48 kHz / mono / 24-bit WAV with `declaredDataSize` in the header
  /// and `sampleBytes` of payload actually on disk. Setting the two to different
  /// values is exactly what a jetsam kill leaves behind.
  private static func makeWAV(
    declaredDataSize: UInt32,
    sampleBytes: Int,
    blockAlign: UInt16 = 3,
    trailingChunk: String? = nil
  ) -> Data {
    var data = Data()
    func append32(_ value: UInt32) {
      data.append(contentsOf: [
        UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF),
      ])
    }
    func append16(_ value: UInt16) {
      data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    data.append(contentsOf: Array("RIFF".utf8))
    append32(0)  // deliberately stale, like an unfinalised file
    data.append(contentsOf: Array("WAVE".utf8))

    data.append(contentsOf: Array("fmt ".utf8))
    append32(16)
    append16(1)  // linear PCM
    append16(1)  // mono
    append32(48_000)
    append32(48_000 * UInt32(blockAlign))
    append16(blockAlign)
    append16(24)

    data.append(contentsOf: Array("data".utf8))
    append32(declaredDataSize)
    data.append(Data(repeating: 0xAB, count: sampleBytes))

    if let trailingChunk {
      data.append(contentsOf: Array(trailingChunk.utf8))
      append32(4)
      data.append(Data(repeating: 0x01, count: 4))
    }
    return data
  }

  private static func write(_ data: Data, name: String = "take.wav") throws -> URL {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: name)
    try data.write(to: url)
    return url
  }

  private static func declaredDataSize(at url: URL) throws -> UInt32 {
    let bytes = [UInt8](try Data(contentsOf: url))
    // 40 is the data-chunk size field in a canonical header.
    return UInt32(bytes[40]) | UInt32(bytes[41]) << 8 | UInt32(bytes[42]) << 16
      | UInt32(bytes[43]) << 24
  }

  // MARK: - Tests

  /// Given a take killed mid-write, when repaired, then the header declares the
  /// bytes that are actually on disk.
  @Test func repairsAHeaderThatUnderDeclaresTheFile() throws {
    let url = try Self.write(Self.makeWAV(declaredDataSize: 0, sampleBytes: 900))

    let outcome = try RecordingRepair.repairIfNeeded(at: url)

    #expect(outcome == .repaired(declaredBytes: 900))
    #expect(try Self.declaredDataSize(at: url) == 900)
  }

  /// Given a finalised take, when the pass runs, then nothing is written.
  @Test func leavesAValidFileAlone() throws {
    let url = try Self.write(Self.makeWAV(declaredDataSize: 900, sampleBytes: 900))
    let before = try Data(contentsOf: url)

    let outcome = try RecordingRepair.repairIfNeeded(at: url)

    #expect(outcome == .alreadyValid)
    #expect(try Data(contentsOf: url) == before)
  }

  /// Running the pass twice must not change bytes the second time — it runs on
  /// every launch, over every take, forever.
  @Test func isIdempotent() throws {
    let url = try Self.write(Self.makeWAV(declaredDataSize: 0, sampleBytes: 900))

    _ = try RecordingRepair.repairIfNeeded(at: url)
    let afterFirst = try Data(contentsOf: url)
    let second = try RecordingRepair.repairIfNeeded(at: url)

    #expect(second == .alreadyValid)
    #expect(try Data(contentsOf: url) == afterFirst)
  }

  /// A kill can land mid-frame. Declaring a partial 24-bit frame would shift
  /// every sample after it, so the size is floored to whole frames.
  @Test func floorsToWholeFrames() throws {
    // 901 bytes is 300 whole 3-byte frames plus one stray byte.
    let url = try Self.write(Self.makeWAV(declaredDataSize: 0, sampleBytes: 901))

    let outcome = try RecordingRepair.repairIfNeeded(at: url)

    #expect(outcome == .repaired(declaredBytes: 900))
  }

  /// The RIFF size must be corrected too, or the file still fails to open.
  @Test func rewritesTheRIFFSize() throws {
    let url = try Self.write(Self.makeWAV(declaredDataSize: 0, sampleBytes: 900))

    _ = try RecordingRepair.repairIfNeeded(at: url)

    let bytes = [UInt8](try Data(contentsOf: url))
    let riffSize =
      UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
    let fileSize = UInt32(bytes.count)
    #expect(riffSize == fileSize - 8)
  }

  /// If something follows `data`, the trailing bytes are not samples and the
  /// declared size is not ours to change.
  @Test func skipsWhenAnotherChunkFollowsData() throws {
    let url = try Self.write(
      Self.makeWAV(declaredDataSize: 900, sampleBytes: 900, trailingChunk: "LIST"))

    let outcome = try RecordingRepair.repairIfNeeded(at: url)

    #expect(outcome == .skipped(.dataChunkNotLast))
  }

  @Test func skipsSomethingThatIsNotAWAV() throws {
    let url = try Self.write(Data("not a wave file at all, just some bytes".utf8))

    let outcome = try RecordingRepair.repairIfNeeded(at: url)

    #expect(outcome == .skipped(.notRIFFWave))
  }

  /// The launch pass repairs only what needs it, and reports every take.
  @Test func repairsOnlyTheStaleTakeInAFolder() throws {
    let stale = try Self.write(Self.makeWAV(declaredDataSize: 0, sampleBytes: 900), name: "a.wav")
    let folder = stale.deletingLastPathComponent()
    try Self.makeWAV(declaredDataSize: 600, sampleBytes: 600)
      .write(to: folder.appending(path: "b.wav"))

    let results = RecordingRepair.repairAll(in: folder)

    #expect(results.count == 2)
    #expect(try results[stale]?.get() == .repaired(declaredBytes: 900))
    #expect(try results[folder.appending(path: "b.wav")]?.get() == .alreadyValid)
  }

  /// A real `AVAudioRecorder` file must survive the round trip, or the whole
  /// pass is arithmetic against a layout this app does not actually write.
  /// Creating the recorder writes the header without needing a microphone.
  @Test func handlesTheHeaderAVAudioRecorderActuallyWrites() throws {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: "real.wav")

    let recorder = try AVAudioRecorder(url: url, settings: AudioSession.recorderSettings)
    #expect(recorder.prepareToRecord())

    // Whatever it wrote, the pass must recognise it as a WAV and not mangle it.
    let outcome = try RecordingRepair.repairIfNeeded(at: url)
    if case .skipped(let reason) = outcome {
      Issue.record("Repair did not understand a real AVAudioRecorder header: \(reason)")
    }

    // And the result must still be openable by AVFoundation.
    #expect(throws: Never.self) { _ = try AVAudioFile(forReading: url) }
  }
}
