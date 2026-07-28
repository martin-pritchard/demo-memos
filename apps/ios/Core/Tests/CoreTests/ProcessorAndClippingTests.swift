import Testing
import Foundation
@testable import Core

@Suite("Identity processor")
struct IdentityProcessorTests {

  @Test("Identity processing of a sine returns an equal buffer with -infinity residual")
  func identitySine() {
    let input = Fixtures.sine(dbFS: -6)
    let output = IdentityProcessor().process(input)
    #expect(output == input)
    nullTest(output, input, tolerance: -250)
  }

  @Test("Identity processing of noise returns an equal buffer with -infinity residual")
  func identityNoise() {
    let input = Fixtures.whiteNoise(rmsDBFS: -20)
    let output = IdentityProcessor().process(input)
    #expect(output == input)
    nullTest(output, input, tolerance: -250)
  }

  @Test("Identity processing of silence returns an equal buffer with -infinity residual")
  func identitySilence() {
    let input = Fixtures.silence()
    let output = IdentityProcessor().process(input)
    #expect(output == input)
    nullTest(output, input, tolerance: -250)
  }
}

@Suite("Clipping")
struct ClippingTests {

  @Test("assertNoClipping passes silently on a clean -6 dBFS sine")
  func cleanPathIsSilent() {
    // No Issue should be recorded; the suite stays green.
    assertNoClipping(Fixtures.sine(dbFS: -6))
  }

  @Test("A sample of exactly 1.0 sits at the clip threshold: peakDBFS == 0.0")
  func thresholdAtFullScale() {
    let buffer = SampleBuffer(sampleRate: 48000, channelCount: 1,
                              samples: [0.0, 1.0, -0.5, 0.25])
    #expect(peakDBFS(buffer) == 0.0)
  }

  @Test("A max |sample| of 1.2 is above the threshold: peakDBFS > 0.0")
  func aboveThreshold() {
    let buffer = SampleBuffer(sampleRate: 48000, channelCount: 1,
                              samples: [0.0, -1.2, 0.5])
    #expect(peakDBFS(buffer) > 0.0)
  }

  @Test("A max |sample| of 0.9999 is below the threshold: peakDBFS < 0.0")
  func belowThreshold() {
    let buffer = SampleBuffer(sampleRate: 48000, channelCount: 1,
                              samples: [0.0, 0.9999, -0.5])
    #expect(peakDBFS(buffer) < 0.0)
  }
}
