import Foundation
import Testing

@testable import Core

@Suite("Warmth parameter mapping")
struct WarmthParametersTests {

  /// The warmth values swept across several ordering tests.
  private let sweep: [Double] = [0, 0.25, 0.5, 0.75, 1.0]

  @Test("Warmth is clamped to the unit interval at both ends")
  func clampsOutOfRangeWarmth() {
    #expect(warmthParameters(-0.5) == warmthParameters(0))
    #expect(warmthParameters(1.5) == warmthParameters(1))
  }

  @Test("At warmth 0 every coloring gain is bypassed")
  func bypassAtZero() {
    let p = warmthParameters(0)
    #expect(p.headBumpGainDB == 0)
    #expect(p.highShelfGainDB == 0)
    #expect(p.drive == 0)
    #expect(p.makeupGainDB == 0)
  }

  @Test("Drive increases strictly across the warmth sweep")
  func driveStrictlyIncreasing() {
    let drives = sweep.map { warmthParameters($0).drive }
    for i in 1..<drives.count {
      #expect(drives[i] > drives[i - 1])
    }
  }

  @Test("Head-bump gain never falls and high-shelf is a deepening cut")
  func headBumpRisesHighShelfCuts() {
    let params = sweep.map { warmthParameters($0) }
    for i in 1..<params.count {
      #expect(params[i].headBumpGainDB >= params[i - 1].headBumpGainDB)
      #expect(params[i].highShelfGainDB <= params[i - 1].highShelfGainDB)
    }
    for p in params {
      #expect(p.highShelfGainDB <= 0)
    }
  }

  @Test("Make-up gain is non-negative and never falls across the sweep")
  func makeupGainNonNegativeAndNonDecreasing() {
    let gains = sweep.map { warmthParameters($0).makeupGainDB }
    for g in gains {
      #expect(g >= 0)
    }
    for i in 1..<gains.count {
      #expect(gains[i] >= gains[i - 1])
    }
  }

  @Test("Ceiling stays a valid sub-unity bound across the sweep")
  func ceilingIsSubUnity() {
    for w in sweep {
      let ceiling = warmthParameters(w).ceiling
      #expect(ceiling > 0)
      #expect(ceiling < 1)
    }
  }
}
