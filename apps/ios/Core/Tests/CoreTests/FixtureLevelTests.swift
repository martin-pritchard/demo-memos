import Foundation
import Testing

@testable import Core

// Generated fixtures (Fixtures.*) measured with the harness.
@Suite("Generated fixture levels")
struct GeneratedFixtureTests {

  @Test("sine(-18): peak -18.0, RMS -21.01 (RMS is 3.01 dB below peak)")
  func sineMinus18() {
    let buffer = Fixtures.sine(dbFS: -18)
    #expect(abs(peakDBFS(buffer) - (-18.0)) <= 0.05)
    #expect(abs(rmsDBFS(buffer) - (-21.01)) <= 0.05)
  }

  @Test("sine(-6): peak -6.0, RMS -9.01")
  func sineMinus6() {
    let buffer = Fixtures.sine(dbFS: -6)
    #expect(abs(peakDBFS(buffer) - (-6.0)) <= 0.05)
    #expect(abs(rmsDBFS(buffer) - (-9.01)) <= 0.05)
  }

  @Test("sine(-0.5): peak -0.5, RMS -3.51")
  func sineMinusHalf() {
    let buffer = Fixtures.sine(dbFS: -0.5)
    #expect(abs(peakDBFS(buffer) - (-0.5)) <= 0.05)
    #expect(abs(rmsDBFS(buffer) - (-3.51)) <= 0.05)
  }

  @Test("whiteNoise(-20): RMS -20.0 (±0.3), peak below full scale")
  func whiteNoiseLevel() {
    let buffer = Fixtures.whiteNoise(rmsDBFS: -20)
    #expect(abs(rmsDBFS(buffer) - (-20.0)) <= 0.3)
    #expect(peakDBFS(buffer) < 0)
  }

  @Test("whiteNoise is deterministic: identical arguments produce identical samples")
  func whiteNoiseDeterministic() {
    let a = Fixtures.whiteNoise(rmsDBFS: -20)
    let b = Fixtures.whiteNoise(rmsDBFS: -20)
    #expect(a.samples == b.samples)
  }

  @Test("silence(): peak and RMS are -infinity")
  func silenceLevels() {
    let buffer = Fixtures.silence()
    #expect(peakDBFS(buffer) == -Double.infinity)
    #expect(rmsDBFS(buffer) == -Double.infinity)
  }

  @Test("impulse(): one non-zero sample, samples[0] == 1.0, peak 0.0 dBFS")
  func impulseFixture() {
    let buffer = Fixtures.impulse()
    let nonZero = buffer.samples.filter { $0 != 0 }
    #expect(nonZero.count == 1)
    #expect(buffer.samples[0] == 1.0)
    #expect(abs(peakDBFS(buffer) - 0.0) <= 1e-9)
  }

  @Test("sineWithDC(-18, dc: 0.05): dcOffset ≈ 0.05")
  func sineWithDCFixture() {
    let buffer = Fixtures.sineWithDC(dbFS: -18, dc: 0.05)
    #expect(abs(dcOffset(buffer) - 0.05) <= 1e-3)
  }
}

// Committed fixture files loaded from real bytes via loadFixture.
@Suite("Committed fixture files")
struct CommittedFixtureTests {

  @Test("sine-18: 48 kHz mono, peak -18.0, RMS -21.01")
  func sine18() throws {
    let buffer = try loadFixture("sine-18")
    #expect(buffer.sampleRate == 48000)
    #expect(buffer.channelCount == 1)
    #expect(abs(peakDBFS(buffer) - (-18.0)) <= 0.05)
    #expect(abs(rmsDBFS(buffer) - (-21.01)) <= 0.05)
  }

  @Test("sine-6: peak -6.0, RMS -9.01")
  func sine6() throws {
    let buffer = try loadFixture("sine-6")
    #expect(abs(peakDBFS(buffer) - (-6.0)) <= 0.05)
    #expect(abs(rmsDBFS(buffer) - (-9.01)) <= 0.05)
  }

  @Test("sine-0_5: peak -0.5, RMS -3.51")
  func sine0_5() throws {
    let buffer = try loadFixture("sine-0_5")
    #expect(abs(peakDBFS(buffer) - (-0.5)) <= 0.05)
    #expect(abs(rmsDBFS(buffer) - (-3.51)) <= 0.05)
  }

  @Test("noise-20: RMS -20.0 (±0.3), no clipping")
  func noise20() throws {
    let buffer = try loadFixture("noise-20")
    #expect(abs(rmsDBFS(buffer) - (-20.0)) <= 0.3)
    #expect(peakDBFS(buffer) < 0)
  }

  @Test("silence: peak is -infinity")
  func silence() throws {
    let buffer = try loadFixture("silence")
    #expect(peakDBFS(buffer) == -Double.infinity)
  }

  @Test("impulse: samples[0] == 1.0, peak 0.0 dBFS")
  func impulse() throws {
    let buffer = try loadFixture("impulse")
    #expect(buffer.samples[0] == 1.0)
    #expect(abs(peakDBFS(buffer) - 0.0) <= 1e-9)
  }

  @Test("sine-18-dc: dcOffset ≈ 0.05")
  func sine18dc() throws {
    let buffer = try loadFixture("sine-18-dc")
    #expect(abs(dcOffset(buffer) - 0.05) <= 1e-3)
  }

  @Test("real-take: EXTENSIBLE + FLLR handled; peak -1.00, RMS -19.65, ~no DC, below full scale")
  func realTake() throws {
    let buffer = try loadFixture("real-take")
    #expect(buffer.sampleRate == 48000)
    #expect(buffer.channelCount == 1)
    #expect(abs(peakDBFS(buffer) - (-1.00)) <= 0.05)
    #expect(abs(rmsDBFS(buffer) - (-19.65)) <= 0.15)
    #expect(abs(dcOffset(buffer)) < 1e-5)
    #expect(peakDBFS(buffer) < 0)
  }
}
