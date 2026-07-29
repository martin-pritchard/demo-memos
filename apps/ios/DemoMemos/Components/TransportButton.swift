import SwiftUI

/// One of the two 66pt transport buttons at the bottom of the Take screen.
///
/// The record flow keeps a fixed two-button layout in every state — Play on the
/// left, the main action on the right — so the tray never jumps between one and
/// two buttons. That is why a single type covers all six roles rather than a
/// `RecordButton` and a `PlayButton`: they share the frame, the label and the
/// disabled treatment, and the screen always places them as a pair.
///
/// State in, events out. The button draws the role it is handed and reports the
/// tap; it owns no timer and no mode. In particular the **count-in beat
/// schedule belongs to the caller** — this view renders whatever numeral it is
/// given and animates when that numeral changes.
///
/// Disabled-ness comes from the environment, so the call site writes
/// `.disabled(…)` as it would for any control and VoiceOver reports it as
/// disabled rather than merely dimmed.
struct TransportButton: View {

  /// Both from `docs/design/README.md` § Take. Per-control geometry lives
  /// beside its one consumer rather than in `DesignTokens` (`PRINCIPLES.md` #2,
  /// and the tokens file says so in as many words).
  static let diameter: CGFloat = 66
  static let ringWidth: CGFloat = 4

  /// The opacity a disabled transport button dims to — Play before a take
  /// exists, Resume while playing.
  private static let disabledOpacity: Double = 0.35

  /// The opacity a *blocked* transport button dims to — Record with no
  /// microphone behind it (`#15a`).
  private static let blockedOpacity: Double = 0.45

  let role: TransportRole
  let action: () -> Void

  /// The recorder is out of action — no microphone, or no permission to use it.
  ///
  /// A second, deeper level of disabled than "no take yet", and the design draws
  /// it differently (`#15a`): the amber disc goes grey, the control sits at 45%
  /// rather than 35%, and the label dims too. That last part is the exception to
  /// the rule below, and it is deliberate: a dim label on a grey disc is what
  /// says *the recorder*, not *this take*, is unavailable.
  var isBlocked: Bool = false

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var appearance: TransportAppearance { TransportAppearance(for: role) }

  var body: some View {
    // `spacing: nil` is the handoff's 8pt gap between a transport button and
    // its label — the system default, so it tracks Dynamic Type.
    VStack {
      Button(action: action) {
        ZStack {
          if appearance.hasRing {
            Circle()
              .strokeBorder(DesignTokens.Palette.separator, lineWidth: Self.ringWidth)
          } else {
            // Play and Pause carry a tinted fill instead of a ring.
            Circle()
              .fill(DesignTokens.Palette.accent.opacity(colorScheme == .dark ? 0.20 : 0.14))
          }
          figure
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(appearance.label)
      .accessibilityValue(countInValue)
      // Only the disc dims. The label stays at full contrast — it is still
      // telling you what the button is for, and dimming it twice reads as two
      // levels of disabled.
      .opacity(isBlocked ? Self.blockedOpacity : (isEnabled ? 1 : Self.disabledOpacity))
      .animation(.easeInOut(duration: 0.2), value: isEnabled)
      .animation(.easeInOut(duration: 0.2), value: isBlocked)

      Text(appearance.label)
        .font(DesignTokens.Typography.transportLabel)
        .foregroundStyle(
          isBlocked
            ? AnyShapeStyle(DesignTokens.Palette.textQuaternary)
            : AnyShapeStyle(DesignTokens.Palette.textSecondary)
        )
        // The button already carries this as its accessibility label; left
        // visible to VoiceOver it would be announced a second time.
        .accessibilityHidden(true)
    }
  }

  /// The remaining beat, so a count-in is audible as well as visible.
  private var countInValue: Text {
    if case .countIn(let beat) = role { Text("\(beat)") } else { Text("") }
  }

  @ViewBuilder private var figure: some View {
    switch appearance.figure {
    case .disc(let scale):
      Circle()
        // Grey, not dimmed amber: nothing on a blocked screen should still read
        // as inviting (`#15a`).
        .fill(
          isBlocked
            ? AnyShapeStyle(DesignTokens.Palette.textTertiary)
            : AnyShapeStyle(DesignTokens.Palette.accent)
        )
        .frame(width: Self.diameter * scale, height: Self.diameter * scale)

    case .roundedSquare(let scale, let radius):
      RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(DesignTokens.Palette.accent)
        .frame(width: Self.diameter * scale, height: Self.diameter * scale)

    case .numeral(let numeral):
      Text(numeral)
        .font(DesignTokens.Typography.countIn)
        .foregroundStyle(DesignTokens.Palette.accent)
        // Capped at the default size. The numeral is part of a fixed-diameter
        // control, and `Typography.countIn` is a Dynamic Type style — left to
        // scale, a two-digit beat overruns the ring at the accessibility sizes
        // while the 66pt frame around it stays put.
        .dynamicTypeSize(...DynamicTypeSize.large)
        // A new beat is a new view, so the transition runs per beat: the
        // handoff's `scale(1.25) → 1` with a fade, one second each.
        .id(numeral)
        .transition(.scale(scale: 1.25).combined(with: .opacity))
        .animation(reduceMotion ? nil : .easeOut(duration: 1), value: numeral)
        .accessibilityHidden(true)

    case .symbol(let name, let scale):
      Image(systemName: name)
        .font(.system(size: Self.diameter * scale))
        // `accentText`, not `accent`: a glyph sitting on an `accent @ 0.14`
        // fill is exactly the case the deep variant exists for — the bright
        // amber loses its contrast on a light page.
        .foregroundStyle(DesignTokens.Palette.accentText)
    }
  }
}

/// What the right-hand transport button is currently for, plus the two roles the
/// left-hand button alternates between.
///
/// `countIn` carries the beat still to be shown. It is a phase of recording, not
/// its own action, which is why it keeps the "Record" label.
enum TransportRole: Equatable {
  case record
  case countIn(Int)
  case stop
  case resume
  case play
  case pause
}

/// The pure mapping from a role to what gets drawn — the view body is a
/// projection over this, which is what makes the six states testable without a
/// simulator (`docs/PRINCIPLES.md` #3 at component scale).
///
/// Scales are fractions of ``TransportButton/diameter``; all of them, and the
/// 9pt stop-square radius, come from `docs/design/README.md` § Take.
struct TransportAppearance: Equatable {

  enum Figure: Equatable {
    case disc(scale: CGFloat)
    case roundedSquare(scale: CGFloat, radius: CGFloat)
    case numeral(String)
    case symbol(name: String, scale: CGFloat)
  }

  let figure: Figure
  let hasRing: Bool
  let label: String

  init(for role: TransportRole) {
    switch role {
    case .record:
      figure = .disc(scale: 0.78)
      hasRing = true
      label = "Record"

    case .countIn(let beat):
      figure = .numeral("\(beat)")
      hasRing = true
      label = "Record"

    case .stop:
      figure = .roundedSquare(scale: 0.40, radius: 9)
      hasRing = true
      label = "Stop"

    case .resume:
      figure = .disc(scale: 0.40)
      hasRing = true
      label = "Resume"

    case .play:
      figure = .symbol(name: "play.fill", scale: 0.42)
      hasRing = false
      label = "Play"

    case .pause:
      figure = .symbol(name: "pause.fill", scale: 0.42)
      hasRing = false
      label = "Pause"
    }
  }
}

// MARK: - Previews

/// Every transport state in `docs/design/screen-states.md` §4.1–4.5, laid out as
/// the pairs the tray actually shows.
private struct TransportGallery: View {

  private struct Pair: Identifiable {
    let id: String
    let left: TransportRole
    let leftEnabled: Bool
    let right: TransportRole
    let rightEnabled: Bool
  }

  private let pairs: [Pair] = [
    .init(id: "4.1 ready", left: .play, leftEnabled: false, right: .record, rightEnabled: true),
    .init(
      id: "4.2 countin", left: .play, leftEnabled: false, right: .countIn(3), rightEnabled: true),
    .init(id: "4.3 recording", left: .play, leftEnabled: false, right: .stop, rightEnabled: true),
    .init(id: "4.4 stopped", left: .play, leftEnabled: true, right: .resume, rightEnabled: true),
    .init(id: "4.5 playing", left: .pause, leftEnabled: true, right: .resume, rightEnabled: false),
  ]

  var body: some View {
    ScrollView {
      VStack(spacing: DesignTokens.Spacing.block) {
        ForEach(pairs) { pair in
          VStack {
            Text(pair.id)
              .font(DesignTokens.Typography.caption)
              .foregroundStyle(DesignTokens.Palette.textTertiary)
            HStack(spacing: DesignTokens.Spacing.group) {
              TransportButton(role: pair.left) {}.disabled(!pair.leftEnabled)
              TransportButton(role: pair.right) {}.disabled(!pair.rightEnabled)
            }
          }
        }

        VStack {
          Text("count-in beats")
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Palette.textTertiary)
          HStack(spacing: DesignTokens.Spacing.group) {
            ForEach([4, 3, 2, 1], id: \.self) { beat in
              TransportButton(role: .countIn(beat)) {}
            }
          }
        }
      }
      .padding(DesignTokens.Spacing.margin)
    }
    .background(DesignTokens.Palette.pageBackground)
  }
}

#Preview("Transport — light") { TransportGallery().preferredColorScheme(.light) }
#Preview("Transport — dark") { TransportGallery().preferredColorScheme(.dark) }
