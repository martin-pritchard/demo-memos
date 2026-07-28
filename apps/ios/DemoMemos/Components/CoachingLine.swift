import SwiftUI

/// The one line of input coaching under the Take screen's timer, during the
/// record flow only.
///
/// The slot is **reserved, never collapsed**: `.clear` renders at zero opacity
/// rather than disappearing, so advice arriving mid-take cannot shove the
/// transport tray down the screen. That is the whole reason this is a type with
/// a height rather than a conditional `Text` at the call site.
///
/// Timing belongs to the caller — including the handoff's 900ms hold past a
/// peak. This view knows only which level it is showing.
struct CoachingLine: View {

  /// The handoff's reserved 24pt slot. A minimum rather than a fixed height so
  /// the line can still grow under Dynamic Type; what matters is that it never
  /// shrinks below the reserved space.
  static let slotHeight: CGFloat = 24

  /// The gap between the warning glyph and its text, from `demo-scene.jsx`.
  private static let glyphGap: CGFloat = 7

  let level: CoachingLevel

  var body: some View {
    HStack(spacing: Self.glyphGap) {
      if level.isWarning {
        Image(systemName: "exclamationmark.triangle")
      }
      Text(level.message)
    }
    .font(DesignTokens.Typography.meta)
    .foregroundStyle(
      level.isWarning
        ? AnyShapeStyle(DesignTokens.Palette.destructive)
        : AnyShapeStyle(DesignTokens.Palette.textSecondary)
    )
    .opacity(level == .clear ? 0 : 1)
    .frame(minHeight: Self.slotHeight)
    .animation(.easeInOut(duration: 0.25), value: level)
    .accessibilityHidden(level == .clear)
  }
}

/// What the live meter has to say about the input, if anything.
///
/// `clear` is a real case rather than an optional: the line is always present,
/// and "nothing to say" is one of the three things it can be showing.
enum CoachingLevel: Equatable, CaseIterable {
  case clear
  case low
  case hot

  var message: String {
    switch self {
    case .clear: ""
    case .low: "Move a little closer"
    case .hot: "A little hot — ease back"
    }
  }

  /// `hot` is the only level drawn in red with a glyph — it is the only one the
  /// user loses a take by ignoring.
  var isWarning: Bool { self == .hot }
}

// MARK: - Previews

private struct CoachingGallery: View {

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.block) {
        ForEach(CoachingLevel.allCases, id: \.self) { level in
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
            Text(String(describing: level))
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Palette.textTertiary)
            // A ruled box so the reserved slot is visible even when the line
            // itself is at zero opacity.
            CoachingLine(level: level)
              .frame(maxWidth: .infinity, alignment: .leading)
              .overlay(
                Rectangle()
                  .stroke(DesignTokens.Palette.separator, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
              )
          }
        }
      }
      .padding(DesignTokens.Spacing.margin)
    }
    .background(DesignTokens.Palette.pageBackground)
  }
}

#Preview("Coaching — light") { CoachingGallery().preferredColorScheme(.light) }
#Preview("Coaching — dark") { CoachingGallery().preferredColorScheme(.dark) }
