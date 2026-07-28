import Testing
import Foundation
@testable import Core

@Suite("WAV codec round-trip and errors")
struct WAVFileTests {

  @Test("A -6 dBFS sine round-trips: same format, clean null test, peak preserved")
  func sineRoundTrip() throws {
    let original = Fixtures.sine(dbFS: -6)
    let data = try WAVFile.encode(original)
    let roundTripped = try WAVFile.read(data)

    #expect(roundTripped.sampleRate == 48000)
    #expect(roundTripped.channelCount == 1)
    #expect(roundTripped.samples.count == original.samples.count)

    // 24-bit quantization floor sits below -130 dBFS.
    nullTest(original, roundTripped, tolerance: -130)
    #expect(abs(peakDBFS(roundTripped) - (-6.0)) <= 0.05)
  }

  @Test("A silence buffer round-trips clean")
  func silenceRoundTrip() throws {
    let original = Fixtures.silence()
    let data = try WAVFile.encode(original)
    let roundTripped = try WAVFile.read(data)

    #expect(roundTripped.sampleRate == 48000)
    #expect(roundTripped.channelCount == 1)
    #expect(roundTripped.samples.count == original.samples.count)
    nullTest(original, roundTripped, tolerance: -130)
    #expect(peakDBFS(roundTripped) == -Double.infinity)
  }

  @Test("Non-RIFF bytes throw WAVError.notRIFF")
  func nonRIFFThrows() {
    let garbage = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    #expect(throws: WAVError.notRIFF) {
      _ = try WAVFile.read(garbage)
    }
  }

  @Test("A truncated valid WAV throws a WAVError")
  func truncatedThrows() throws {
    let data = try WAVFile.encode(Fixtures.sine(dbFS: -6))
    let cut = data.prefix(20)
    #expect(throws: WAVError.self) {
      _ = try WAVFile.read(Data(cut))
    }
  }
}
