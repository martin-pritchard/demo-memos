import AVFAudio
import Core
import Foundation
import Testing

@testable import DemoMemos

/// The offline render, end to end.
///
/// These run a real `AVAudioEngine` — in `.offline` manual rendering mode, which
/// is connected to no device, so nothing here depends on simulator audio and
/// nothing here is the "unverified on simulator" case `PRINCIPLES.ios.md` #4
/// warns about. What they cannot tell you is whether it *sounds* right; that
/// needs ears, on a device.
@Suite("Rendering a take for sharing")
struct TakeExporterTests {

  // MARK: - Fixtures

  /// A scratch tree of its own per test, so a parallel run cannot share a slot.
  private func withTemporary(_ body: (URL) async throws -> Void) async rethrows {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root)
  }

  /// Half a second of 220 Hz at 48 kHz mono — the capture format, small enough
  /// that a whole suite of renders stays quick.
  private func writeTake(in folder: URL, named name: String = "take.wav") throws -> URL {
    let url = folder.appending(path: name)
    let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    let frames = AVAudioFrameCount(24000)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let channel = buffer.floatChannelData![0]
    let step: Double = 2 * Double.pi * 220 / 48000
    for i in 0..<Int(frames) {
      let value: Double = 0.5 * sin(step * Double(i))
      channel[i] = Float(value)
    }
    try file.write(from: buffer)
    return url
  }

  private func frameCount(of url: URL) throws -> AVAudioFramePosition {
    try AVAudioFile(forReading: url).length
  }

  private func peak(of url: URL) throws -> Float {
    let (samples, _) = try TakeDecoder.mono(url)
    return samples.reduce(0) { max($0, abs($1)) }
  }

  // MARK: - The render

  @Test("a rendered take is a real, audible file")
  func rendersAudio() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let exporter = TakeExporter(temporary: root)

      let output = try await exporter.rendered(take: take, warmth: 0.5, named: "New Demo 3")

      #expect(FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
      // Not silence. A render that writes an empty file passes every structural
      // check and is completely useless.
      #expect(try peak(of: output) > 0.01)
    }
  }

  @Test("the payload is named after the demo, not the take on disk")
  func namesThePayloadForTheDemo() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let exporter = TakeExporter(temporary: root)

      let output = try await exporter.rendered(take: take, warmth: 0.5, named: "Chorus — fast")

      #expect(output.lastPathComponent == "Chorus — fast.m4a")
    }
  }

  @Test("the reverb is given room to ring out past the end of the take")
  func rendersATail() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let exporter = TakeExporter(temporary: root)

      let wet = try await exporter.rendered(take: take, warmth: 1, named: "Wet")

      // The take is 0.5s. With the reverb up, the render has to outlast it or the
      // tail is chopped mid-decay — the most audible way to get this wrong.
      #expect(try frameCount(of: wet) > 24000)
    }
  }

  @Test("a dry share is not padded with silence")
  func doesNotPadWhenBypassed() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let exporter = TakeExporter(temporary: root)

      let dry = try await exporter.rendered(take: take, warmth: 0, named: "Dry")

      // Warmth 0 is true bypass, so there is no tail to wait for. Three seconds
      // of silence on the end of every dry share would be a bug nobody reports
      // and everybody hears.
      #expect(try frameCount(of: dry) < 26000)
    }
  }

  @Test("the dial changes what gets shared")
  func warmthChangesTheRender() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let exporter = TakeExporter(temporary: root)

      let dry = try await exporter.rendered(take: take, warmth: 0, named: "Demo")
      // Read before the next render: moving the dial prunes the slot this one is
      // in, which is the point of `aMovedDialReRenders` below.
      let dryBytes = try Data(contentsOf: dry)
      let wet = try await exporter.rendered(take: take, warmth: 1, named: "Demo")
      let wetBytes = try Data(contentsOf: wet)

      #expect(dry != wet)
      #expect(dryBytes != wetBytes)
    }
  }

  @Test("the dry take is never touched")
  func leavesTheCaptureAlone() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let before = try Data(contentsOf: take)
      let exporter = TakeExporter(temporary: root)

      _ = try await exporter.rendered(take: take, warmth: 0.7, named: "Demo")

      #expect(try Data(contentsOf: take) == before)
    }
  }

  // MARK: - The cache

  @Test("sharing an unchanged take twice renders once")
  func reusesTheRender() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let exporter = TakeExporter(temporary: root)

      let first = try await exporter.rendered(take: take, warmth: 0.5, named: "Demo")
      let stamp =
        try FileManager.default.attributesOfItem(
          atPath: first.path(percentEncoded: false))[.modificationDate] as? Date
      let second = try await exporter.rendered(take: take, warmth: 0.5, named: "Demo")
      let after =
        try FileManager.default.attributesOfItem(
          atPath: second.path(percentEncoded: false))[.modificationDate] as? Date

      #expect(first == second)
      // Same file, untouched — this is `#17e`'s silent path, and the only
      // evidence that the second share did not pay for the render again.
      #expect(stamp == after)
    }
  }

  @Test("moving the dial invalidates the previous render")
  func aMovedDialReRenders() async throws {
    try await withTemporary { root in
      let take = try writeTake(in: root)
      let exporter = TakeExporter(temporary: root)

      let first = try await exporter.rendered(take: take, warmth: 0.2, named: "Demo")
      let second = try await exporter.rendered(take: take, warmth: 0.8, named: "Demo")

      #expect(first != second)
      // Only one render is kept: processed audio is not allowed to accumulate.
      #expect(!FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
    }
  }

  // MARK: - Failure

  @Test("a take that cannot be read leaves nothing behind")
  func cleansUpAfterAFailure() async throws {
    try await withTemporary { root in
      let missing = root.appending(path: "not-a-take.wav")
      let exporter = TakeExporter(temporary: root)

      await #expect(throws: (any Error).self) {
        try await exporter.rendered(take: missing, warmth: 0.5, named: "Demo")
      }

      // A half-written payload would satisfy the cache on the next tap and send
      // silence to whoever the user picked.
      let scratch = try ShareScratch.directory(inTemporary: root)
      let left = try FileManager.default.contentsOfDirectory(
        at: scratch, includingPropertiesForKeys: nil)
      #expect(left.isEmpty)
    }
  }
}
