import Core
import Foundation
import Testing

// Swift Testing assertions built on the measurement primitives. Each takes a
// `sourceLocation` defaulting to the call site, so a failure points at the test
// that made the claim, not at this file.

/// Fails when any sample reaches full scale. The threshold is `|sample| >= 1.0`
/// — at, not beyond: a sample sitting exactly on 1.0 is already clipped.
func assertNoClipping(
  _ buffer: SampleBuffer,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  var peak: Float = 0
  for sample in buffer.samples { peak = max(peak, abs(sample)) }
  #expect(
    peak < 1.0,
    "clipping: peak sample \(peak) is at or beyond full scale",
    sourceLocation: sourceLocation
  )
}

/// Subtracts `b` from `a` sample-by-sample and checks the residual's peak is at
/// or below `tolerance` dBFS. Two identical buffers null to −∞; a 24-bit
/// round-trip nulls to roughly −140. A shape mismatch (rate, channel count, or
/// length) records a failure rather than trapping, so a wrong-shaped comparison
/// fails the test instead of the process.
func nullTest(
  _ a: SampleBuffer,
  _ b: SampleBuffer,
  tolerance: Double,
  sourceLocation: SourceLocation = #_sourceLocation
) {
  guard a.sampleRate == b.sampleRate,
    a.channelCount == b.channelCount,
    a.samples.count == b.samples.count
  else {
    Issue.record(
      """
      nullTest: buffers differ in shape — \
      rate \(a.sampleRate)/\(b.sampleRate), \
      channels \(a.channelCount)/\(b.channelCount), \
      length \(a.samples.count)/\(b.samples.count)
      """,
      sourceLocation: sourceLocation
    )
    return
  }
  let residual = SampleBuffer(
    sampleRate: a.sampleRate,
    channelCount: a.channelCount,
    samples: zip(a.samples, b.samples).map { $0 - $1 }
  )
  let residualPeak = peakDBFS(residual)
  #expect(
    residualPeak <= tolerance,
    "nullTest: residual peak \(residualPeak) dBFS exceeds tolerance \(tolerance) dBFS",
    sourceLocation: sourceLocation
  )
}
