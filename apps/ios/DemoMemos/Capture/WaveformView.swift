import SwiftUI

/// The one waveform surface, in the two forms the design uses:
///
/// - `.live` — capture. Bars fill the width and scroll in from the right.
/// - `.scrub` — review. The take scrolls under a fixed centre marker (12a):
///   4pt orange line, no dot, clearing the bars, played side warm and fading
///   over the last six bars so the marker separates. Hard edges.
///
/// Enhance drives the warm bloom behind the bars. It processes nothing.
struct WaveformView: View {
  enum Mode {
    case live
    case scrub(progress: Double)
  }

  let levels: [Float]
  let mode: Mode
  let enhance: Double

  private var space: Double { enhance * 0.7 }

  var body: some View {
    ZStack {
      bloom
      switch mode {
      case .live:
        liveBars
      case .scrub(let progress):
        scrubBars(progress: progress)
        marker
      }
    }
    .frame(height: 120)
    .frame(maxWidth: .infinity)
  }

  // MARK: - Bloom

  /// Warm radial aura that widens with Enhance — the ChromaVerb nod, never a
  /// literal reverb tail.
  private var bloom: some View {
    GeometryReader { proxy in
      Ellipse()
        .fill(
          RadialGradient(
            colors: [Palette.accent.opacity(0.09 + space * 0.16), .clear],
            center: .center,
            startRadius: 0,
            endRadius: proxy.size.width * 0.5 * (0.58 + space * 0.66)
          )
        )
        .frame(
          width: proxy.size.width * (0.58 + space * 0.66),
          height: proxy.size.height * (1.18 + space * 0.90)
        )
        .blur(radius: 7 + space * 11)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .allowsHitTesting(false)
  }

  // MARK: - Live

  private var liveBars: some View {
    Canvas { context, size in
      guard !levels.isEmpty else { return }
      let gap: CGFloat = 3
      let barWidth = max(1, (size.width - gap * CGFloat(levels.count - 1)) / CGFloat(levels.count))
      let colour = Palette.warm(0.35 + enhance * 0.65)
      for (index, level) in levels.enumerated() {
        let height = max(2, CGFloat(level) * size.height)
        let x = CGFloat(index) * (barWidth + gap)
        let rect = CGRect(
          x: x, y: (size.height - height) / 2, width: barWidth, height: height)
        context.fill(
          Path(roundedRect: rect, cornerRadius: min(4, barWidth / 2)),
          with: .color(level > 0.02 ? colour : Palette.barIdle)
        )
      }
    }
  }

  // MARK: - Scrub

  private static let scrubBarWidth: CGFloat = 5
  private static let scrubGap: CGFloat = 3
  static let scrubStep: CGFloat = scrubBarWidth + scrubGap

  /// Bars nearest the marker fade so the orange line reads cleanly against the
  /// warm played side — the design's 6-bar fade down to 0.45.
  private static let fadeSpan = 6.0
  private static let fadeMinimum = 0.45

  private func scrubBars(progress: Double) -> some View {
    Canvas { context, size in
      guard !levels.isEmpty else { return }
      let peak = CGFloat(levels.max() ?? 1)
      let playIndex = progress * Double(levels.count - 1)
      let originX = size.width / 2 - CGFloat(playIndex) * Self.scrubStep
      let amber = Palette.warm(0.35 + enhance * 0.65)

      for (index, level) in levels.enumerated() {
        let x = originX + CGFloat(index) * Self.scrubStep
        guard x > -Self.scrubStep, x < size.width + Self.scrubStep else { continue }
        let height = max(2, CGFloat(level) / max(peak, 0.001) * size.height * 0.94)
        let rect = CGRect(
          x: x, y: (size.height - height) / 2, width: Self.scrubBarWidth, height: height)
        let colour: Color
        if Double(index) > playIndex {
          colour = Palette.barIdle
        } else {
          let distance = playIndex - Double(index)
          let alpha =
            Self.fadeMinimum + (1 - Self.fadeMinimum) * min(1, distance / Self.fadeSpan)
          colour = amber.opacity(alpha)
        }
        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(colour))
      }
    }
    .clipped()
  }

  private var marker: some View {
    Capsule()
      .fill(Palette.accent)
      .frame(width: 4)
      .padding(.vertical, -4)
      .shadow(color: Palette.accent.opacity(0.55), radius: 3)
      .allowsHitTesting(false)
  }
}

#Preview("Live · recording") {
  WaveformView(
    levels: (0..<48).map { _ in Float.random(in: 0.15...0.9) },
    mode: .live,
    enhance: 0.6
  )
  .padding()
}

#Preview("Live · at rest") {
  WaveformView(levels: Array(repeating: 0, count: 48), mode: .live, enhance: 0)
    .padding()
}

#Preview("Scrub · centre-locked") {
  WaveformView(
    levels: (0..<220).map { index in
      0.12 + Float.random(in: 0.2...0.9) * Float(sin(Double(index) / 220 * .pi))
    },
    mode: .scrub(progress: 0.32),
    enhance: 0.6
  )
  .padding()
}
