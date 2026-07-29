import Testing

@testable import Core

@Suite("WarmthRenderCore position and seeking")
struct WarmthRenderCoreSeekTests {

  /// A distinctive take: `take[k] == Float(k)`, so an off-by-one is visible.
  private let take = (0..<100).map { Float($0) }

  private func makeCore() -> WarmthRenderCore {
    let core = WarmthRenderCore(sampleRate: 48000)
    // True bypass throughout, so every sample comparison is exact.
    core.setTargetWarmth(0)
    return core
  }

  private func makeLoadedCore(_ samples: [Float]) -> WarmthRenderCore {
    let core = makeCore()
    core.load(samples: samples)
    return core
  }

  private func render(_ core: WarmthRenderCore, frames: Int) -> [Float] {
    var out = [Float](repeating: .nan, count: frames)
    out.withUnsafeMutableBufferPointer { core.render(into: $0) }
    return out
  }

  @Test("reports no frames before a take is loaded, and the take's length afterwards")
  func reportsNoFramesBeforeATakeIsLoadedAndTheTakesLengthAfterwards() {
    let core = makeCore()
    #expect(core.frameCount == 0)

    core.load(samples: take)
    #expect(core.frameCount == take.count)
  }

  @Test("has rendered nothing immediately after loading a take")
  func hasRenderedNothingImmediatelyAfterLoadingATake() {
    let core = makeLoadedCore(take)
    #expect(core.framesRendered == 0)
  }

  @Test("advances the rendered frame count by the length of the block it filled")
  func advancesTheRenderedFrameCountByTheLengthOfTheBlockItFilled() {
    let core = makeLoadedCore(take)

    _ = render(core, frames: 16)

    #expect(core.framesRendered == 16)
  }

  @Test("accumulates the rendered frame count across successive blocks")
  func accumulatesTheRenderedFrameCountAcrossSuccessiveBlocks() {
    let core = makeLoadedCore(take)

    _ = render(core, frames: 16)
    _ = render(core, frames: 16)

    #expect(core.framesRendered == 32)
  }

  @Test("saturates the rendered frame count at the length of the take")
  func saturatesTheRenderedFrameCountAtTheLengthOfTheTake() {
    let core = makeLoadedCore(take)

    _ = render(core, frames: 128)

    #expect(core.framesRendered == take.count)
  }

  @Test("leaves the rendered frame count untouched until the next render happens")
  func leavesTheRenderedFrameCountUntouchedUntilTheNextRenderHappens() {
    let core = makeLoadedCore(take)
    _ = render(core, frames: 16)
    #expect(core.framesRendered == 16)

    core.seek(toFrame: 70)
    #expect(core.framesRendered == 16)

    _ = render(core, frames: 8)
    #expect(core.framesRendered == 78)
  }

  @Test("counts rendered frames from the sought position onwards")
  func countsRenderedFramesFromTheSoughtPositionOnwards() {
    let core = makeLoadedCore(take)

    core.seek(toFrame: 40)
    _ = render(core, frames: 12)

    #expect(core.framesRendered == 52)
  }

  @Test("renders the take's own samples starting at the sought frame")
  func rendersTheTakesOwnSamplesStartingAtTheSoughtFrame() {
    let core = makeLoadedCore(take)

    core.seek(toFrame: 40)
    let out = render(core, frames: 8)

    #expect(out == Array(take[40..<48]))
  }

  @Test("clamps a seek below zero to the start of the take")
  func clampsASeekBelowZeroToTheStartOfTheTake() {
    let core = makeLoadedCore(take)
    _ = render(core, frames: 32)

    core.seek(toFrame: -25)
    let out = render(core, frames: 8)

    #expect(out == Array(take[0..<8]))
    #expect(core.framesRendered == 8)
  }

  @Test("clamps a seek past the end to the end of the take and renders silence")
  func clampsASeekPastTheEndToTheEndOfTheTakeAndRendersSilence() {
    let core = makeLoadedCore(take)

    core.seek(toFrame: take.count + 500)
    let out = render(core, frames: 8)

    #expect(out == [Float](repeating: 0, count: 8))
    #expect(core.framesRendered == take.count)
    #expect(core.hasReachedEnd)
  }

  @Test("clears the end latch at the seek itself, not at the next render")
  func clearsTheEndLatchAtTheSeekItselfNotAtTheNextRender() {
    let core = makeLoadedCore(take)
    _ = render(core, frames: 128)
    #expect(core.hasReachedEnd)

    core.seek(toFrame: 0)

    #expect(!core.hasReachedEnd)
  }

  @Test("plays the take's real samples again after seeking back from the end")
  func playsTheTakesRealSamplesAgainAfterSeekingBackFromTheEnd() {
    let core = makeLoadedCore(take)
    _ = render(core, frames: 128)
    #expect(core.hasReachedEnd)

    core.seek(toFrame: 0)
    let out = render(core, frames: 8)

    #expect(out == Array(take[0..<8]))
    #expect(core.framesRendered == 8)
  }

  @Test("discards a seek made before any take is loaded")
  func discardsASeekMadeBeforeAnyTakeIsLoaded() {
    let core = makeCore()

    core.seek(toFrame: 40)
    core.load(samples: take)

    #expect(core.framesRendered == 0)
    #expect(render(core, frames: 8) == Array(take[0..<8]))
  }

  @Test("re-arms from frame zero when a second take is loaded")
  func reArmsFromFrameZeroWhenASecondTakeIsLoaded() {
    let core = makeLoadedCore(take)
    _ = render(core, frames: 32)
    #expect(core.framesRendered == 32)

    let shorterTake = (0..<10).map { Float($0) * -1 }
    core.load(samples: shorterTake)

    #expect(core.frameCount == shorterTake.count)
    #expect(core.framesRendered == 0)
    #expect(render(core, frames: 4) == Array(shorterTake[0..<4]))
  }
}
