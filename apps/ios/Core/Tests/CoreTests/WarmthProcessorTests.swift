import Foundation
import Testing

@testable import Core

@Suite("Warmth processor behaviour")
struct WarmthProcessorTests {

  @Test("Output never clips across the processing range and signal types")
  func noClippingAcrossSweep() {
    // Sweep the processing range only, excluding warmth 0. At warmth 0 the
    // processor is a true bypass and returns the input verbatim; since
    // Fixtures.impulse() peaks at exactly 1.0 (full scale), bypassing it yields
    // peak 1.0, which reads as "clipped" though the processor introduced
    // nothing. No-clip is a guarantee about what the processor *does*; warmth-0
    // correctness is covered by the separate true-bypass null-test below.
    let warmths: [Double] = [0.1, 0.25, 0.5, 0.75, 1.0]
    for warmth in warmths {
      let processor = WarmthProcessor(warmth: warmth)

      let sine = Fixtures.sine(dbFS: -0.5)
      let sineOut = processor.process(sine)
      assertNoClipping(sineOut)
      #expect(peakDBFS(sineOut) < 0)

      let noiseOut = processor.process(Fixtures.whiteNoise(rmsDBFS: -12))
      assertNoClipping(noiseOut)

      let impulseOut = processor.process(Fixtures.impulse())
      assertNoClipping(impulseOut)
    }
  }

  @Test("Warmth 0 is a true bypass for tone, noise and silence")
  func trueBypassAtZero() {
    let processor = WarmthProcessor(warmth: 0)

    let sine = Fixtures.sine(dbFS: -6)
    nullTest(processor.process(sine), sine, tolerance: -250)

    let noise = Fixtures.whiteNoise(rmsDBFS: -20)
    nullTest(processor.process(noise), noise, tolerance: -250)

    let silence = Fixtures.silence()
    nullTest(processor.process(silence), silence, tolerance: -250)
  }

  @Test("Loudness stays within ±1 dB of the reference tone")
  func loudnessWithinOneDecibel() {
    let ref = Fixtures.sine(dbFS: -12, frequency: 1000)
    let refRMS = rmsDBFS(ref)
    for warmth in [0, 0.25, 0.5, 0.75, 1.0] as [Double] {
      let out = WarmthProcessor(warmth: warmth).process(ref)
      #expect(abs(rmsDBFS(out) - refRMS) <= 1.0)
    }
  }

  @Test("Total harmonic distortion rises monotonically with warmth")
  func thdRisesMonotonically() throws {
    let ref = Fixtures.sine(dbFS: -12, frequency: 1000)
    let warmths: [Double] = [0.1, 0.25, 0.5, 0.75, 1.0]
    var previous: Double? = nil
    for warmth in warmths {
      let out = WarmthProcessor(warmth: warmth).process(ref)
      let d = try #require(thd(out, fundamental: 1000))
      if let previous {
        #expect(d > previous)
      }
      previous = d
    }
  }

  @Test("Processing introduces no DC offset")
  func noDCIntroduced() {
    for warmth in [0, 0.25, 0.5, 0.75, 1.0] as [Double] {
      let processor = WarmthProcessor(warmth: warmth)

      // A DC-free input must come out DC-free. This is the assertion that
      // actually catches a stage inventing an offset, and it stays exact.
      let sine = Fixtures.sine(dbFS: -12)
      let sineOut = processor.process(sine)
      #expect(abs(dcOffset(sineOut) - dcOffset(sine)) <= 1e-4)

      // The noise fixture carries a small offset of its own (~−0.0012: PRNG
      // sampling noise at this length, not a property anyone chose). Comparing
      // input and output DC directly only worked while every stage had unity
      // gain — the leveler (#32) applies a *level-dependent* gain, so a
      // pre-existing offset is rescaled rather than passed through. DC is a
      // low-level component, so it rides the gain the leveler gives low-level
      // content: measured ~1.22× at full warmth.
      //
      // Bounding it by the chain's small-signal gain keeps the guardrail honest
      // — a chain that *invented* DC would blow past a bound tied to the input's
      // own offset — without asserting a unity-gain property this chain no
      // longer has. See `docs/DECISIONS.md`.
      let parameters = warmthParameters(warmth)
      let smallSignalGain = pow(
        10, (parameters.levelerMakeupGainDB + parameters.makeupGainDB) / 20)
      let noise = Fixtures.whiteNoise(rmsDBFS: -12)
      let noiseOut = processor.process(noise)
      #expect(abs(dcOffset(noiseOut)) <= abs(dcOffset(noise)) * smallSignalGain + 1e-4)
    }
  }

  @Test("Buffer shape is preserved through processing")
  func shapePreserved() {
    let sine = Fixtures.sine(dbFS: -12)
    let out = WarmthProcessor(warmth: 0.6).process(sine)
    #expect(out.sampleRate == sine.sampleRate)
    #expect(out.channelCount == sine.channelCount)
    #expect(out.samples.count == sine.samples.count)
  }
}
