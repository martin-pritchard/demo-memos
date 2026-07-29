import Core
import SwiftUI

/// The Take screen's one reserved message slot, under the timer.
///
/// **One slot, one channel** (`#16`, FINAL). Both kinds of message the screen
/// has live here, and the caller resolves which one wins before it gets here —
/// see `TakeSlot.resolve(notice:coaching:)`. The design explored giving notices
/// their own row and their own full-block empty state and dropped both: one slot
/// "keeps the screen identical in every state — nothing above it moves, nothing
/// below it jumps".
///
/// The slot is **reserved, never collapsed**: an empty slot renders at zero
/// opacity rather than disappearing, so a message arriving mid-take cannot shove
/// the transport tray down the screen. That is the whole reason this is a type
/// with a height rather than a conditional `Text` at the call site.
///
/// The two kinds differ in exactly two ways, and both are drawn here:
/// - **Coaching** cross-fades; a **notice** appears instantly and persists.
/// - Only a **notice** may carry an action.
///
/// Timing belongs to the caller — including the handoff's 900ms hold past a
/// peak. This view knows only what it is showing.
struct InlineNotice: View {

  /// The handoff's reserved 24pt slot. A minimum rather than a fixed height so
  /// the line can still grow under Dynamic Type; what matters is that it never
  /// shrinks below the reserved space.
  static let slotHeight: CGFloat = 24

  /// The gap between the warning glyph and its text, from `demo-scene.jsx`.
  private static let glyphGap: CGFloat = 7

  let slot: TakeSlot

  /// Tapped when a notice carries one. Never called for coaching.
  var onAction: (TakeNoticeAction) -> Void = { _ in }

  var body: some View {
    Group {
      switch slot {
      case .empty:
        coaching(.clear)
      case .coaching(let level):
        coaching(level)
      case .notice(let notice):
        line(notice)
      }
    }
    .frame(minHeight: Self.slotHeight)
    // Coaching cross-fades; a notice is not animated in, because it persists
    // and is sometimes actionable — it should not arrive like a hint.
    .animation(.easeInOut(duration: 0.25), value: isCoaching)
  }

  private var isCoaching: Bool {
    if case .notice = slot { return false }
    return true
  }

  @ViewBuilder private func coaching(_ level: CoachingLevel) -> some View {
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
    .accessibilityHidden(level == .clear)
  }

  /// A notice: line, optional second line, optional tinted capsule. Never red —
  /// a mic state is a state, not an error (`#15`).
  @ViewBuilder private func line(_ notice: TakeNotice) -> some View {
    VStack(spacing: DesignTokens.Spacing.hairline) {
      Text(notice.line)
        .font(DesignTokens.Typography.meta)
        .foregroundStyle(DesignTokens.Palette.text)

      if let sub = notice.sub {
        Text(sub)
          .font(DesignTokens.Typography.meta)
          .foregroundStyle(DesignTokens.Palette.textSecondary)
      }

      if let action = notice.action {
        Button(action.label) { onAction(action) }
          .font(DesignTokens.Typography.meta.weight(.semibold))
          .foregroundStyle(DesignTokens.Palette.accentText)
          .padding(.horizontal, DesignTokens.Spacing.label)
          .padding(.vertical, DesignTokens.Spacing.hairline)
          .background(DesignTokens.Palette.accent.opacity(0.14), in: .capsule)
          .buttonStyle(.plain)
          .padding(.top, DesignTokens.Spacing.hairline)
      }
    }
    .multilineTextAlignment(.center)
  }
}

extension TakeNoticeAction {
  /// `#15g`'s route out, as the capsule says it.
  var label: String {
    switch self {
    case .openSettings: "Open Settings"
    case .tryAgain: "Try Again"
    }
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

private struct InlineNoticeGallery: View {

  /// Every state the slot can be in: the three coaching levels, and a notice
  /// with an action. `.empty` is drawn too — an invisible line inside a visible
  /// box is exactly the thing the reserved slot exists to guarantee.
  private var slots: [(name: String, slot: TakeSlot)] {
    var slots: [(String, TakeSlot)] = [("empty", .empty)]
    slots += CoachingLevel.allCases.map { ("coaching · \($0)", .coaching($0)) }
    if let denied = TakeNotice(.permissionDenied) {
      slots.append(("notice · mic denied", .notice(denied)))
    }
    return slots
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.block) {
        ForEach(slots, id: \.name) { entry in
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
            Text(entry.name)
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Palette.textTertiary)
            // A ruled box so the reserved slot is visible even when the line
            // itself is at zero opacity.
            InlineNotice(slot: entry.slot)
              .frame(maxWidth: .infinity)
              .overlay(
                Rectangle()
                  .stroke(
                    DesignTokens.Palette.separator,
                    style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
              )
          }
        }
      }
      .padding(DesignTokens.Spacing.margin)
    }
    .background(DesignTokens.Palette.pageBackground)
  }
}

#Preview("Inline notice — light") { InlineNoticeGallery().preferredColorScheme(.light) }
#Preview("Inline notice — dark") { InlineNoticeGallery().preferredColorScheme(.dark) }
