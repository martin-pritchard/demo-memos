import Core
import Foundation

// Measurement primitives for the test harness. Pure functions over a
// `SampleBuffer`, sharing one convention: level is dBFS against 1.0 full scale,
// and a signal with no energy reads −∞, never a floor — a floor would let a
// silent buffer slip past a level assertion.

/// Largest instantaneous excursion, in dBFS. `−∞` for a silent or empty buffer.
func peakDBFS(_ buffer: SampleBuffer) -> Double {
  var peak: Float = 0
  for sample in buffer.samples { peak = max(peak, abs(sample)) }
  guard peak > 0 else { return -.infinity }
  return 20 * log10(Double(peak))
}

/// Root-mean-square level, in dBFS. A sine's RMS sits 3.01 dB below its peak.
/// `−∞` for a silent or empty buffer.
func rmsDBFS(_ buffer: SampleBuffer) -> Double {
  guard !buffer.samples.isEmpty else { return -.infinity }
  var sumOfSquares = 0.0
  for sample in buffer.samples {
    let value = Double(sample)
    sumOfSquares += value * value
  }
  let rms = (sumOfSquares / Double(buffer.samples.count)).squareRoot()
  guard rms > 0 else { return -.infinity }
  return 20 * log10(rms)
}

/// The linear mean of every sample — the raw DC bias, not a level. `0` for an
/// empty buffer. Kept linear on purpose: callers that want it in dBFS take the
/// log themselves, and a signed bias has no dB.
func dcOffset(_ buffer: SampleBuffer) -> Double {
  guard !buffer.samples.isEmpty else { return 0 }
  var sum = 0.0
  for sample in buffer.samples { sum += Double(sample) }
  return sum / Double(buffer.samples.count)
}

/// Total harmonic distortion as a ratio: the energy in harmonics 2…10 over the
/// fundamental's, measured by Goertzel at each frequency. Harmonics at or above
/// Nyquist are skipped. `nil` when the fundamental carries no energy (silence) —
/// there is nothing to be distorted relative to.
///
/// Fixtures must contain a whole number of cycles so a rectangular window leaks
/// nothing; a fractional count would read as distortion that isn't there.
func thd(_ buffer: SampleBuffer, fundamental: Double) -> Double? {
  let channel = channelZero(of: buffer)
  guard !channel.isEmpty else { return nil }

  let nyquist = buffer.sampleRate / 2
  let fundamentalMagnitude = goertzelMagnitude(
    channel, frequency: fundamental, sampleRate: buffer.sampleRate)
  guard fundamentalMagnitude > 0 else { return nil }

  var harmonicPower = 0.0
  for harmonic in 2...10 {
    let frequency = fundamental * Double(harmonic)
    guard frequency < nyquist else { continue }
    let magnitude = goertzelMagnitude(channel, frequency: frequency, sampleRate: buffer.sampleRate)
    harmonicPower += magnitude * magnitude
  }
  return harmonicPower.squareRoot() / fundamentalMagnitude
}

// MARK: - Internals

/// The first channel, deinterleaved. THD is a single-channel measurement; the
/// fixtures are mono, but this keeps the maths honest if a caller passes stereo.
private func channelZero(of buffer: SampleBuffer) -> [Float] {
  guard buffer.channelCount > 1 else { return buffer.samples }
  return stride(from: 0, to: buffer.samples.count, by: buffer.channelCount).map {
    buffer.samples[$0]
  }
}

/// Goertzel magnitude at one frequency — an O(n) DFT bin, no windowing.
private func goertzelMagnitude(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double
{
  let omega = 2 * Double.pi * frequency / sampleRate
  let coefficient = 2 * cos(omega)
  var s0 = 0.0
  var s1 = 0.0
  var s2 = 0.0
  for sample in samples {
    s0 = Double(sample) + coefficient * s1 - s2
    s2 = s1
    s1 = s0
  }
  let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
  return max(power, 0).squareRoot()
}
