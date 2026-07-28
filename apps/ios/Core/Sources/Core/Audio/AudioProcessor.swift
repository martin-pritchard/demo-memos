/// The seam shipping DSP will conform to: one buffer in, one buffer out. Keeping
/// it this narrow is deliberate — the Enhance chain, when it lands, is just an
/// `AudioProcessor`, and the test harness can null-test any conforming type
/// against its input without knowing what it does.
public protocol AudioProcessor {
  func process(_ buffer: SampleBuffer) -> SampleBuffer
}

/// The seam's second half until real Enhance DSP arrives (per
/// `docs/PRINCIPLES.ios.md` #3: a seam ships both halves). Returns its input
/// unchanged, so it null-tests perfectly clean — the reference every future
/// processor is measured against.
public struct IdentityProcessor: AudioProcessor {
  public init() {}

  public func process(_ buffer: SampleBuffer) -> SampleBuffer { buffer }
}
