import SwiftUI
import UIKit

/// The design handoff's tokens (`docs/design/README.md`), resolved against
/// SwiftUI's semantic API.
///
/// **The rule applied throughout.** Where the handoff names a role iOS already
/// names, the token *is* the system value — `.primary`, `.secondary`,
/// `Color.accentColor`, `.title2`. That is not rounding for convenience: it is
/// what keeps Dark Mode, Increase Contrast, Reduce Transparency and Dynamic
/// Type working without a second code path, and the handoff asks for it in so
/// many words ("prefer the semantic system colours — they give you dark mode
/// and accessibility contrast for free"). A literal survives only where SwiftUI
/// has no equivalent; every one is listed under "Literals kept" below with the
/// reason, and carries a `Literal —` comment at its definition.
///
/// **The two accent hexes are not in this file.** `#FF9F0A` and `#FF7A00` live
/// in `Assets.xcassets` (`AccentColor`, `AccentDeep`), which is where iOS wants
/// an app's accent: the catalog feeds `Color.accentColor`, the global control
/// tint, and the light/dark variant, none of which a Swift constant can do.
///
/// **Tokens deliberately absent.** Most of the handoff's spacing, radii and
/// shadows describe standard iOS chrome; the container supplies them, so
/// hard-coding them would only fight the platform:
///
/// | Handoff | Comes free from |
/// |---|---|
/// | list header `64 / 20 / 12`, title 34/700 | `.navigationTitle` + `.navigationBarTitleDisplayMode(.large)` |
/// | list card radius `22`, 16pt side inset, 0.5pt inset dividers, row min-height `66` | `List { }.listStyle(.insetGrouped)` |
/// | list bottom padding `120`, capsule `16` above a `40` inset | `.safeAreaInset(edge: .bottom)` |
/// | transport tray bottom `42` | bottom safe area (34) + `.padding(.bottom, 8)` |
/// | swipe row: 76pt actions, −152 open, −64 threshold, `transform .2s` | `.swipeActions(edge: .trailing)` |
/// | delete action sheet: radius `14`, 8pt gap, scrim, `.32s` curve | `.confirmationDialog` with `role: .destructive` |
/// | share sheet: radius `40`, inset 8, app row, actions | `ShareLink` |
/// | sheet radius `16`, `translateY(115%) → 0` at `.34s cubic-bezier(.32,.72,0,1)` | `.sheet` (that curve *is* the system sheet curve) |
/// | play button `accent @ 0.14` light / `0.20` dark | `.buttonStyle(.bordered)` + `.tint(.accentColor)` |
/// | New Demo capsule: accent @ 0.9 over `blur(24px) saturate(1.6)`, hairline, shadow | `.glassEffect(.regular.tint(.accentColor))` |
/// | Continue button: accent fill, `0 6px 18px rgba(255,159,10,0.34)` | `.buttonStyle(.glassProminent)` |
/// | sheet glass `blur(34px) saturate(180%)` | `Palette.glass` (`.regularMaterial`) |
/// | pills and discs, radius `999` | `Capsule()` / `Circle()` |
/// | 8pt gaps (label under a transport button, sheet card gap) | default `VStack` spacing (`spacing: nil`) |
/// | 16pt side margin on the list | `.padding()` (16 on iOS) |
/// | letter-spacing `−0.6 … +0.3` | SF's own optical tracking at each size; the handoff says approximate |
///
/// **Literals kept** — 12 values, each because SwiftUI offers nothing to map to:
///
/// - `Typography.timer` / `Literal.timerFontSize` (56) — no Dynamic Type style
///   reaches 56pt; `.largeTitle` tops out at 34. A display numeral, not text.
/// - `Palette.warm(_:opacity:)` — the OKLCH warmth ramp. SwiftUI has no OKLCH
///   initialiser, and the ramp's whole job is holding perceptual lightness
///   steady while chroma climbs, which HSB cannot do.
/// - `Spacing.hairline` (2) — sub-default gap; the system minimum is 8.
/// - `Spacing.label` (12) — Enhance label above its track.
/// - `Spacing.icon` (18) — icon column to text; not a padding role.
/// - `Spacing.margin` (24) — Take screen side margin; wider than `.padding()`'s 16.
/// - `Spacing.block` (30) — meta → waveform → timer; onboarding rows.
/// - `Spacing.group` (44) — between transport buttons; title → feature rows.
/// - `Spacing.contentTop` (90) — Take screen content inset below the header.
/// - `Radius.card` (22) — only for a hand-drawn card; an inset-grouped `List`
///   supplies its own and should be preferred.
/// - `Radius.button` (15) — when a bordered shape is wanted over iOS 26's capsule.
/// - `Radius.tile` (12) — the accent-tinted glyph tile in the share header.
///
/// Per-control geometry the handoff also specifies — 66pt transport buttons,
/// the 300 × 40 Enhance track and its 14pt tick pitch, 5/3 waveform bar
/// geometry, the 4pt playhead — is deliberately *not* here. It has one consumer
/// each, so it belongs beside that view (`docs/PRINCIPLES.md` #2).
enum DesignTokens {

  // MARK: - Colour

  enum Palette {

    // Accent. Both from the asset catalog; see the note above.

    /// `ACCENT` `#FF9F0A`. Record disc, Enhance marker, buttons, links.
    static let accent = Color.accentColor

    /// `ACCENT_DEEP` `#FF7A00` light / `#FF9F0A` dark. The accent as *text or a
    /// glyph*, where the bright amber loses contrast on a light background.
    static let accentText = Color(.accentDeep)

    // Backgrounds.

    /// `pageBg`. Light `#FBFBFD → #F2F2F6`, dark `#1C1C1E → #000`. The two ends
    /// are `secondarySystemGroupedBackground` and `systemGroupedBackground` to
    /// within a shade in light, and exactly in dark.
    static let pageBackground = LinearGradient(
      colors: [Color(.secondarySystemGroupedBackground), Color(.systemGroupedBackground)],
      startPoint: .top,
      endPoint: .bottom
    )

    /// `card`. `#FFFFFF` / `#2C2C2E` — exactly `secondarySystemGroupedBackground`.
    static let card = Color(.secondarySystemGroupedBackground)

    /// The handoff's `backdrop-filter: blur(34px) saturate(180%)` on sheets, and
    /// the dark `card` variant `rgba(118,118,128,0.16)`.
    static let glass: Material = .regularMaterial

    // Foreground hierarchy. The handoff's four text levels are the system's
    // four label levels; `text4` matches `tertiaryLabel` exactly and `text2`
    // matches `secondaryLabel` exactly in dark.

    /// `text`. `#1C1C1E` / `#FFFFFF`.
    static let text = Color.primary
    /// `text2`. `rgba(60,60,67,0.5)` / `rgba(235,235,245,0.6)`.
    static let textSecondary = Color.secondary
    /// `text3`. `rgba(60,60,67,0.4)` / `rgba(235,235,245,0.4)`.
    static let textTertiary = HierarchicalShapeStyle.tertiary
    /// `text4`. `rgba(60,60,67,0.3)` / `rgba(235,235,245,0.3)`. The timer before
    /// capture starts.
    static let textQuaternary = HierarchicalShapeStyle.quaternary

    // Lines and fills.

    /// `divider` and `recBorder` (the transport ring). Both are borders, which
    /// is what `separator` is for. A `List` draws its own — this is for the
    /// ring only.
    static let separator = Color(.separator)

    /// `barOff`, the unplayed waveform. `rgba(120,120,128,0.28)` /
    /// `rgba(235,235,245,0.22)` — the system fill family, and a fill is what
    /// this is.
    static let barOff = Color(.systemFill)

    /// `tickMaj` on the Enhance scale. `rgba(60,60,67,0.32)` / `rgba(235,235,245,0.4)`.
    static let tickMajor = HierarchicalShapeStyle.tertiary
    /// `tickMin`. `rgba(60,60,67,0.15)` / `rgba(235,235,245,0.18)` — near-exactly
    /// `quaternaryLabel`.
    static let tickMinor = HierarchicalShapeStyle.quaternary

    // Status.

    /// Delete (`#FF3B30`) and the clip warning (`#FF453A`). These are `systemRed`'s
    /// own light and dark values, so one token covers both handoff entries.
    static let destructive = Color.red

    /// The swipe row's Share action, `#0A84FF` — `systemBlue`'s dark value.
    static let share = Color.blue

    /// Literal — the handoff's warm waveform ramp, `warmColor(w, α)` in OKLCH.
    /// Kept because SwiftUI has no OKLCH initialiser and the ramp exists to hold
    /// perceptual lightness steady as chroma climbs; an HSB approximation drifts
    /// exactly where the dial is most used. Played bars are
    /// `warm(0.35 + enhance * 0.65)`; unplayed bars use ``barOff``.
    static func warm(_ warmth: Double, opacity: Double = 1) -> Color {
      let lightness = 0.74 - warmth * 0.07
      let chroma = 0.008 + warmth * 0.16
      let hue = (72 - warmth * 10) * .pi / 180
      return oklab(lightness, chroma * cos(hue), chroma * sin(hue), opacity)
    }

    /// OKLab → linear sRGB (Björn Ottosson's matrices). Handed to SwiftUI as
    /// `.sRGBLinear` so no gamma step is needed here.
    private static func oklab(_ l: Double, _ a: Double, _ b: Double, _ opacity: Double) -> Color {
      let lCone = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
      let mCone = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
      let sCone = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
      return Color(
        .sRGBLinear,
        red: min(max(4.0767416621 * lCone - 3.3077115913 * mCone + 0.2309699292 * sCone, 0), 1),
        green: min(max(-1.2684380046 * lCone + 2.6097574011 * mCone - 0.3413193965 * sCone, 0), 1),
        blue: min(max(-0.0041960863 * lCone - 0.7034186147 * mCone + 1.7076147010 * sCone, 0), 1),
        opacity: opacity
      )
    }
  }

  // MARK: - Type

  /// Every role but the timer lands on a built-in text style, so all of it
  /// scales with Dynamic Type for free. The handoff's variable-weight steps
  /// (590, 640, 680, 720) round to the nearest named weight, which it asks for:
  /// "approximate rather than chase exact numerals".
  enum Typography {

    /// List large title "Demos", 34/700. Free from `.navigationTitle`; here for
    /// anywhere the title is drawn by hand.
    static let largeTitle = Font.largeTitle.bold()

    /// Onboarding title, 32/720. `.largeTitle` is 34.
    static let onboardingTitle = Font.largeTitle.bold()

    /// Take title (24/680) and empty-state title (22/700). `.title2` is 22.
    static let screenTitle = Font.title2.bold()

    /// Action-sheet rows, 19/590–680. `.title3` is 20. Free from
    /// `.confirmationDialog`.
    static let sheetAction = Font.title3.weight(.semibold)

    /// Count-in numeral, 28/560, tabular. `.title` is 28 — exact.
    static let countIn = Font.title.weight(.medium).monospacedDigit()

    /// List row name (17/590) and the prominent bar button "Done" (17/640).
    /// `.headline` is 17 semibold — exact, and its semantic role besides.
    static let rowTitle = Font.headline

    /// Sheet row label and plain bar buttons ("Cancel"), 17/400. `.body` is 17.
    static let body = Font.body

    /// Onboarding feature title (16.5/640) and the New Demo capsule label
    /// (16/640). `.callout` is 16.
    static let featureTitle = Font.callout.weight(.semibold)

    /// Feature body and empty-state body, 14.5–15/400. `.subheadline` is 15.
    static let secondaryBody = Font.subheadline

    /// Row meta ("Today · 3:14 PM") and hints, 14.
    static let meta = Font.subheadline

    /// Row duration, 15/400 tabular. `.subheadline` is 15 — exact.
    static let duration = Font.subheadline.monospacedDigit()

    /// "Enhance · {tone}", 14/640.
    static let enhanceLabel = Font.subheadline.weight(.semibold)

    /// Transport button labels, 13/500. `.footnote` is 13 — exact.
    static let transportLabel = Font.footnote.weight(.medium)

    /// "Swipe a demo to share", 12.5. `.caption` is 12.
    static let caption = Font.caption

    /// Literal — the 56/300 tabular timer. Kept because no Dynamic Type style
    /// reaches 56pt (`.largeTitle` is 34) and this is a display numeral, not
    /// text. To let it scale anyway, wrap the call site in
    /// `@ScaledMetric(relativeTo: .largeTitle) private var size = Literal.timerFontSize`
    /// and build the font from `size`.
    static let timer = Font.system(size: Literal.timerFontSize, weight: .light).monospacedDigit()
  }

  // MARK: - Spacing

  /// SwiftUI has no spacing *scale*. What it has is three semantic defaults —
  /// `spacing: nil` on a stack (8), `.padding()` (16) and the safe-area insets —
  /// and the handoff's 8, 16, 40 and 42 all resolve to those (see the table
  /// above). What is left is geometry, so every value here is a literal by
  /// necessity; each doc line says which gap it is.
  enum Spacing {

    /// Literal — 2. Name → meta, timer digits → hundredths. Below the system's
    /// 8pt stack default, which is the smallest thing it offers.
    static let hairline: CGFloat = 2

    /// Literal — 12. Enhance label above its track.
    static let label: CGFloat = 12

    /// Literal — 18. Icon column → text in an onboarding row; share glyph →
    /// "Done" in the Take header. A gap between siblings, not a padding role.
    static let icon: CGFloat = 18

    /// Literal — 24. Take screen side margin. `.padding()` is 16.
    static let margin: CGFloat = 24

    /// Literal — 30. Meta → waveform → timer; between onboarding feature rows.
    static let block: CGFloat = 30

    /// Literal — 44. Between the two transport buttons; onboarding title → rows.
    static let group: CGFloat = 44

    /// Literal — 90. Take screen content top inset, below the 56pt header.
    static let contentTop: CGFloat = 90
  }

  // MARK: - Radius

  /// Sheets, action sheets, the share sheet, pills and discs are all system
  /// shapes and carry their own radii — see the table above. These three are
  /// what is left. On iOS 26, prefer `ConcentricRectangle` for anything nested
  /// inside one of them so the corners stay concentric.
  enum Radius {

    /// Literal — 22. The Demos card, *only* if it is drawn by hand;
    /// `List { }.listStyle(.insetGrouped)` supplies the card and its radius.
    static let card: CGFloat = 22

    /// Literal — 15. The Continue button, where a bordered rectangle is wanted
    /// instead of iOS 26's default capsule.
    static let button: CGFloat = 15

    /// Literal — 12. The accent-tinted glyph tile in the share sheet header.
    static let tile: CGFloat = 12
  }

  // MARK: - Literals

  /// The bare numbers behind the tokens above that needed one. Separated so the
  /// list of "things SwiftUI could not supply" is countable at a glance rather
  /// than inferred from the file.
  enum Literal {

    /// 56pt, the timer. See ``Typography/timer``.
    static let timerFontSize: CGFloat = 56
  }
}

// MARK: - Specimen

/// Renders the mapping so it can be checked against `docs/design/` by eye, in
/// both appearances. No data, no state — the tokens are the whole subject.
private struct TokenSpecimen: View {

  private let swatches: [(String, AnyShapeStyle)] = [
    ("accent", AnyShapeStyle(DesignTokens.Palette.accent)),
    ("accentText", AnyShapeStyle(DesignTokens.Palette.accentText)),
    ("card", AnyShapeStyle(DesignTokens.Palette.card)),
    ("text", AnyShapeStyle(DesignTokens.Palette.text)),
    ("text2", AnyShapeStyle(DesignTokens.Palette.textSecondary)),
    ("text3", AnyShapeStyle(DesignTokens.Palette.textTertiary)),
    ("text4", AnyShapeStyle(DesignTokens.Palette.textQuaternary)),
    ("separator", AnyShapeStyle(DesignTokens.Palette.separator)),
    ("barOff", AnyShapeStyle(DesignTokens.Palette.barOff)),
    ("destructive", AnyShapeStyle(DesignTokens.Palette.destructive)),
    ("share", AnyShapeStyle(DesignTokens.Palette.share)),
    ("glass", AnyShapeStyle(DesignTokens.Palette.glass)),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.block) {
        grid
        ramp
        type
      }
      .padding(DesignTokens.Spacing.margin)
    }
    .background(DesignTokens.Palette.pageBackground)
  }

  private var grid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
      ForEach(swatches, id: \.0) { name, style in
        VStack(spacing: DesignTokens.Spacing.hairline) {
          RoundedRectangle(cornerRadius: DesignTokens.Radius.tile)
            .fill(style)
            .frame(height: 44)
            .overlay(
              RoundedRectangle(cornerRadius: DesignTokens.Radius.tile)
                .stroke(DesignTokens.Palette.separator)
            )
          Text(name).font(DesignTokens.Typography.caption)
        }
      }
    }
  }

  private var ramp: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.hairline) {
      Text("Palette.warm — Enhance 0…1")
        .font(DesignTokens.Typography.enhanceLabel)
        .foregroundStyle(DesignTokens.Palette.accentText)
      HStack(spacing: 3) {
        ForEach(0..<24) { step in
          let enhance = Double(step) / 23
          Capsule().fill(DesignTokens.Palette.warm(0.35 + enhance * 0.65))
        }
      }
      .frame(height: 44)
    }
  }

  private var type: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.label) {
      Text("Demos").font(DesignTokens.Typography.largeTitle)
      Text("New Demo 3").font(DesignTokens.Typography.rowTitle)
      Text("Today · 3:14 PM")
        .font(DesignTokens.Typography.meta)
        .foregroundStyle(DesignTokens.Palette.textSecondary)
      Text("00:37").font(DesignTokens.Typography.timer)
      Text("0:37")
        .font(DesignTokens.Typography.duration)
        .foregroundStyle(DesignTokens.Palette.textTertiary)
      Text("Record").font(DesignTokens.Typography.transportLabel)
      Text("Swipe a demo to share")
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(DesignTokens.Palette.textTertiary)
    }
  }
}

#Preview("Tokens — light") { TokenSpecimen().preferredColorScheme(.light) }
#Preview("Tokens — dark") { TokenSpecimen().preferredColorScheme(.dark) }
