import SwiftUI

/// One of onboarding's three feature rows: an accent glyph in a fixed column,
/// then a title over a line of body copy.
///
/// The fixed icon column is why this is a type rather than a `Label` — the three
/// rows must align down the page whatever each glyph's natural width is, and
/// `Label` sizes its icon to the symbol.
struct FeatureRow: View {

  let symbol: String
  let title: String

  /// Named `message` rather than `body`, which `View` has already claimed.
  let message: String

  /// The handoff's 34pt icon column, scaled with the title it sits beside.
  /// Fixed *relative to the other rows*, which is what the alignment needs —
  /// holding it at 34pt while the text tripled would strand the glyphs.
  @ScaledMetric(relativeTo: .callout) private var column: CGFloat = 34

  var body: some View {
    HStack(alignment: .top, spacing: DesignTokens.Spacing.icon) {
      Image(systemName: symbol)
        .font(.system(size: column * 0.74))
        .foregroundStyle(DesignTokens.Palette.accent)
        .frame(width: column)

      VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
        Text(title)
          .font(DesignTokens.Typography.featureTitle)
          .foregroundStyle(DesignTokens.Palette.text)
        Text(message)
          .font(DesignTokens.Typography.secondaryBody)
          .foregroundStyle(DesignTokens.Palette.textSecondary)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Previews

/// The three rows the onboarding screen ships, copy and symbols from
/// `docs/design/README.md` § Onboarding.
private struct FeatureRowGallery: View {

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.block) {
        FeatureRow(
          symbol: "mic.fill",
          title: "Voice Memos, but for demos",
          message:
            "Open it and go — the same one-tap simplicity you know, made for catching musical ideas."
        )
        FeatureRow(
          symbol: "wand.and.stars",
          title: "One Enhance dial",
          message: "A single slider warms and widens your whole sound. No menus, no mixing."
        )
        FeatureRow(
          symbol: "square.and.arrow.up",
          title: "Share anywhere",
          message:
            "Send takes straight to Messages, Mail or Files with the native share sheet."
        )
      }
      .padding(DesignTokens.Spacing.margin)
    }
    .background(DesignTokens.Palette.pageBackground)
  }
}

#Preview("Feature row — light") { FeatureRowGallery().preferredColorScheme(.light) }
#Preview("Feature row — dark") { FeatureRowGallery().preferredColorScheme(.dark) }
