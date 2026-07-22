import SwiftUI

/// The Photos-style Enhance dial: a tick scale that scrolls under a fixed
/// centre marker, rather than a thumb sliding along a track. The same control
/// appears at record time and on playback, so the one thing you learn works
/// everywhere.
struct EnhanceSlider: View {
  @Binding var value: Double

  private static let trackWidth: CGFloat = 300
  private static let tickGap: CGFloat = 14
  private static let tickCount = 41
  private static var stripWidth: CGFloat { CGFloat(tickCount - 1) * tickGap }

  @State private var dragOrigin: (start: CGFloat, value: Double)?

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 7) {
        Image(systemName: "wand.and.sparkles")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Palette.accent)
        Text("Enhance · \(Palette.toneName(value))")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Palette.accentText)
      }
      .accessibilityHidden(true)

      track
    }
    .frame(width: Self.trackWidth)
    .accessibilityElement()
    .accessibilityLabel("Enhance")
    .accessibilityValue(Palette.toneName(value))
    .accessibilityAdjustableAction { direction in
      let step = 1.0 / Double(Self.tickCount - 1)
      value = min(max(value + (direction == .increment ? step : -step), 0), 1)
    }
  }

  private var track: some View {
    ZStack {
      ticks
        .frame(width: Self.trackWidth, height: 40)
        .clipped()
        .mask(
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0),
              .init(color: .black, location: 0.16),
              .init(color: .black, location: 0.84),
              .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
      marker
    }
    .frame(width: Self.trackWidth, height: 40)
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { gesture in
          let origin = dragOrigin ?? (gesture.startLocation.x, value)
          dragOrigin = origin
          // Drag left → value up: the scale scrolls left under the marker.
          let delta = (origin.start - gesture.location.x) / Self.stripWidth
          value = min(max(origin.value + delta, 0), 1)
        }
        .onEnded { _ in dragOrigin = nil }
    )
  }

  private var ticks: some View {
    HStack(spacing: Self.tickGap - 2) {
      ForEach(0..<Self.tickCount, id: \.self) { index in
        let major = index % 5 == 0
        Capsule()
          .fill(major ? Color(.tertiaryLabel) : Color(.quaternaryLabel))
          .frame(width: 2, height: major ? 20 : 11)
      }
    }
    // The tick for `value` sits under the marker; the strip moves, not a thumb.
    .offset(x: Self.stripWidth / 2 - value * Self.stripWidth)
  }

  private var marker: some View {
    ZStack(alignment: .top) {
      Capsule()
        .fill(Palette.accent)
        .frame(width: 3, height: 30)
        .shadow(color: Palette.accent.opacity(0.55), radius: 3)
        .offset(y: 5)
      Circle()
        .fill(Palette.accent)
        .frame(width: 11, height: 11)
        .shadow(color: Palette.accent.opacity(0.5), radius: 3, y: 2)
        .offset(y: 2)
    }
    .frame(height: 40, alignment: .top)
    .allowsHitTesting(false)
  }
}

#Preview {
  @Previewable @State var value = 0.5
  return EnhanceSlider(value: $value)
    .padding(40)
}
