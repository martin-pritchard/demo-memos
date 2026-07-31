import SwiftUI

/// First launch, once: what the app is, in three lines and a button.
///
/// The iOS "What's New" pattern — one page, no pagination, no skip, no back,
/// which is why there is no `TabView` and no dismiss control here. The screen
/// still reports Continue and nothing more: the `hasOnboarded` flag that decides
/// whether it appears at all is written by `AppRouter` at the composition root
/// (#60), so this view neither reads nor writes it.
///
/// The only screen in the bundle with no dark-mode render — the handoff's own
/// "try next" note asks for one. It has a dark preview below because every token
/// it uses is semantic, so the appearance follows the system either way; what is
/// undesigned is whether that is what the designer wanted, not whether it works.
struct OnboardFeatures: View {

  var onContinue: () -> Void = {}

  var body: some View {
    VStack(spacing: DesignTokens.Spacing.group) {
      Spacer()
      title
      features
      Spacer()
    }
    .padding(.horizontal, DesignTokens.Spacing.margin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DesignTokens.Palette.pageBackground.ignoresSafeArea())
    .safeAreaInset(edge: .bottom) { continueButton }
  }

  /// "Welcome to" over "Demo Memos" in the accent. Two `Text`s in a tight stack
  /// rather than one with a newline, so only the second line takes the colour.
  private var title: some View {
    VStack(spacing: 0) {
      Text("Welcome to")
        .foregroundStyle(DesignTokens.Palette.text)
      Text("Demo Memos")
        // The accent as text takes the deep variant, which is what keeps it
        // legible on the light page.
        .foregroundStyle(DesignTokens.Palette.accentText)
    }
    .font(DesignTokens.Typography.onboardingTitle)
    .multilineTextAlignment(.center)
    .accessibilityElement(children: .combine)
  }

  private var features: some View {
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
        message: "Send takes straight to Messages, Mail or Files with the native share sheet."
      )
    }
  }

  /// Full width, accent-filled — `DesignTokens.swift` maps the handoff's accent
  /// fill and its `0 6px 18px` amber shadow onto iOS 26's prominent glass
  /// button, which supplies both.
  private var continueButton: some View {
    Button(action: onContinue) {
      // The width goes on the *label*: put on the button it stretches the frame
      // and leaves the capsule its natural size in the middle of it.
      Text("Continue").frame(maxWidth: .infinity)
    }
    .buttonStyle(.glassProminent)
    .tint(DesignTokens.Palette.accent)
    .controlSize(.large)
    .padding(.horizontal, DesignTokens.Spacing.margin)
    .padding(.bottom, DesignTokens.Spacing.label)
  }
}

// MARK: - Previews

#Preview("Onboarding") { OnboardFeatures() }
#Preview("Onboarding — dark") { OnboardFeatures().preferredColorScheme(.dark) }
#Preview("Onboarding — accessibility size") {
  OnboardFeatures().dynamicTypeSize(.accessibility2)
}
