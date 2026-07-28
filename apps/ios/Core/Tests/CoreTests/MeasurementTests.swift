import Foundation
import Testing

@testable import Core

// Measurement math tested against inline-built SampleBuffers, so the
// measurement functions are exercised independently of the generators.
@Suite("Measurement math")
struct MeasurementTests {

  /// Build a mono sine of the given linear amplitude, inline.
  private func inlineSine(
    amplitude: Float,
    frequency: Double = 1000,
    sampleRate: Double = 48000,
    duration: Double = 0.5
  ) -> SampleBuffer {
    let count = Int(sampleRate * duration)
    var samples = [Float](repeating: 0, count: count)
    for n in 0..<count {
      let phase = 2.0 * Double.pi * frequency * Double(n) / sampleRate
      samples[n] = amplitude * Float(sin(phase))
    }
    return SampleBuffer(sampleRate: sampleRate, channelCount: 1, samples: samples)
  }

  @Test("A hand-built amplitude-0.5 sine measures peak -6.02 dBFS, RMS -9.03 dBFS")
  func handBuiltSineLevels() {
    let buffer = inlineSine(amplitude: 0.5)
    #expect(abs(peakDBFS(buffer) - (-6.02)) <= 0.01)
    #expect(abs(rmsDBFS(buffer) - (-9.03)) <= 0.02)
  }

  @Test("Silence: peak and RMS are -infinity, DC is 0, THD is nil")
  func silence() {
    let count = Int(48000 * 0.5)
    let buffer = SampleBuffer(
      sampleRate: 48000, channelCount: 1,
      samples: [Float](repeating: 0, count: count))
    #expect(peakDBFS(buffer) == -Double.infinity)
    #expect(rmsDBFS(buffer) == -Double.infinity)
    #expect(dcOffset(buffer) == 0)
    #expect(thd(buffer, fundamental: 1000) == nil)
  }

  @Test("Empty buffer: peak and RMS -infinity, DC 0, THD nil, no crash")
  func emptyBuffer() {
    let buffer = SampleBuffer(sampleRate: 48000, channelCount: 1, samples: [])
    #expect(peakDBFS(buffer) == -Double.infinity)
    #expect(rmsDBFS(buffer) == -Double.infinity)
    #expect(dcOffset(buffer) == 0)
    #expect(thd(buffer, fundamental: 1000) == nil)
  }

  @Test("dcOffset of a constant 0.05 buffer is 0.05")
  func dcOffsetConstant() {
    let buffer = SampleBuffer(
      sampleRate: 48000, channelCount: 1,
      samples: [Float](repeating: 0.05, count: 1000))
    #expect(abs(dcOffset(buffer) - 0.05) <= 1e-6)
  }

  @Test("dcOffset of a buffer symmetric about zero is 0")
  func dcOffsetSymmetric() {
    // +a, -a pairs sum to zero.
    var samples = [Float]()
    for n in 0..<500 {
      let v = Float(n) / 500.0
      samples.append(v)
      samples.append(-v)
    }
    let buffer = SampleBuffer(sampleRate: 48000, channelCount: 1, samples: samples)
    #expect(abs(dcOffset(buffer)) <= 1e-6)
  }

  @Test("THD of a pure integer-cycle 1 kHz sine is near zero (< 0.001)")
  func thdPureTone() {
    // 48000 Hz, 0.5 s, 1000 Hz => exactly 500 cycles, integer.
    let buffer = inlineSine(amplitude: 0.5)
    let value = thd(buffer, fundamental: 1000)
    let unwrapped = try? #require(value)
    #expect(unwrapped != nil)
    if let unwrapped { #expect(unwrapped < 0.001) }
  }
}
