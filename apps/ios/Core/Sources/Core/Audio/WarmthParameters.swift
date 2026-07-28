import Foundation

/// The coordinated parameter set the Enhance `warmth` dial maps to. A single
/// `warmth` in `0...1` drives every field along a curated curve (see
/// `warmthParameters(_:)`); the dial never touches these individually. Pure
/// data, no DSP, so the mapping is testable on its own — which is the whole
/// reason it is a separate type from `WarmthProcessor`.
public struct WarmthParameters: Equatable, Sendable {
  /// Low-mid head-bump bell — centre frequency in Hz.
  public var headBumpFrequency: Double
  /// Head-bump bell gain in dB (`>= 0`): the woody body of the references.
  public var headBumpGainDB: Double
  /// Head-bump bell Q.
  public var headBumpQ: Double
  /// High-shelf softening — corner frequency in Hz.
  public var highShelfFrequency: Double
  /// High-shelf gain in dB (`<= 0`, a cut): the rolled-off tape top.
  public var highShelfGainDB: Double
  /// Saturation drive (`>= 0`). `0` is linear; larger is more tape grit. The
  /// character waveshaper is `tanh(drive · x) / drive`, so drive alone sets the
  /// harmonic content while keeping unity small-signal gain.
  public var drive: Double
  /// Make-up gain in dB (`>= 0`) that level-matches the saturated output so the
  /// dial changes character, not volume.
  public var makeupGainDB: Double
  /// Output ceiling in linear full scale, `0 < ceiling < 1`. The final
  /// `ceiling · tanh(x / ceiling)` stage cannot exceed it, which is what makes
  /// no-clipping structural rather than something the curve has to be tuned to
  /// avoid.
  public var ceiling: Double

  public init(
    headBumpFrequency: Double,
    headBumpGainDB: Double,
    headBumpQ: Double,
    highShelfFrequency: Double,
    highShelfGainDB: Double,
    drive: Double,
    makeupGainDB: Double,
    ceiling: Double
  ) {
    self.headBumpFrequency = headBumpFrequency
    self.headBumpGainDB = headBumpGainDB
    self.headBumpQ = headBumpQ
    self.highShelfFrequency = highShelfFrequency
    self.highShelfGainDB = highShelfGainDB
    self.drive = drive
    self.makeupGainDB = makeupGainDB
    self.ceiling = ceiling
  }
}

/// Map one `warmth` (clamped to `0...1`) to the coordinated set. Pure and
/// deterministic — no wow, flutter, or modulation lives here or downstream.
///
/// Every coloring term rises with `warmth` along a linear ramp for now; the
/// final voicing is found by ear against the reference records in Unit 2 (#24),
/// so this ships a musically sensible starting curve, not a finished one. At
/// `warmth == 0` every active term is neutral, so the parameters alone describe
/// a true bypass even before `WarmthProcessor` short-circuits it.
public func warmthParameters(_ warmth: Double) -> WarmthParameters {
  let w = min(max(warmth, 0), 1)
  return WarmthParameters(
    headBumpFrequency: 90,
    headBumpGainDB: 3.5 * w,
    headBumpQ: 0.7,
    highShelfFrequency: 3500,
    highShelfGainDB: -4.0 * w,
    drive: 2.2 * w,
    makeupGainDB: 0.8 * w,
    ceiling: 0.9772  // ~ −0.2 dBFS
  )
}
