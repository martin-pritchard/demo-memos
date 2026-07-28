import Foundation
import Testing

@testable import Core

// The dial positions every behavioural claim is checked across.
private let sweep: [Double] = [0, 0.25, 0.5, 0.75, 1.0]

// A finer sweep for pure-curve shape claims, where evaluation is cheap.
private let curveSweep: [Double] = stride(from: 0.0, through: 1.0, by: 0.01).map { $0 }

// `levelSteps` lays out three 0.5 s segments: quiet, loud, quiet. The envelope
// follower needs time after each level change, so we measure only the settled
// tail of the loud segment and of the final quiet segment.
private let loudWindow: Range<Double> = 0.7..<1.0
private let quietWindow: Range<Double> = 1.2..<1.5

/// Quiet -> loud -> quiet. The fixture the levelling claims are made against.
private func dynamicFixture() -> SampleBuffer {
  Fixtures.levelSteps(dbFS: [-30, -6, -30])
}

private func processed(_ warmth: Double, _ buffer: SampleBuffer) -> SampleBuffer {
  WarmthProcessor(warmth: warmth).process(buffer)
}

@Suite("Leveler parameter curve")
struct LevelerParameterCurveTests {

  @Test("At warmth zero the leveler is exactly identity: ratio 1.0 and no make-up")
  func identityAtZero() {
    let params = warmthParameters(0)
    #expect(params.levelerRatio == 1.0)
    #expect(params.levelerMakeupGainDB == 0)
  }

  @Test("Ratio never falls as warmth rises and compresses at all by full warmth")
  func ratioRisesAndCompressesAtFullWarmth() throws {
    let ratios = curveSweep.map { warmthParameters($0).levelerRatio }
    for (lower, higher) in zip(ratios, ratios.dropFirst()) {
      #expect(higher >= lower)
    }
    for ratio in ratios {
      #expect(ratio >= 1.0)
    }
    #expect(try #require(ratios.last) > 1.0)
  }

  @Test("Threshold never rises as warmth rises and is never above full scale")
  func thresholdFallsAndStaysBelowFullScale() {
    let thresholds = curveSweep.map { warmthParameters($0).levelerThresholdDB }
    for (lower, higher) in zip(thresholds, thresholds.dropFirst()) {
      #expect(higher <= lower)
    }
    for threshold in thresholds {
      #expect(threshold <= 0)
    }
  }

  @Test("Make-up gain is never negative and never falls as warmth rises")
  func makeupIsNonNegativeAndNonDecreasing() {
    let makeups = curveSweep.map { warmthParameters($0).levelerMakeupGainDB }
    for (lower, higher) in zip(makeups, makeups.dropFirst()) {
      #expect(higher >= lower)
    }
    for makeup in makeups {
      #expect(makeup >= 0)
    }
  }

  @Test(
    "Attack and release are positive, constant across the dial, and release is the longer of the two"
  )
  func timeConstantsArePositiveAndConstant() {
    let reference = warmthParameters(0)
    #expect(reference.levelerAttack > 0)
    #expect(reference.levelerRelease > 0)
    #expect(reference.levelerRelease > reference.levelerAttack)

    for warmth in curveSweep {
      let params = warmthParameters(warmth)
      #expect(params.levelerAttack == reference.levelerAttack)
      #expect(params.levelerRelease == reference.levelerRelease)
    }
  }

  @Test("The pivot the leveler is referenced to sits below full scale")
  func pivotIsBelowFullScale() {
    #expect(levelerPivotDBFS < 0)
  }

  @Test("Warmth outside zero to one is clamped to the ends of the curve")
  func warmthIsClamped() {
    #expect(warmthParameters(-5) == warmthParameters(0))
    #expect(warmthParameters(5) == warmthParameters(1))
  }

  @Test("Make-up gain is derived so a signal at the pivot passes through unchanged")
  func makeupIsDerivedFromThePivot() {
    for warmth in curveSweep {
      let params = warmthParameters(warmth)
      #expect(params.levelerMakeupGainDB >= 0)

      guard params.levelerThresholdDB <= levelerPivotDBFS else { continue }
      let expected =
        (levelerPivotDBFS - params.levelerThresholdDB) * (1 - 1 / params.levelerRatio)
      #expect(abs(params.levelerMakeupGainDB - expected) <= 1e-9)
    }
  }
}

@Suite("Leveler dynamics")
struct LevelerDynamicsTests {

  @Test(
    "Raising warmth never widens the gap between the loud and quiet passages, and narrows it by full warmth"
  )
  func passageRangeNeverWidens() throws {
    let input = dynamicFixture()
    let ranges = sweep.map { warmth -> Double in
      let output = processed(warmth, input)
      return rmsDBFS(output, seconds: loudWindow) - rmsDBFS(output, seconds: quietWindow)
    }

    for range in ranges {
      #expect(range.isFinite)
    }

    // Small slack: this is a claim about the shape of the curve, not about
    // float noise between adjacent dial positions.
    for (lower, higher) in zip(ranges, ranges.dropFirst()) {
      #expect(higher <= lower + 1e-6)
    }

    let dry = try #require(ranges.first)
    let wet = try #require(ranges.last)
    #expect(wet < dry)
  }

  @Test("No dial position makes the loud passage more than a decibel louder than dry")
  func loudPassageNeverGetsLouder() {
    let input = dynamicFixture()
    let dryLoud = rmsDBFS(processed(0, input), seconds: loudWindow)

    for warmth in sweep {
      let loud = rmsDBFS(processed(warmth, input), seconds: loudWindow)
      #expect(loud <= dryLoud + 1.0)
    }
  }

  @Test("The quiet passage is lifted at full warmth")
  func quietPassageIsLifted() {
    let input = dynamicFixture()
    let dryQuiet = rmsDBFS(processed(0, input), seconds: quietWindow)
    let wetQuiet = rmsDBFS(processed(1, input), seconds: quietWindow)
    #expect(wetQuiet > dryQuiet)
  }

  @Test("Gain reduction on the loud passage stays within six decibels at full warmth")
  func gainReductionIsBounded() {
    let input = dynamicFixture()
    let dryLoud = rmsDBFS(processed(0, input), seconds: loudWindow)
    let wetLoud = rmsDBFS(processed(1, input), seconds: loudWindow)
    #expect(wetLoud >= dryLoud - 6.0)
  }

  @Test("Warmth zero passes the dynamic fixture through untouched")
  func warmthZeroIsATrueBypass() {
    let input = dynamicFixture()
    nullTest(processed(0, input), input, tolerance: -250)
  }
}

@Suite("Leveler safety")
struct LevelerSafetyTests {

  @Test("Silence stays silent and finite at every dial position")
  func silenceStaysSilent() {
    let input = Fixtures.silence()
    for warmth in sweep {
      let output = processed(warmth, input)
      #expect(peakDBFS(output) == -.infinity)
      for sample in output.samples {
        #expect(sample.isFinite)
      }
    }
  }

  @Test("The dynamic fixture never clips at any dial position")
  func dynamicFixtureNeverClips() {
    let input = dynamicFixture()
    for warmth in sweep {
      let output = processed(warmth, input)
      assertNoClipping(output)
      #expect(peakDBFS(output) < 0)
    }
  }

  @Test("An impulse never clips at any dial position above bypass")
  func impulseNeverClips() {
    // Warmth 0 is excluded: it is a true bypass returning the input verbatim,
    // and `Fixtures.impulse()` peaks at exactly 1.0, so it would read as
    // clipped though the processor introduced nothing. `WarmthProcessorTests`
    // excludes warmth 0 for the same reason.
    let input = Fixtures.impulse()
    for warmth in sweep where warmth > 0 {
      let output = processed(warmth, input)
      assertNoClipping(output)
      #expect(peakDBFS(output) < 0)
    }
  }

  @Test("No DC offset is introduced at any dial position")
  func noDCOffsetIntroduced() {
    let input = dynamicFixture()
    let inputDC = dcOffset(input)
    for warmth in sweep {
      let outputDC = dcOffset(processed(warmth, input))
      #expect(abs(outputDC - inputDC) <= 1e-4)
    }
  }

  @Test("Sample rate, channel count and sample count survive the leveler unchanged")
  func bufferShapeIsPreserved() {
    let input = dynamicFixture()
    for warmth in sweep {
      let output = processed(warmth, input)
      #expect(output.sampleRate == input.sampleRate)
      #expect(output.channelCount == input.channelCount)
      #expect(output.samples.count == input.samples.count)
    }
  }
}
