import SwiftUI

/// The Enhance dial — the app's single audio control.
///
/// Photos-style: a tick scale scrolls horizontally under a fixed centre marker,
/// rather than a thumb sliding along a track. That is why this is a custom
/// component at all. A `Slider` is the right control for "pick a point on a
/// line"; this is "wind a scale past a reading", and the difference is the whole
/// gesture — you push the *scale*, and it keeps moving under your finger long
/// after a thumb would have hit the end of its travel.
///
/// State in, events out. The dial owns no storage: the value is bound in, and
/// every frame of a drag writes back through that binding so the label, the tick
/// offset and the marker move together rather than on release.
///
/// The visual metaphor is bespoke; the semantics are not. The dial exposes
/// itself as an adjustable control, so a VoiceOver user swipes up and down
/// through the same 41 stops a sighted user drags between.
struct EnhanceDial: View {

  /// All from `docs/design/README.md` § Enhance dial. Per-control geometry lives
  /// beside its one consumer rather than in `DesignTokens` (`PRINCIPLES.md` #2,
  /// and the tokens file says so in as many words).
  static let trackWidth: CGFloat = 300
  static let trackHeight: CGFloat = 40

  /// 41 ticks at a 14pt pitch — 0…1 in 40 steps, every 5th major.
  private static let tickCount = 41
  private static let tickPitch: CGFloat = 14
  private static let tickWidth: CGFloat = 2
  private static let majorTickHeight: CGFloat = 20
  private static let minorTickHeight: CGFloat = 11

  /// The scale is wider than its window; that difference is what scrolls.
  private static let stripWidth = CGFloat(tickCount - 1) * tickPitch

  private static let markerWidth: CGFloat = 3
  private static let markerHeight: CGFloat = 30
  private static let markerDotDiameter: CGFloat = 11
  /// The dot rides at the *top* of the marker line, not its centre.
  private static let markerDotCentreY: CGFloat = 7.5

  /// Wand glyph to "Enhance · {tone}". Below the system's 8pt stack minimum.
  private static let labelGap: CGFloat = 7

  /// One tick — the increment a VoiceOver swipe moves.
  private static let step = 1.0 / Double(tickCount - 1)

  @Binding var value: Double

  /// Where the current gesture is measured from. Re-anchored whenever the value
  /// clamps, which is what makes a drag that overshoots an end come back the
  /// instant the finger reverses instead of paying off an invisible debt.
  @State private var anchorValue: Double?
  @State private var anchorTranslation: CGFloat = 0

  /// Alive only for the duration of a drag. SwiftUI resets a `@GestureState`
  /// when the gesture ends **or is cancelled**, and cancellation is the case
  /// that matters: `onEnded` never runs for a drag an enclosing scroll view
  /// steals, so an anchor cleared only there survives into the next touch and
  /// the value jumps the moment a finger lands.
  @GestureState private var isDragging = false

  var body: some View {
    VStack(spacing: DesignTokens.Spacing.label) {
      label
      track
    }
    // Bounds the label to the track, so at the accessibility sizes it wraps
    // rather than widening the component around a track that cannot grow.
    .frame(width: Self.trackWidth)
    .accessibilityElement()
    .accessibilityLabel("Enhance")
    .accessibilityValue(accessibilityValue)
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: value = stepped(by: 1)
      case .decrement: value = stepped(by: -1)
      @unknown default: break
      }
    }
  }

  private var label: some View {
    HStack(spacing: Self.labelGap) {
      // `.large` on the label's own font lands the glyph at ~18pt and keeps it
      // scaling with the text beside it, which a fixed 18pt size would not.
      Image(systemName: "wand.and.stars")
        .imageScale(.large)
      // Non-breaking space before the separator: at the accessibility sizes the
      // label wraps, and a "·" left to start the second line reads as a bullet.
      Text("Enhance\u{00A0}· \(Tone.name(for: value))")
    }
    .font(DesignTokens.Typography.enhanceLabel)
    // The bright amber loses contrast as text on a light page; this is exactly
    // the case the deep accent variant exists for.
    .foregroundStyle(DesignTokens.Palette.accentText)
    .multilineTextAlignment(.center)
  }

  private var track: some View {
    ticks
      .frame(width: Self.trackWidth, height: Self.trackHeight)
      // The handoff's `linear-gradient(90deg, transparent, #000 16%, #000 84%,
      // transparent)`: the scale fades out at both ends rather than being cut
      // off, so there is no hard edge for the eye to read as a boundary.
      .mask(endFade)
      // Over the mask, not under it — otherwise the glow gets clipped.
      .overlay(marker)
      // The whole track is the grab area, including the gaps between ticks.
      .contentShape(Rectangle())
      .gesture(drag)
      // The one reset path for the anchor, so it covers cancellation as well as
      // a clean lift.
      .onChange(of: isDragging) { _, dragging in
        if !dragging {
          anchorValue = nil
          anchorTranslation = 0
        }
      }
  }

  /// One drawing surface for 41 ticks. Not because 41 views would be slow, but
  /// because the tick offset and the end fade then share a single coordinate
  /// space — the same reason the waveform is a `Canvas`.
  private var ticks: some View {
    Canvas { context, size in
      let offset = size.width / 2 - CGFloat(value) * Self.stripWidth
      for index in 0..<Self.tickCount {
        let centreX = offset + CGFloat(index) * Self.tickPitch
        guard centreX > -Self.tickWidth, centreX < size.width + Self.tickWidth else { continue }

        let isMajor = index % 5 == 0
        let height = isMajor ? Self.majorTickHeight : Self.minorTickHeight
        let rect = CGRect(
          x: centreX - Self.tickWidth / 2,
          y: (size.height - height) / 2,
          width: Self.tickWidth,
          height: height
        )
        context.fill(
          Path(roundedRect: rect, cornerRadius: Self.tickWidth / 2),
          with: .style(isMajor ? DesignTokens.Palette.tickMajor : DesignTokens.Palette.tickMinor)
        )
      }
    }
  }

  private var endFade: some View {
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
  }

  private var marker: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Self.markerWidth / 2, style: .continuous)
        .fill(DesignTokens.Palette.accent)
        .frame(width: Self.markerWidth, height: Self.markerHeight)
        .shadow(color: DesignTokens.Palette.accent.opacity(0.55), radius: 3)

      Circle()
        .fill(DesignTokens.Palette.accent)
        .frame(width: Self.markerDotDiameter, height: Self.markerDotDiameter)
        .shadow(color: DesignTokens.Palette.accent.opacity(0.5), radius: 3, y: 2)
        .offset(y: Self.markerDotCentreY - Self.trackHeight / 2)
    }
    // The marker is the reading, not a control; the scale under it is what
    // moves, and VoiceOver already has the value from the dial itself.
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }

  private var drag: some Gesture {
    DragGesture(minimumDistance: 0)
      .updating($isDragging) { _, dragging, _ in dragging = true }
      .onChanged { gesture in
        let anchor = anchorValue ?? value
        if anchorValue == nil {
          anchorValue = anchor
          anchorTranslation = 0
        }

        let resolved = DialGesture.value(
          from: anchor,
          translation: gesture.translation.width - anchorTranslation,
          trackWidth: Self.trackWidth
        )

        // Pinned against an end: move the anchor up to the finger so the next
        // frame measures from here. Without this the value would owe the whole
        // overshoot back before it started falling again.
        if resolved <= 0 || resolved >= 1 {
          anchorValue = resolved
          anchorTranslation = gesture.translation.width
        }

        value = resolved
      }
  }

  /// Snapped to the 41 stops rather than added to, so repeated VoiceOver swipes
  /// cannot drift off the tick marks they are supposed to land on.
  private func stepped(by steps: Double) -> Double {
    let index = (value / Self.step).rounded() + steps
    return min(max(index * Self.step, 0), 1)
  }

  private var accessibilityValue: String {
    "\(Int((value * 100).rounded()))%, \(Tone.name(for: value))"
  }
}

/// What the dial's value is called. The bands are `docs/design/README.md`'s
/// table, which #44 settled as authoritative over the prototype's conflicting
/// thresholds; every edge is a strict `<` on the upper bound, so a boundary
/// value belongs to the band above it.
enum Tone {

  static func name(for value: Double) -> String {
    switch value {
    case ..<0.06: "Dry"
    case ..<0.32: "Room"
    case ..<0.60: "Warm"
    case ..<0.85: "Studio"
    default: "Hall"
    }
  }
}

/// The drag arithmetic, lifted out of the view so the direction, the clamp and
/// the degenerate cases are testable without a simulator (`PRINCIPLES.md` #3 at
/// component scale).
///
/// Pure, and with no memory of previous calls: coming back from a clamped end is
/// the caller's business, which it handles by re-anchoring on the clamped value.
enum DialGesture {

  /// - Parameters:
  ///   - startValue: the value this leg of the gesture is measured from.
  ///   - translation: horizontal drag, SwiftUI's sense — negative is leftward.
  ///   - trackWidth: the visible track. A full sweep of it covers the range.
  /// - Returns: the new value, clamped to 0…1; `startValue` unchanged if the
  ///   track has no width to divide by.
  static func value(
    from startValue: Double,
    translation: CGFloat,
    trackWidth: CGFloat
  ) -> Double {
    guard trackWidth > 0 else { return startValue }
    // Drag left raises the value, matching the scale scrolling left as it climbs.
    let delta = Double(-translation / trackWidth)
    return min(max(startValue + delta, 0), 1)
  }
}

// MARK: - Previews

/// The five tone bands and both ends of the range. The first dial is live, so
/// the gesture — including what happens when a drag runs past an end — can be
/// checked in the canvas; the rest are fixed so the bands can be read together.
private struct EnhanceDialGallery: View {

  @State private var live: Double = 0.5

  private let samples: [(String, Double)] = [
    ("0.00 — floor", 0.0),
    ("0.03 — Dry", 0.03),
    ("0.20 — Room", 0.20),
    ("0.50 — Warm (default)", 0.50),
    ("0.70 — Studio", 0.70),
    ("0.95 — Hall", 0.95),
    ("1.00 — ceiling", 1.0),
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: DesignTokens.Spacing.block) {
        VStack(spacing: DesignTokens.Spacing.hairline) {
          Text("live — drag me")
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Palette.textTertiary)
          EnhanceDial(value: $live)
        }

        ForEach(samples, id: \.0) { caption, sample in
          VStack(spacing: DesignTokens.Spacing.hairline) {
            Text(caption)
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Palette.textTertiary)
            EnhanceDial(value: .constant(sample))
          }
        }
      }
      .padding(DesignTokens.Spacing.margin)
    }
    .background(DesignTokens.Palette.pageBackground)
  }
}

#Preview("Enhance — light") { EnhanceDialGallery().preferredColorScheme(.light) }
#Preview("Enhance — dark") { EnhanceDialGallery().preferredColorScheme(.dark) }
