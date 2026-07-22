import SwiftUI

/// 5a — the one-time first-launch intro. The iOS "What's New" pattern: a welcome
/// title, three benefit rows, one Continue. Purely presentational — it shows the
/// pitch and emits `onContinue`; the gate that shows it exactly once lives in
/// `RootView`.
///
/// Standard chrome throughout: semantic type, a `.borderedProminent` button that
/// inherits the orange `AccentColor`. The orange on the title word and the row
/// icons is the design's single deliberate accent, so it draws from `Palette`.
struct OnboardingView: View {
  let onContinue: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Centre the pitch when it fits; scroll it when Dynamic Type makes it tall.
      GeometryReader { proxy in
        ScrollView {
          VStack(spacing: 44) {
            title
            features
          }
          .padding(.horizontal, 32)
          .frame(maxWidth: .infinity, minHeight: proxy.size.height)
        }
      }
      continueButton
    }
    .background(Palette.pageBackground.ignoresSafeArea())
  }

  private var title: some View {
    VStack(spacing: 4) {
      Text("Welcome to")
      Text("Demo Memos")
        .foregroundStyle(Palette.accentText)
    }
    .font(.largeTitle.bold())
    .multilineTextAlignment(.center)
  }

  private var features: some View {
    VStack(alignment: .leading, spacing: 30) {
      feature(
        icon: "mic.fill",
        title: "Voice Memos, but for demos",
        detail:
          "Open it and go — the same one-tap simplicity you know, made for catching musical ideas."
      )
      feature(
        icon: "wand.and.stars",
        title: "One Enhance dial",
        detail: "A single slider warms and widens your whole sound. No menus, no mixing."
      )
      feature(
        icon: "square.and.arrow.up",
        title: "Share anywhere",
        detail: "Send takes straight to Messages, Mail or Files with the native share sheet."
      )
    }
  }

  private func feature(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 18) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(Palette.accentText)
        .frame(width: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.headline)
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var continueButton: some View {
    Button(action: onContinue) {
      Text("Continue")
        .font(.headline)
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    // The design's primary CTA is the bright accent in both appearances — the
    // same deliberate orange as the New Demo pill, so it draws from Palette
    // rather than the deeper light-mode AccentColor.
    .tint(Palette.accent)
    .padding(.horizontal, 24)
    .padding(.top, 18)
    .padding(.bottom, 44)
  }
}

#Preview("5a · onboarding") {
  OnboardingView(onContinue: {})
}

#Preview("5a · onboarding (dark)") {
  OnboardingView(onContinue: {})
    .preferredColorScheme(.dark)
}
