import Foundation
import Testing

@testable import Core

// MARK: - Shared helpers

/// Dial positions used for curve-shape sweeps.
private let curveSweep: [Double] = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }

/// Dial positions used for the DSP sweeps.
private let dspSweep: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]

/// The leveler fields of `warmthParameters(warmth)` with every other stage in the
/// chain neutralised, so a measurement isolates what the leveler alone does.
private func isolatedLevelerParameters(_ warmth: Double) -> WarmthParameters {
  let p = warmthParameters(warmth)
  return WarmthParameters(
    headBumpFrequency: p.headBumpFrequency,
    headBumpGainDB: 0,
    headBumpQ: p.headBumpQ,
    highShelfFrequency: p.highShelfFrequency,
    highShelfGainDB: 0,
    drive: 0,
    makeupGainDB: 0,
    ceiling: p.ceiling,
    levelerThresholdDB: p.levelerThresholdDB,
    levelerRatio: p.levelerRatio,
    levelerAttack: p.levelerAttack,
    levelerRelease: p.levelerRelease,
    levelerMakeupGainDB: p.levelerMakeupGainDB,
    reverbWetMix: 0
  )
}

/// Runs a whole buffer through a freshly built kernel.
private func kernelProcessed(_ buffer: SampleBuffer, _ parameters: WarmthParameters) -> SampleBuffer
{
  var kernel = WarmthKernel(parameters: parameters, sampleRate: buffer.sampleRate)
  var samples = buffer.samples
  samples.withUnsafeMutableBufferPointer { kernel.process($0) }
  return SampleBuffer(
    sampleRate: buffer.sampleRate, channelCount: buffer.channelCount, samples: samples)
}

/// The three-segment quiet → loud → quiet fixture the DSP suite measures.
private func dynamicFixture() -> SampleBuffer {
  Fixtures.levelSteps(dbFS: [-30, -6, -30])
}

/// Settled RMS of the loud middle segment.
private func loudRMS(_ buffer: SampleBuffer) -> Double {
  rmsDBFS(buffer, seconds: 0.7..<1.0)
}

/// Settled RMS of the final quiet segment.
private func quietRMS(_ buffer: SampleBuffer) -> Double {
  rmsDBFS(buffer, seconds: 1.2..<1.5)
}

// MARK: - Curve shape

@Suite("Leveler curve shape")
struct LevelerCurveTests {

  @Test("The dial at zero leaves the leveler doing nothing at all")
  func neutralAtZero() {
    let p = warmthParameters(0)
    #expect(p.levelerRatio == 1.0)
    #expect(p.levelerMakeupGainDB == 0)
  }

  @Test("The leveler ratio never falls as warmth rises and compresses at full warmth")
  func ratioRisesMonotonically() {
    for i in 1..<curveSweep.count {
      let lower = warmthParameters(curveSweep[i - 1]).levelerRatio
      let higher = warmthParameters(curveSweep[i]).levelerRatio
      #expect(higher >= lower, "ratio fell between \(curveSweep[i - 1]) and \(curveSweep[i])")
    }
    #expect(warmthParameters(1).levelerRatio > 1.0)
  }

  @Test("The leveler threshold never rises as warmth rises and is never above zero dBFS")
  func thresholdFallsMonotonically() {
    for i in 1..<curveSweep.count {
      let lower = warmthParameters(curveSweep[i - 1]).levelerThresholdDB
      let higher = warmthParameters(curveSweep[i]).levelerThresholdDB
      #expect(higher <= lower, "threshold rose between \(curveSweep[i - 1]) and \(curveSweep[i])")
    }
    for warmth in curveSweep {
      #expect(warmthParameters(warmth).levelerThresholdDB <= 0)
    }
  }

  @Test("Leveler make-up gain is never negative and never falls as warmth rises")
  func makeupRisesMonotonically() {
    for warmth in curveSweep {
      #expect(warmthParameters(warmth).levelerMakeupGainDB >= 0)
    }
    for i in 1..<curveSweep.count {
      let lower = warmthParameters(curveSweep[i - 1]).levelerMakeupGainDB
      let higher = warmthParameters(curveSweep[i]).levelerMakeupGainDB
      #expect(higher >= lower, "make-up fell between \(curveSweep[i - 1]) and \(curveSweep[i])")
    }
  }

  @Test(
    "Attack and release are positive, constant across the dial, and release is the slower of the two"
  )
  func timeConstantsAreConstantAndOrdered() {
    let reference = warmthParameters(0)
    #expect(reference.levelerAttack > 0)
    #expect(reference.levelerRelease > 0)
    #expect(reference.levelerRelease > reference.levelerAttack)
    for warmth in curveSweep {
      let p = warmthParameters(warmth)
      #expect(p.levelerAttack == reference.levelerAttack)
      #expect(p.levelerRelease == reference.levelerRelease)
    }
  }

  @Test("Warmth outside zero to one is clamped to the ends of the dial")
  func warmthIsClamped() {
    #expect(warmthParameters(-5) == warmthParameters(0))
    #expect(warmthParameters(5) == warmthParameters(1))
  }

  @Test("The leveler pivot sits below full scale")
  func pivotIsBelowFullScale() {
    #expect(levelerPivotDBFS < 0)
  }
}

// MARK: - Pivot guarantee

@Suite("Leveler pivot guarantee")
struct LevelerPivotTests {

  @Test("Make-up gain is derived from the pivot, the threshold and the ratio")
  func makeupMatchesTheDerivation() {
    for warmth in [0.0, 0.25, 0.5, 0.75, 1.0] {
      let p = warmthParameters(warmth)
      let expected = (levelerPivotDBFS - p.levelerThresholdDB) * (1 - 1 / p.levelerRatio)
      #expect(abs(p.levelerMakeupGainDB - expected) < 1e-9, "derivation mismatch at \(warmth)")
    }
  }

  @Test("A tone at the pivot changes level by the same amount at every dial position")
  func pivotToneIsUnchangedByTheLeveler() {
    let input = Fixtures.sine(dbFS: levelerPivotDBFS, frequency: 1000, duration: 2.0)
    let window = 1.5..<2.0
    let inputLevel = rmsDBFS(input, seconds: window)

    let positions: [Double] = [0.25, 0.5, 0.75, 1.0]
    let changes = positions.map { warmth -> Double in
      let out = kernelProcessed(input, isolatedLevelerParameters(warmth))
      return rmsDBFS(out, seconds: window) - inputLevel
    }

    // The ceiling stage is still active in the isolated chain and costs a small
    // constant amount at every position. What the pivot guarantee claims is that
    // the *leveler* contributes nothing, so the figure must be identical across
    // dial positions even though the ratio varies a lot.
    for i in 0..<changes.count {
      for j in (i + 1)..<changes.count {
        #expect(
          abs(changes[i] - changes[j]) <= 0.01,
          """
          pivot level change drifted between warmth \(positions[i]) and \(positions[j]): \
          \(changes[i]) vs \(changes[j])
          """
        )
      }
    }

    // And it must stay small in absolute terms, to catch a wholesale gain error.
    for (warmth, change) in zip(positions, changes) {
      #expect(abs(change) <= 0.5, "pivot level change too large at warmth \(warmth): \(change)")
    }
  }
}

// MARK: - DSP behaviour

@Suite("Leveler DSP behaviour")
struct LevelerProcessorTests {

  @Test("The gap between a loud passage and a quiet one narrows as warmth rises")
  func passageRangeNarrows() {
    let input = dynamicFixture()
    let ranges = dspSweep.map { warmth -> Double in
      let out = WarmthProcessor(warmth: warmth).process(input)
      return loudRMS(out) - quietRMS(out)
    }

    for i in 1..<ranges.count {
      #expect(
        ranges[i] <= ranges[i - 1] + 1e-6,
        """
        passage range widened between warmth \(dspSweep[i - 1]) and \(dspSweep[i]): \
        \(ranges[i - 1]) → \(ranges[i])
        """
      )
    }
    #expect(ranges[ranges.count - 1] < ranges[0])
  }

  @Test("The loud passage never gets louder than dry at any dial position")
  func loudPassageNeverGetsLouder() {
    let input = dynamicFixture()
    let dryLoud = loudRMS(WarmthProcessor(warmth: 0).process(input))
    for warmth in dspSweep {
      let loud = loudRMS(WarmthProcessor(warmth: warmth).process(input))
      #expect(loud <= dryLoud + 1.0, "loud passage rose to \(loud) from \(dryLoud) at \(warmth)")
    }
  }

  @Test("The quiet passage is lifted at full warmth but by a bounded amount")
  func quietPassageIsLiftedButBounded() {
    let input = dynamicFixture()
    let dryQuiet = quietRMS(WarmthProcessor(warmth: 0).process(input))
    let wetQuiet = quietRMS(WarmthProcessor(warmth: 1).process(input))
    #expect(wetQuiet > dryQuiet)
    #expect(wetQuiet - dryQuiet <= 6.0, "quiet passage lifted by \(wetQuiet - dryQuiet) dB")
  }

  @Test("Gain reduction on the loud passage is bounded at full warmth")
  func gainReductionIsBounded() {
    let input = dynamicFixture()
    let dryLoud = loudRMS(WarmthProcessor(warmth: 0).process(input))
    let wetLoud = loudRMS(WarmthProcessor(warmth: 1).process(input))
    #expect(wetLoud >= dryLoud - 6.0, "loud passage pulled down by \(dryLoud - wetLoud) dB")
  }

  @Test("Warmth zero returns the input untouched")
  func warmthZeroIsATrueBypass() {
    let input = dynamicFixture()
    let out = WarmthProcessor(warmth: 0).process(input)
    nullTest(input, out, tolerance: -250)
  }

  @Test("Silence stays silent and finite at every dial position")
  func silenceStaysSilent() {
    for warmth in dspSweep {
      let out = WarmthProcessor(warmth: warmth).process(Fixtures.silence())
      #expect(peakDBFS(out) == -.infinity, "silence gained level at warmth \(warmth)")
      let allFinite = out.samples.allSatisfy({ $0.isFinite })
      #expect(allFinite, "non-finite sample at warmth \(warmth)")
    }
  }

  @Test("Nothing clips across the dial")
  func nothingClips() {
    let dynamic = dynamicFixture()
    for warmth in dspSweep {
      let out = WarmthProcessor(warmth: warmth).process(dynamic)
      assertNoClipping(out)
      #expect(peakDBFS(out) < 0, "peak reached \(peakDBFS(out)) at warmth \(warmth)")
    }

    // Warmth 0 is excluded for the impulse: the processor short-circuits and
    // returns the input verbatim, and the impulse fixture peaks at exactly 1.0,
    // which reads as clipped even though the processor introduced nothing.
    let impulse = Fixtures.impulse()
    for warmth in dspSweep where warmth != 0 {
      let out = WarmthProcessor(warmth: warmth).process(impulse)
      assertNoClipping(out)
      #expect(peakDBFS(out) < 0, "impulse peak reached \(peakDBFS(out)) at warmth \(warmth)")
    }
  }

  @Test("No DC offset is introduced at any dial position")
  func noDCIntroduced() {
    let input = dynamicFixture()
    let inputDC = dcOffset(input)
    for warmth in dspSweep {
      let out = WarmthProcessor(warmth: warmth).process(input)
      #expect(
        abs(dcOffset(out) - inputDC) <= 1e-4,
        "DC drifted to \(dcOffset(out)) from \(inputDC) at warmth \(warmth)"
      )
    }
  }

  @Test("Buffer shape is preserved at every dial position")
  func bufferShapeIsPreserved() {
    let input = dynamicFixture()
    for warmth in dspSweep {
      let out = WarmthProcessor(warmth: warmth).process(input)
      #expect(out.sampleRate == input.sampleRate)
      #expect(out.channelCount == input.channelCount)
      #expect(out.samples.count == input.samples.count)
    }
  }
}

// MARK: - Kernel state

@Suite("Leveler kernel state")
struct LevelerKernelStateTests {

  @Test("Updating the parameters mid-buffer does not restart the leveler")
  func updateDoesNotResetState() throws {
    let input = dynamicFixture()
    let parameters = warmthParameters(0.8)
    let sampleRate = input.sampleRate

    var straight = WarmthKernel(parameters: parameters, sampleRate: sampleRate)
    var straightSamples = input.samples
    straightSamples.withUnsafeMutableBufferPointer { straight.process($0) }

    var interrupted = WarmthKernel(parameters: parameters, sampleRate: sampleRate)
    var interruptedSamples = input.samples
    let split = interruptedSamples.count / 2
    try interruptedSamples.withUnsafeMutableBufferPointer { buffer in
      let base = try #require(buffer.baseAddress)
      interrupted.process(UnsafeMutableBufferPointer(start: base, count: split))
      interrupted.update(parameters)
      interrupted.process(
        UnsafeMutableBufferPointer(start: base + split, count: buffer.count - split))
    }

    #expect(straightSamples.count == interruptedSamples.count)
    let shared = min(straightSamples.count, interruptedSamples.count)
    if let firstDifference = (0..<shared).first(where: {
      straightSamples[$0] != interruptedSamples[$0]
    }) {
      Issue.record(
        """
        sample \(firstDifference) differs after update: \
        \(straightSamples[firstDifference]) vs \(interruptedSamples[firstDifference])
        """)
    }
    #expect(straightSamples == interruptedSamples)
  }

  @Test("Resetting clears the leveler state so a quiet signal is processed as if fresh")
  func resetClearsState() {
    let parameters = warmthParameters(0.8)
    let loud = Fixtures.sine(dbFS: -3, frequency: 1000, duration: 1.0)
    let quiet = Fixtures.sine(dbFS: -30, frequency: 1000, duration: 1.0)
    let sampleRate = quiet.sampleRate

    var driven = WarmthKernel(parameters: parameters, sampleRate: sampleRate)
    var loudSamples = loud.samples
    loudSamples.withUnsafeMutableBufferPointer { driven.process($0) }
    driven.reset()
    var afterReset = quiet.samples
    afterReset.withUnsafeMutableBufferPointer { driven.process($0) }

    var fresh = WarmthKernel(parameters: parameters, sampleRate: sampleRate)
    var freshOutput = quiet.samples
    freshOutput.withUnsafeMutableBufferPointer { fresh.process($0) }

    #expect(afterReset == freshOutput)
  }
}
