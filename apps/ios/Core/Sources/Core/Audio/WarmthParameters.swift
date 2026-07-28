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
  /// Reverb wet mix as a fraction, `0...1` (`0` fully dry). Unlike every field
  /// above this is *not* consumed by `WarmthKernel`/`WarmthProcessor` — the
  /// warmth DSP stays dry. It is applied by the playback engine's
  /// `AVAudioUnitReverb` (#22): the one dial folds a touch of space in on top of
  /// the tape colouring, rising along the same curve.
  public var reverbWetMix: Double

  public init(
    headBumpFrequency: Double,
    headBumpGainDB: Double,
    headBumpQ: Double,
    highShelfFrequency: Double,
    highShelfGainDB: Double,
    drive: Double,
    makeupGainDB: Double,
    ceiling: Double,
    reverbWetMix: Double
  ) {
    self.headBumpFrequency = headBumpFrequency
    self.headBumpGainDB = headBumpGainDB
    self.headBumpQ = headBumpQ
    self.highShelfFrequency = highShelfFrequency
    self.highShelfGainDB = highShelfGainDB
    self.drive = drive
    self.makeupGainDB = makeupGainDB
    self.ceiling = ceiling
    self.reverbWetMix = reverbWetMix
  }
}

/// Map one `warmth` (clamped to `0...1`) to the coordinated set. Pure and
/// deterministic — no wow, flutter, or modulation lives here or downstream.
///
/// The dial is mapped onto the *usable* part of the sweep: `0…1` covers what
/// used to be ~50%…100% of travel, so the colouring is active across the whole
/// length instead of hiding its bottom third near silence. The voicing is still
/// being found by ear against the reference records under #28. At `warmth == 0`
/// every active term is neutral, so the parameters alone describe a true bypass
/// even before `WarmthProcessor` short-circuits it.
public func warmthParameters(_ warmth: Double) -> WarmthParameters {
  let w = min(max(warmth, 0), 1)
  // Spread the usable part of the sweep across the whole dial: `0…1` maps onto
  // what used to be `floor…1` of travel, killing the near-silent bottom third.
  // `warmth == 0` stays an exact bypass (`c == 0`); just above it the map floors
  // ~0.6 dB above dry — inaudible — so lifting off zero doesn't click. `shape`
  // keeps a gentle convexity so it still eases in; `1.0` at the top is unchanged.
  let floor = 0.50
  let shape = 2.0
  let c = w == 0 ? 0 : pow(floor + (1 - floor) * w, shape)
  // Reverb rides the same `c`, so the one dial folds a touch of space in with the
  // warmth (#22). `reverbMaxWet` is the wet fraction at the top of the dial — kept
  // subtle for the intimate, "dry take made finished" target; tuned by ear.
  let reverbMaxWet = 0.35
  return WarmthParameters(
    headBumpFrequency: 120,
    headBumpGainDB: 7.8 * c,
    headBumpQ: 0.7,
    highShelfFrequency: 3500,
    highShelfGainDB: -10.4 * c,
    drive: 2.2 * c,
    makeupGainDB: 0.8 * c,
    ceiling: 0.9772,  // ~ −0.2 dBFS
    reverbWetMix: reverbMaxWet * c
  )
}
