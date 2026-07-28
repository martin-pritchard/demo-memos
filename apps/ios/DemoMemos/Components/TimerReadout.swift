import SwiftUI

/// The Take screen's 56pt elapsed-time display: `MM:SS` in full contrast with
/// `.CS` hundredths a shade back, greyed wholesale until capture starts.
///
/// The whole readout is tabular, so a digit changing never reflows the line —
/// which is the point of a hundredths field updating 100 times a second.
///
/// State in, events out: the caller owns the clock. This view formats one value.
struct TimerReadout: View {

  let elapsed: TimeInterval

  /// `false` before capture starts, which greys the whole readout to
  /// `text4` — the handoff's resting state for `ready`.
  var isActive: Bool = true

  private var parts: TimerParts { TimerParts(elapsed: elapsed) }

  var body: some View {
    // `Spacing.hairline` is the handoff's 2pt gap between the digits and the
    // hundredths.
    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.hairline) {
      Text(parts.major)
        .foregroundStyle(isActive ? AnyShapeStyle(DesignTokens.Palette.text) : quaternary)
      Text(".\(parts.hundredths)")
        .foregroundStyle(isActive ? AnyShapeStyle(DesignTokens.Palette.textTertiary) : quaternary)
    }
    .font(DesignTokens.Typography.timer)
    // The timer is a display numeral rather than text — it holds 56pt so the
    // Take screen's fixed content block cannot be pushed apart by Dynamic Type
    // (`DesignTokens.Typography.timer` documents the scaling opt-in for a call
    // site that wants it).
    .accessibilityElement(children: .combine)
    // Minutes and seconds only. The hundredths change a hundred times a second,
    // so announcing them would leave VoiceOver reciting a field that is already
    // stale by the time the sentence ends.
    .accessibilityLabel(Text(parts.major))
  }

  private var quaternary: AnyShapeStyle {
    AnyShapeStyle(DesignTokens.Palette.textQuaternary)
  }
}

/// The two halves of the readout, resolved from an elapsed time.
///
/// Two rules worth stating because they are choices, not consequences:
///
/// - **Minutes never roll into hours.** An hour reads `60:00`. A demo is a song
///   idea; a take that long is a runaway recording, and showing it as `1:00:00`
///   would widen the field for a case that should never arrive.
/// - **Rounded to the nearest centisecond**, not truncated. Truncation is the
///   more common stopwatch behaviour and is what the prototype does, but it
///   turns ordinary binary floating-point error into a visibly wrong final
///   digit. The cost of rounding is 1/100 s at the boundary.
struct TimerParts: Equatable {

  /// `MM:SS`, each field zero-padded to at least two digits.
  let major: String

  /// `CS`, zero-padded to two digits, with no leading dot — the separator is
  /// the view's, so the two halves can carry different colours.
  let hundredths: String

  init(elapsed: TimeInterval) {
    let total = max(0, Int((elapsed * 100).rounded()))
    let minutes = total / 6000
    let seconds = (total % 6000) / 100

    major = "\(Self.padded(minutes)):\(Self.padded(seconds))"
    hundredths = Self.padded(total % 100)
  }

  private static func padded(_ value: Int) -> String {
    value < 10 ? "0\(value)" : "\(value)"
  }
}

// MARK: - Previews

private struct TimerGallery: View {

  private let samples: [(String, TimeInterval, Bool)] = [
    ("ready — greyed", 0, false),
    ("zero", 0, true),
    ("mid take", 61.5, true),
    ("padding", 63.07, true),
    ("just under an hour", 3599.99, true),
    ("an hour", 3600, true),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.block) {
        ForEach(samples, id: \.0) { name, elapsed, isActive in
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
            Text(name)
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Palette.textTertiary)
            TimerReadout(elapsed: elapsed, isActive: isActive)
          }
        }
      }
      .padding(DesignTokens.Spacing.margin)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(DesignTokens.Palette.pageBackground)
  }
}

#Preview("Timer — light") { TimerGallery().preferredColorScheme(.light) }
#Preview("Timer — dark") { TimerGallery().preferredColorScheme(.dark) }
