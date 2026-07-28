import SwiftUI

/// One take in the Demos list: name over meta on the left, duration on the
/// right.
///
/// **Content only.** The card, the inset dividers, the 66pt minimum height and
/// the swipe actions all come from `List { }.listStyle(.insetGrouped)` and
/// `.swipeActions(edge: .trailing)` at the call site — this draws what goes
/// inside a row, not the row itself. `DesignTokens.swift` records that mapping.
///
/// Takes formatted strings rather than a `Demo` and a `Date`: there is no domain
/// model yet, and inventing one inside a component would be the persistence
/// decision made in passing that the build rules exist to prevent.
struct DemoRow: View {

  let name: String

  /// Already formatted — "Today · 3:14 PM".
  let meta: String

  /// Already formatted — "0:37".
  let duration: String

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
        Text(name)
          .font(DesignTokens.Typography.rowTitle)
          .foregroundStyle(DesignTokens.Palette.text)
        Text(meta)
          .font(DesignTokens.Typography.meta)
          .foregroundStyle(DesignTokens.Palette.textSecondary)
      }
      .lineLimit(1)

      Spacer(minLength: DesignTokens.Spacing.label)

      Text(duration)
        .font(DesignTokens.Typography.duration)
        .foregroundStyle(DesignTokens.Palette.textTertiary)
        // A long name truncates; the duration is never the thing that gives
        // way, and never shrinks to fit.
        .fixedSize(horizontal: true, vertical: false)
    }
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Previews

/// Seed content is the handoff's own sample list (`docs/design/README.md`
/// § Demos), plus the two cases it does not draw: a name long enough to
/// truncate, and a take over ten minutes.
private struct DemoRowGallery: View {

  private let rows: [(name: String, meta: String, duration: String)] = [
    ("New Demo 3", "Today · 3:14 PM", "0:37"),
    ("Chorus — fast", "Today · 11:02 AM", "0:21"),
    ("Bridge hum", "Yesterday", "1:12"),
    ("Verse idea 2", "Monday", "0:48"),
    ("Riff in D", "Sunday", "0:15"),
    ("A working title far too long to fit on one line", "Today · 9:41 AM", "12:04"),
  ]

  var body: some View {
    List {
      ForEach(rows, id: \.name) { row in
        DemoRow(name: row.name, meta: row.meta, duration: row.duration)
          .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {}
            Button("Share", systemImage: "square.and.arrow.up") {}
              .tint(DesignTokens.Palette.share)
          }
      }
    }
    .listStyle(.insetGrouped)
  }
}

#Preview("Demo row — light") { DemoRowGallery().preferredColorScheme(.light) }
#Preview("Demo row — dark") { DemoRowGallery().preferredColorScheme(.dark) }
