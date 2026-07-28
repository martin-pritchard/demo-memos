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
  /// Leveler threshold in dBFS (`<= 0`): the envelope level above which gain
  /// reduction begins. Descends as the dial rises, so more of the take is
  /// levelled. Always at or below `levelerPivotDBFS`, which is what keeps
  /// `levelerMakeupGainDB` a non-negative quantity.
  public var levelerThresholdDB: Double
  /// Leveler ratio (`>= 1`). `1` is an exact identity — no compression, no
  /// branch needed — which is how the stage bypasses itself at `warmth == 0`.
  /// Stays low (a leveler, ~2:1) because slammed compression pumps and reads as
  /// cheap; gentle is the intimacy win.
  public var levelerRatio: Double
  /// Leveler attack in seconds (`> 0`). Constant across the dial: slow enough to
  /// let transients through, so strums keep their attack.
  public var levelerAttack: Double
  /// Leveler release in seconds (`> 0`, and longer than the attack). Constant
  /// across the dial. Slow release is what makes this *program levelling* rather
  /// than the fast waveshaping `drive` already does — different jobs.
  public var levelerRelease: Double
  /// Leveler make-up in dB (`>= 0`). **Derived, never voiced independently** —
  /// see `warmthParameters(_:)`. It is pinned so a signal sitting at
  /// `levelerPivotDBFS` passes through the leveler unchanged, which is what
  /// makes "character, not volume" structural rather than something the curve
  /// has to be tuned around.
  public var levelerMakeupGainDB: Double
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
    levelerThresholdDB: Double,
    levelerRatio: Double,
    levelerAttack: Double,
    levelerRelease: Double,
    levelerMakeupGainDB: Double,
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
    self.levelerThresholdDB = levelerThresholdDB
    self.levelerRatio = levelerRatio
    self.levelerAttack = levelerAttack
    self.levelerRelease = levelerRelease
    self.levelerMakeupGainDB = levelerMakeupGainDB
    self.reverbWetMix = reverbWetMix
  }
}

/// The operating level the leveler's make-up gain is referenced to, in dBFS —
/// roughly where a well-tracked take sits (`docs/PRINCIPLES.ios.md` and the
/// `ios-audio` skill both target −6…−12 dBFS peaks).
///
/// This is the pivot the whole "character, not volume" guarantee turns on. Gain
/// reduction alone makes the dial quieter; auto make-up referenced to *full
/// scale* would make it louder — roughly +6 dB on a −12 dBFS take, which is the
/// loudness-control-in-a-costume failure #21 warns about. Referencing the make-up
/// here instead pins the middle of the take in place: louder passages come down,
/// quieter detail comes up, and the level the user tracked at does not move.
public let levelerPivotDBFS: Double = -12

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

  // The leveler (#32) rides the same `c`. Two terms are voiced, and the third is
  // derived rather than chosen:
  //
  // - `threshold` descends *from the pivot*, never above it, so more of the take
  //   is levelled as the dial rises. Starting at the pivot (rather than at 0 dBFS)
  //   is what keeps the make-up below a closed form instead of clamping through
  //   the bottom half of the dial.
  // - `ratio` stays gentle — a leveler, not a squasher. `1` at the very bottom is
  //   an exact identity, so the stage bypasses itself without a branch.
  // - `makeup` is *derived* so a signal at `levelerPivotDBFS` passes through
  //   unchanged: for input `L` above the threshold `T` at ratio `R`, the leveler
  //   outputs `T + (L − T)/R`, so restoring `L == pivot` needs exactly
  //   `(pivot − T)·(1 − 1/R)` back. Deriving it means no tuning pass can leave
  //   the dial louder than it started — the guarantee holds by construction, the
  //   way the bounded `ceiling` makes no-clipping structural.
  //   `max(0, …)` is defensive only: `threshold <= pivot` above keeps it positive.
  let levelerMaxDepthDB = 6.0
  let levelerMaxRatio = 2.0
  let threshold = levelerPivotDBFS - levelerMaxDepthDB * c
  let ratio = 1 + (levelerMaxRatio - 1) * c
  let makeup = max(0, (levelerPivotDBFS - threshold) * (1 - 1 / ratio))

  return WarmthParameters(
    headBumpFrequency: 120,
    headBumpGainDB: 7.8 * c,
    headBumpQ: 0.7,
    highShelfFrequency: 3500,
    highShelfGainDB: -10.4 * c,
    drive: 2.2 * c,
    makeupGainDB: 0.8 * c,
    ceiling: 0.9772,  // ~ −0.2 dBFS
    levelerThresholdDB: threshold,
    levelerRatio: ratio,
    // Fixed, not dial-driven: these two *are* the difference between levelling and
    // squashing, and nothing at any dial position wants them faster. Slow enough
    // to let a strum's attack through, slow enough on release to ride the
    // performance rather than pump on it.
    levelerAttack: 0.020,
    levelerRelease: 0.250,
    levelerMakeupGainDB: makeup,
    reverbWetMix: reverbMaxWet * c
  )
}
