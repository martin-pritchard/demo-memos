import Foundation
import Testing

@testable import Core

/// The graph arithmetic of on-device Enhance, verified with no engine and no
/// simulator (`docs/PRINCIPLES.ios.md` #2, #4). What is left unverified until a
/// device — the by-ear voicing, real dial clicks, dropouts — is called out in
/// the issue, not here.
@Suite("Warmth render core")
struct WarmthRenderCoreTests {

  private let sampleRate = 48_000.0

  /// Render the whole of `input` in a single block and return the output frames.
  private func renderWhole(_ core: WarmthRenderCore, _ input: [Float]) -> [Float] {
    var out = [Float](repeating: 0, count: input.count)
    out.withUnsafeMutableBufferPointer { core.render(into: $0) }
    return out
  }

  @Test("warmth 0 is a true bypass — output is the recording, untouched")
  func bypassAtZeroIsIdentity() {
    let core = WarmthRenderCore(sampleRate: sampleRate)
    core.setTargetWarmth(0)
    let take = Fixtures.sine(dbFS: -6).samples
    core.load(samples: take)

    let out = renderWhole(core, take)

    #expect(out == take, "warmth 0 must pass the frames through verbatim")
  }

  @Test("A settled dial matches the offline WarmthProcessor exactly")
  func settledWarmthMatchesOfflineProcessor() {
    // Same kernel, same input, same reset state — the realtime path and the
    // offline guardrail path must agree, which is what ties this unit to Unit 1's
    // already-verified DSP.
    let take = Fixtures.sine(dbFS: -6).samples
    for warmth in [0.25, 0.5, 0.75, 1.0] {
      let core = WarmthRenderCore(sampleRate: sampleRate)
      core.setTargetWarmth(warmth)  // set before load → no start glide
      core.load(samples: take)
      let live = renderWhole(core, take)

      let offline = WarmthProcessor(warmth: warmth)
        .process(SampleBuffer(sampleRate: sampleRate, channelCount: 1, samples: take))
        .samples

      var maxDiff: Float = 0
      for (a, b) in zip(live, offline) { maxDiff = max(maxDiff, abs(a - b)) }
      #expect(maxDiff < 1e-5, "warmth \(warmth): live vs offline diverged by \(maxDiff)")
    }
  }

  @Test("Setting the dial before play takes effect from the first sample")
  func startSnapsToTargetWithoutGliding() {
    let core = WarmthRenderCore(sampleRate: sampleRate)
    core.setTargetWarmth(0.7)
    core.load(samples: Fixtures.sine(dbFS: -6).samples)

    var block = [Float](repeating: 0, count: 512)
    block.withUnsafeMutableBufferPointer { core.render(into: $0) }

    #expect(core.currentWarmth == 0.7, "play must not ramp up from 0 on start")
  }

  @Test("A dial move during playback glides — it never jumps in one block")
  func dialMoveGlidesNotJumps() {
    // Silence as the carrier: we are watching the smoothed control value, not the
    // audio. A short time constant so it settles within the buffer.
    let core = WarmthRenderCore(sampleRate: sampleRate, smoothingTimeConstant: 0.02)
    core.setTargetWarmth(0)
    core.load(samples: Fixtures.silence(duration: 1.0).samples)

    core.setTargetWarmth(1)  // the dial move
    var trace: [Double] = []
    var block = [Float](repeating: 0, count: 512)
    for _ in 0..<90 {
      block.withUnsafeMutableBufferPointer { core.render(into: $0) }
      trace.append(core.currentWarmth)
    }

    #expect(trace.first! > 0, "the move must start")
    #expect(trace.first! < 1, "but not arrive in a single block — that would click")
    for (previous, next) in zip(trace, trace.dropFirst()) {
      #expect(next >= previous, "the glide must be monotonic")
    }
    #expect(trace.last! == 1, "and settle exactly on the target")
  }

  @Test("Reading past the end of the take zero-pads and latches the end flag")
  func reachesEndAndZeroPads() {
    let core = WarmthRenderCore(sampleRate: sampleRate)
    core.setTargetWarmth(0.5)
    let take = [Float](repeating: 0.2, count: 300)
    core.load(samples: take)

    #expect(core.hasReachedEnd == false)

    // One block larger than the take: the first 300 are real, the rest silent.
    var block = [Float](repeating: 99, count: 512)
    block.withUnsafeMutableBufferPointer { core.render(into: $0) }
    #expect(core.hasReachedEnd, "running out of take must latch the end")
    #expect(block[400] == 0, "past the end must be silence, not stale buffer")

    // A further block is all silence and stays ended.
    var next = [Float](repeating: 99, count: 512)
    next.withUnsafeMutableBufferPointer { core.render(into: $0) }
    #expect(next.allSatisfy { $0 == 0 })
    #expect(core.hasReachedEnd)
  }
}
