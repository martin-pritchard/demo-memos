import Foundation
import Synchronization

/// The realtime half of on-device Enhance (#24): it hosts Unit 1's
/// `WarmthKernel` over a preloaded take and is driven, one block at a time, from
/// an `AVAudioSourceNode` render block. Deliberately framework-free — no
/// `AVFoundation`, no UI — so the *graph arithmetic* (bypass at 0, the smoothed
/// dial response, level-matched colour, end-of-take) is verified under
/// `swift test` with no engine and no simulator (`docs/PRINCIPLES.ios.md` #2, #4).
///
/// **Thread discipline** — this is why `@unchecked Sendable` is sound:
/// - `load(samples:)` and `reset()` run on the setup thread *before* the source
///   node is started; nothing renders concurrently with them.
/// - `render(into:)` runs on the realtime thread and is the *only* mutator of
///   the DSP state (cursor, kernel, smoothed warmth) once playback is live.
/// - The dial (`setTargetWarmth`) and the end poll (`hasReachedEnd`) cross
///   threads through `Atomic` only — lock-free, allocation-free, no async, so
///   the render block never blocks (`docs/PRINCIPLES.ios.md` #1).
public final class WarmthRenderCore: @unchecked Sendable {

  private let sampleRate: Double
  /// Smoothing time constant for a dial move, in seconds. A one-pole glide over
  /// ~this long declicks a parameter change; it is a one-shot response to the
  /// user, categorically not the wow/flutter #21 forbids. Injectable so the
  /// value can be tuned by ear on device and driven hard/soft in tests.
  private let smoothingTau: Double

  // Immutable once `load` returns; read (never written) on the realtime thread.
  private var samples: [Float] = []

  // Realtime-thread-owned. Touched only inside `render`, except where `load`
  // primes them before the first render.
  private var cursor = 0
  private var kernel: WarmthKernel
  /// The dial value the DSP is currently voiced for — glides toward the target.
  private(set) var currentWarmth: Double = 0
  /// The warmth the kernel's coefficients were last computed for; `.nan` forces
  /// the first `update`.
  private var appliedWarmth: Double = .nan

  // Cross-thread, lock-free. Warmth is carried as its bit pattern because
  // `Double` is not itself `AtomicRepresentable`.
  private let targetWarmthBits: Atomic<UInt64>
  private let ended: Atomic<Bool>

  /// Below this the glide snaps to the target, so a move to 0 reaches *true*
  /// bypass and a move to any value settles instead of crawling forever.
  private let snapEpsilon = 1e-4

  public init(sampleRate: Double, smoothingTimeConstant: Double = 0.025) {
    self.sampleRate = sampleRate
    self.smoothingTau = smoothingTimeConstant
    self.kernel = WarmthKernel(parameters: warmthParameters(0), sampleRate: sampleRate)
    self.targetWarmthBits = Atomic(0.0.bitPattern)
    self.ended = Atomic(false)
  }

  // MARK: - Setup (setup thread, before the node starts)

  /// Hand the core the whole take, decoded to mono ±1.0, and arm it from frame
  /// zero. The dial does *not* glide on start — `currentWarmth` snaps to the
  /// target so pressing play with the dial already up sounds enhanced from the
  /// first sample; the glide is only for moves *during* playback.
  public func load(samples: [Float]) {
    self.samples = samples
    cursor = 0
    ended.store(false, ordering: .relaxed)
    currentWarmth = clampedTarget()
    appliedWarmth = .nan
    kernel.reset()
  }

  // MARK: - Dial (any thread)

  /// Set the Enhance target. Clamped to `0...1`; picked up by the next render
  /// block and glided toward. Safe to call before `load`, while playing, or idle.
  public func setTargetWarmth(_ warmth: Double) {
    let w = min(max(warmth, 0), 1)
    targetWarmthBits.store(w.bitPattern, ordering: .relaxed)
  }

  /// True once the render block has read past the last frame of the take. The
  /// player polls this on the main actor and fires `onFinish` there — the render
  /// thread never touches UI or observable state.
  public var hasReachedEnd: Bool { ended.load(ordering: .relaxed) }

  private func clampedTarget() -> Double {
    Double(bitPattern: targetWarmthBits.load(ordering: .relaxed))
  }

  // MARK: - Render (realtime thread only)

  /// Fill `output` with the next block of the take, coloured by the current
  /// (smoothed) warmth. Allocation-free, lock-free, no async: only reads/writes
  /// the caller's buffer, the preloaded array, the atomics, and `libm`.
  public func render(into output: UnsafeMutableBufferPointer<Float>) {
    let frames = output.count
    guard frames > 0 else { return }

    // 1. Glide the single scalar toward the dial target, once per block. One
    //    pole with a per-block coefficient so the time constant holds whatever
    //    the block size is.
    let target = clampedTarget()
    if currentWarmth != target {
      let alpha = 1 - exp(-Double(frames) / (smoothingTau * sampleRate))
      currentWarmth += (target - currentWarmth) * alpha
      if abs(target - currentWarmth) < snapEpsilon { currentWarmth = target }
    }

    // 2. Recompute coefficients only when the voicing actually moved. `libm`
    //    only, no allocation — safe in the render block per #1.
    if currentWarmth != appliedWarmth {
      kernel.update(warmthParameters(currentWarmth))
      appliedWarmth = currentWarmth
    }

    // 3. Copy the take into the output; zero-pad and latch the end if we run out.
    let available = max(0, samples.count - cursor)
    let toCopy = min(frames, available)
    if toCopy > 0 {
      samples.withUnsafeBufferPointer { src in
        output.baseAddress!.update(from: src.baseAddress! + cursor, count: toCopy)
      }
      cursor += toCopy
    }
    if toCopy < frames {
      for i in toCopy..<frames { output[i] = 0 }
      ended.store(true, ordering: .relaxed)
    }

    // 4. warmth 0 is *true bypass*: the frames from step 3 are the recording,
    //    untouched. Otherwise colour in place — only the real frames, never the
    //    silent tail past the end of the take.
    if currentWarmth > 0, toCopy > 0 {
      let voiced = UnsafeMutableBufferPointer(start: output.baseAddress!, count: toCopy)
      kernel.process(voiced)
    }
  }
}
