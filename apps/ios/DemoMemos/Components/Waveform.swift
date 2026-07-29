import SwiftUI

/// The take, drawn as bars — one `Canvas`, three modes.
///
/// Every bar, and the marker over them, is a single drawing surface rather than
/// N views because the handoff asks for one in as many words. The bloom behind
/// them is the one thing that is *not* in that surface: `Canvas` clips to its
/// frame, and an aura specified at 208% of the box height has to be able to
/// bleed past it or it stops being an aura and becomes a rectangle. The ticket
/// named that escalation ahead of time — start in-canvas, add a layer only if it
/// visibly differs — and on device it visibly differed.
///
/// **The view owns no time.** There is no `Timer`, no ring buffer and no audio
/// import here: the ~95ms-per-bar roll and the 40ms playhead tick are just
/// successive values of ``bars`` and ``progress``, driven by whatever owns the
/// metering. That is what makes it previewable from fixture arrays and testable
/// without a simulator — every decision it makes is in ``WaveformGeometry``, and
/// the body is a projection over that.
///
/// State in, events out: a scrub reports a new progress through ``onScrub`` and
/// the component never moves its own playhead.
struct Waveform: View {

  /// Bar levels, `0…1`, newest last.
  var bars: [Float]

  /// The playhead, `0…1`. Ignored in ``WaveformMode/resting`` and
  /// ``WaveformMode/live``, where there is nothing to play back.
  var progress: Double = 0

  var mode: WaveformMode = .resting

  /// The Enhance value, `0…1` — drives the warm ramp on the played bars and the
  /// size of the bloom behind them.
  var enhance: Double = 0

  /// Reports the progress a drag lands on. Scrubbing is
  /// ``WaveformMode/scrub`` only.
  var onScrub: (Double) -> Void = { _ in }

  /// Freezes the roll rather than dropping it: the bars still take their current
  /// values, they just do not animate between positions, and the bloom snaps
  /// instead of easing. `Waveform` is the only component in the epic that
  /// animates, so it is the only one that has to honour this.
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Where the current drag is measured from. Held for the life of the gesture
  /// so every frame resolves from the same origin, rather than integrating
  /// deltas and accumulating drift.
  @State private var scrubAnchor: Double?

  /// SwiftUI resets a `@GestureState` when a gesture ends *or is cancelled*, and
  /// cancellation is the case that matters: `onEnded` never runs for a drag an
  /// enclosing scroll view steals, so an anchor cleared only there survives into
  /// the next touch and the playhead jumps the moment a finger lands.
  @GestureState private var isScrubbing = false

  var body: some View {
    ZStack {
      // Behind the bars, and outside the clipped drawing surface so it can
      // bleed past the box the way an aura has to.
      bloom
      WaveformCanvas(bars: bars, progress: progress, mode: mode, enhance: enhance)
    }
    .frame(maxWidth: .infinity)
    .frame(height: WaveformGeometry.height)
    .contentShape(Rectangle())
    // A drag does nothing where there is no take to wind — which includes a
    // `.scrub` that was handed an empty `bars`.
    .gesture(scrub, isEnabled: effectiveMode == .scrub)
    // The one reset path for the anchor, so it covers a cancelled gesture as
    // well as a clean lift.
    .onChange(of: isScrubbing) { _, scrubbing in
      if !scrubbing { scrubAnchor = nil }
    }
    // The handoff's motion table: the bloom eases over `.2s`, the playhead
    // ticks on `40ms`. These sit on the drawing rather than on the caller, so
    // the component owns its own motion — which is what makes the Reduce Motion
    // check the last word on it instead of a suggestion a caller can override.
    .animation(bloomAnimation, value: enhance)
    .animation(rollAnimation, value: progress)
    .accessibilityElement()
    .accessibilityLabel("Waveform")
    .accessibilityValue(accessibilityValue)
    .accessibilityAdjustableAction { direction in
      // Adjustable only where there is a playhead to move.
      guard effectiveMode == .scrub else { return }
      switch direction {
      case .increment: onScrub(steppedProgress(by: 1))
      case .decrement: onScrub(steppedProgress(by: -1))
      @unknown default: break
      }
    }
  }

  private var effectiveMode: WaveformMode {
    WaveformGeometry.effectiveMode(mode, bars: bars)
  }

  /// The soft warm aura. A real `Ellipse` with a real `.blur`, rather than a
  /// gradient inside the `Canvas` standing in for one: `Canvas` clips to its
  /// frame, so an in-canvas aura specified at 208% of the box height came out
  /// as a rectangle with hard top and bottom edges. Deliberately not a literal
  /// reverb tail.
  private var bloom: some View {
    GeometryReader { proxy in
      let resolved = WaveformGeometry.bloom(enhance: enhance, in: proxy.size)
      Ellipse()
        // `radial-gradient(closest-side, accent@α, transparent 72%)`, then
        // blurred — the prototype's own two steps. A solid fill blurred by the
        // same radius reads several times heavier than the handoff's render.
        .fill(
          RadialGradient(
            stops: [
              .init(color: DesignTokens.Palette.accent.opacity(resolved.opacity), location: 0),
              .init(color: .clear, location: 0.72),
            ],
            center: .center,
            startRadius: 0,
            endRadius: max(resolved.size.width, resolved.size.height) / 2
          )
        )
        .frame(width: resolved.size.width, height: resolved.size.height)
        .blur(radius: resolved.blurRadius)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  // MARK: - Gesture

  private var scrub: some Gesture {
    DragGesture(minimumDistance: 1)
      .updating($isScrubbing) { _, scrubbing, _ in scrubbing = true }
      .onChanged { gesture in
        let anchor = scrubAnchor ?? progress
        if scrubAnchor == nil { scrubAnchor = anchor }
        onScrub(
          WaveformGeometry.scrubProgress(
            from: anchor,
            translation: gesture.translation.width,
            barCount: bars.count
          )
        )
      }
  }

  // MARK: - Accessibility

  /// A fortieth of the take a swipe, matching the 41 stops `EnhanceDial` offers
  /// — a bar a swipe would be 419 swipes end to end on a 35-second demo. The
  /// scrub gesture is otherwise drag-only, which `screen-states.md` flags as a
  /// gap for exactly this reason.
  private func steppedProgress(by steps: Double) -> Double {
    min(max(progress + steps / 40, 0), 1)
  }

  private var accessibilityValue: String {
    switch effectiveMode {
    case .resting: "No audio yet"
    case .live: "Recording"
    case .scrub: "\(Int((min(max(progress, 0), 1) * 100).rounded()))% through the take"
    }
  }

  /// The playhead advances on a 40ms tick, so the roll between two ticks is
  /// linear over exactly that — and frozen under Reduce Motion, which is the
  /// behaviour the handoff names and this component owns for the epic.
  private var rollAnimation: Animation? {
    reduceMotion ? nil : .linear(duration: 0.04)
  }

  /// `.2s ease` on the bloom, instant under Reduce Motion.
  private var bloomAnimation: Animation? {
    reduceMotion ? nil : .easeInOut(duration: 0.2)
  }
}

// MARK: - The drawing surface

/// Every bar and the marker over them, on one `Canvas`.
///
/// It is `Animatable` over `progress` and `enhance` because a `Canvas` does not
/// tween its own contents — it re-runs its closure when an input changes, and
/// interpolates nothing. Without this the handoff's `.2s` bloom ease and 40ms
/// playhead tick would exist only on paper, and freezing them for Reduce Motion
/// would be freezing something that never moved.
///
/// The bar *levels* are deliberately not animatable: a rolling meter's bars
/// arrive as data, one every ~95ms, rather than travelling between two known
/// states, and an `[Float]` has no meaningful interpolation when its length
/// changes underneath it.
private struct WaveformCanvas: View, Animatable {

  var bars: [Float]
  var progress: Double
  var mode: WaveformMode
  var enhance: Double

  var animatableData: AnimatablePair<Double, Double> {
    get { AnimatablePair(progress, enhance) }
    set {
      progress = newValue.first
      enhance = newValue.second
    }
  }

  var body: some View {
    Canvas { context, size in
      let effective = WaveformGeometry.effectiveMode(mode, bars: bars)
      let levels = WaveformGeometry.resolvedBars(bars, mode: mode)

      switch effective {
      case .resting, .live:
        drawDistributed(levels, mode: effective, in: &context, size: size)
      case .scrub:
        drawScrub(levels, in: &context, size: size)
        drawMarker(in: &context, size: size)
      }
    }
  }

  /// `.resting` and `.live`: 48 bars spread across the full width, newest at the
  /// right edge. The bar *width* gives here rather than the count, because the
  /// count is what the design fixes — 48 fixed-5pt bars do not fit a phone.
  private func drawDistributed(
    _ levels: [Float],
    mode: WaveformMode,
    in context: inout GraphicsContext,
    size: CGSize
  ) {
    let width = WaveformGeometry.liveBarWidth(width: size.width)
    let played = DesignTokens.Palette.warm(0.35 + enhance * 0.65)
    // A `.live` strip shorter than 48 is padded on the left with resting bars.
    // They take the resting *colour* too: they are not quiet audio, they are
    // audio that has not arrived, and warming them reads as captured silence.
    let arrived = mode == .live ? levels.count - bars.count : levels.count

    for (index, level) in levels.enumerated() {
      let rect = WaveformGeometry.barRect(
        level: level,
        centreX: WaveformGeometry.liveBarCentreX(index: index, width: size.width),
        barWidth: width,
        in: size.height
      )
      let path = Path(roundedRect: rect, cornerRadius: width / 2)

      guard mode == .live, index >= arrived else {
        context.fill(path, with: .style(DesignTokens.Palette.barOff))
        continue
      }

      context.fill(path, with: .color(played))
      if WaveformGeometry.clips(level, in: mode) {
        drawClip(over: rect, cornerRadius: width / 2, in: &context)
      }
    }
  }

  /// The red top segment and its glow. `.live` only — a take being reviewed has
  /// nothing left to warn about.
  private func drawClip(over bar: CGRect, cornerRadius: CGFloat, in context: inout GraphicsContext)
  {
    let clip = Path(
      roundedRect: WaveformGeometry.clipRect(in: bar),
      cornerRadius: min(cornerRadius, WaveformGeometry.clipRect(in: bar).height / 2)
    )
    var glowing = context
    glowing.addFilter(.shadow(color: DesignTokens.Palette.destructive.opacity(0.6), radius: 4))
    glowing.fill(clip, with: .style(DesignTokens.Palette.destructive))
  }

  /// `.scrub`: the take scrolls under the fixed centre marker. Only the bars the
  /// box can show are drawn, so the cost is bounded by the width rather than by
  /// how long the take is.
  private func drawScrub(_ levels: [Float], in context: inout GraphicsContext, size: CGSize) {
    let playhead = WaveformGeometry.playhead(progress: progress, barCount: levels.count)
    let window = WaveformGeometry.visibleRange(
      progress: progress,
      barCount: levels.count,
      width: size.width
    )
    let warm = DesignTokens.Palette.warm(0.35 + enhance * 0.65)
    // The bars occupy the middle 94% of the box so the full-height marker clears
    // their tops, per the handoff — and per the prototype, which sizes its scrub
    // bars the same way. `Canvas` clips, so a marker drawn past the box would be
    // cut off instead; the bars are what give.
    let barBox = size.height * WaveformGeometry.scrubBarHeightFraction
    let inset = (size.height - barBox) / 2

    for index in window {
      let rect = WaveformGeometry.barRect(
        level: levels[index],
        centreX: WaveformGeometry.barCentreX(
          index: index,
          playhead: playhead,
          width: size.width
        ),
        barWidth: WaveformGeometry.barWidth,
        in: barBox
      )
      .offsetBy(dx: 0, dy: inset)
      let path = Path(roundedRect: rect, cornerRadius: WaveformGeometry.barWidth / 2)

      if Double(index) <= playhead {
        // Played. The amber eases off over the last few bars so the accent
        // marker is not amber-on-amber where it matters most.
        let opacity = WaveformGeometry.playedOpacity(index: index, playhead: playhead)
        context.fill(path, with: .color(warm.opacity(opacity)))
      } else {
        context.fill(path, with: .style(DesignTokens.Palette.barOff))
      }
    }
  }

  /// The fixed playhead: an accent line at the horizontal centre, just clearing
  /// the tops of the bars. Hard edges — the take runs the full width, no mask.
  private func drawMarker(in context: inout GraphicsContext, size: CGSize) {
    let rect = CGRect(
      x: (size.width - WaveformGeometry.markerWidth) / 2,
      y: 0,
      width: WaveformGeometry.markerWidth,
      height: size.height
    )
    var glowing = context
    glowing.addFilter(.shadow(color: DesignTokens.Palette.accent.opacity(0.55), radius: 3))
    glowing.fill(
      Path(roundedRect: rect, cornerRadius: WaveformGeometry.markerWidth / 2),
      with: .style(DesignTokens.Palette.accent)
    )
  }

}

// MARK: - Mode

/// What the waveform is showing. Not a rendering flag — each case is a different
/// relationship to time: nothing yet, arriving now, or a finished take being
/// wound past a playhead.
enum WaveformMode: Equatable, CaseIterable {

  /// Before capture. A flat line that does **not** react to input — nothing is
  /// being captured yet, so reacting would be a lie.
  case resting

  /// While capturing. A rolling meter, newest bar at the right edge.
  case live

  /// Reviewing a take. Centre-locked: the take scrolls under a fixed marker.
  case scrub
}

// MARK: - Bloom

/// The warm aura behind the bars, resolved for a given Enhance value and box.
struct WaveformBloom: Equatable {
  var size: CGSize
  var opacity: Double
  var blurRadius: CGFloat
}

// MARK: - Geometry

/// Every number the waveform draws with, lifted out of the view so the bar
/// layout, the visible window, the scrub arithmetic and the ramps are testable
/// without a simulator (`docs/PRINCIPLES.md` #3 at component scale).
///
/// It stays in the app target rather than in `Core`: this is view geometry in
/// points, not domain (`docs/PRINCIPLES.ios.md` #2 prefers `Core` only for
/// things that are genuinely core).
///
/// Pure and memoryless throughout — no clamped state is carried between calls,
/// so a caller can ask any question in any order and get the same answer.
enum WaveformGeometry {

  // MARK: Constants

  /// `docs/design/README.md` § Waveform. The fixed bar geometry is the *scrub*
  /// geometry; see ``liveBarWidth(width:)`` for why the live meter differs.
  static let barWidth: CGFloat = 5
  static let barGap: CGFloat = 3
  static let barStep: CGFloat = barWidth + barGap

  /// The box: height `120`, full width.
  static let height: CGFloat = 120

  /// The flat line before capture — low, but not nothing.
  static let restingLevel: Float = 0.05

  /// The live meter's window, in bars. Fixed by the design; the bar width is
  /// what gives when the box is narrower than 48 fixed bars.
  static let liveBarCount = 48

  /// A bar at or above this is clipping. `.live` only.
  static let clipLevel: Float = 0.9

  /// How much of a clipping bar goes red, from the top.
  static let clipTopFraction: CGFloat = 0.36

  /// The fixed centre playhead.
  static let markerWidth: CGFloat = 4

  /// How much of the box a scrub bar may fill. The remaining 6%, split between
  /// top and bottom, is the gap the full-height marker clears them by.
  static let scrubBarHeightFraction: CGFloat = 0.94

  /// The amber fades over this many bars before the marker…
  static let fadeSpan: Double = 6
  /// …down to this alpha, so the accent marker separates from amber bars.
  static let fadeFloor: Double = 0.45

  // MARK: Mode and levels

  /// What is actually drawn. An empty take is the resting line in every mode —
  /// never a blank box, never a crash on an index that is not there.
  static func effectiveMode(_ mode: WaveformMode, bars: [Float]) -> WaveformMode {
    bars.isEmpty ? .resting : mode
  }

  /// The levels actually drawn, for the effective mode.
  ///
  /// `.live` right-aligns into its 48 slots and pads the left with resting bars,
  /// so a meter that has only just started **grows into place from the right**
  /// rather than jumping once it fills.
  static func resolvedBars(_ bars: [Float], mode: WaveformMode) -> [Float] {
    switch effectiveMode(mode, bars: bars) {
    case .resting:
      return Array(repeating: restingLevel, count: liveBarCount)
    case .live:
      if bars.count >= liveBarCount {
        return Array(bars.suffix(liveBarCount))
      }
      return Array(repeating: restingLevel, count: liveBarCount - bars.count) + bars
    case .scrub:
      return bars
    }
  }

  // MARK: Layout

  /// How many fixed-geometry bars fit a box of this width. Floors — a partial
  /// bar is not drawn.
  static func visibleBarCount(width: CGFloat) -> Int {
    guard width > 0 else { return 0 }
    return Int((width / barStep).rounded(.down))
  }

  /// The fractional bar index under the centre marker. `progress` clamps, so an
  /// out-of-range value parks the strip at an end rather than scrolling it off
  /// into space.
  static func playhead(progress: Double, barCount: Int) -> Double {
    guard barCount > 1 else { return 0 }
    return clamped(progress) * Double(barCount - 1)
  }

  /// ``playhead(progress:barCount:)`` rounded to a whole bar.
  static func centredBarIndex(progress: Double, barCount: Int) -> Int {
    guard barCount > 0 else { return 0 }
    let index = Int(playhead(progress: progress, barCount: barCount).rounded())
    return min(max(index, 0), barCount - 1)
  }

  /// The bar indices that can land inside the box, with a bar of slack each
  /// side. This is what bounds the drawing cost by the width of the box rather
  /// than by the length of the take.
  static func visibleRange(progress: Double, barCount: Int, width: CGFloat) -> Range<Int> {
    guard barCount > 0, width > 0 else { return 0..<0 }
    let centre = playhead(progress: progress, barCount: barCount)
    let span = Int(((width / 2) / barStep).rounded(.up)) + 1
    let lower = max(0, Int(centre.rounded(.down)) - span)
    let upper = min(barCount, Int(centre.rounded(.up)) + span + 1)
    return lower..<upper
  }

  /// A scrub bar's centre. The bar at the playhead sits exactly on the box's
  /// centre, and the strip is free to run off either edge — there is no clamping
  /// of the scroll to the content.
  static func barCentreX(index: Int, playhead: Double, width: CGFloat) -> CGFloat {
    width / 2 + CGFloat(Double(index) - playhead) * barStep
  }

  /// `.resting` and `.live` spread all 48 bars across the full width instead of
  /// using the fixed 5pt bar: the design fixes the *count*, and 48 bars at an
  /// 8pt step need 381pt, which a 24pt-margined phone screen does not have. The
  /// count is the thing the eye reads, so the width is what gives.
  static func liveBarWidth(width: CGFloat) -> CGFloat {
    let available = width - barGap * CGFloat(liveBarCount - 1)
    return max(1, available / CGFloat(liveBarCount))
  }

  /// A live bar's centre. Index 0 sits at the left edge, the newest at the right.
  static func liveBarCentreX(index: Int, width: CGFloat) -> CGFloat {
    let bar = liveBarWidth(width: width)
    return CGFloat(index) * (bar + barGap) + bar / 2
  }

  /// One bar, **symmetric about the horizontal midline** — it grows equally
  /// above and below, which is what makes the strip read as a waveform rather
  /// than a bar chart. Floored at the bar's own width so a near-silent bar draws
  /// as a cap instead of vanishing.
  static func barRect(level: Float, centreX: CGFloat, barWidth: CGFloat, in height: CGFloat)
    -> CGRect
  {
    let clampedLevel = CGFloat(min(max(level, 0), 1))
    let barHeight = max(clampedLevel * height, barWidth)
    return CGRect(
      x: centreX - barWidth / 2,
      y: (height - barHeight) / 2,
      width: barWidth,
      height: barHeight
    )
  }

  /// The red top segment of a clipping bar.
  static func clipRect(in bar: CGRect) -> CGRect {
    CGRect(
      x: bar.minX,
      y: bar.minY,
      width: bar.width,
      height: bar.height * clipTopFraction
    )
  }

  // MARK: Gesture

  /// The progress a drag reports out.
  ///
  /// 1:1 with **bar geometry**, not with the width of the box: dragging 80pt
  /// moves ten 8pt bars whether the take is 200 bars or 4000. Dragging left
  /// advances, matching the take scrolling leftwards under the marker as it
  /// plays.
  ///
  /// - Parameters:
  ///   - startProgress: what this gesture is measured from.
  ///   - translation: horizontal drag, SwiftUI's sense — negative is leftward.
  ///   - barCount: bars in the take.
  static func scrubProgress(from startProgress: Double, translation: CGFloat, barCount: Int)
    -> Double
  {
    guard barCount > 1 else { return clamped(startProgress) }
    let barsMoved = Double(-translation / barStep)
    return clamped(clamped(startProgress) + barsMoved / Double(barCount - 1))
  }

  // MARK: Ramps

  /// Clipping is a capture warning, so it exists only while capturing.
  static func clips(_ level: Float, in mode: WaveformMode) -> Bool {
    mode == .live && level >= clipLevel
  }

  /// How opaque a played bar is. Full amber away from the marker, easing down to
  /// ``fadeFloor`` at it, so the accent playhead does not sit amber-on-amber.
  static func playedOpacity(index: Int, playhead: Double) -> Double {
    let distance = max(0, playhead - Double(index))
    return fadeFloor + (1 - fadeFloor) * min(1, distance / fadeSpan)
  }

  /// The bloom's geometry for an Enhance value, as fractions of the box.
  /// `docs/design/README.md` § Waveform: alpha `0.09 → 0.24`, width `58% → 124%`,
  /// height `118% → 208%`, blur `6 → 15`.
  static func bloom(enhance: Double, in box: CGSize) -> WaveformBloom {
    let value = clamped(enhance)
    return WaveformBloom(
      size: CGSize(
        width: box.width * (0.58 + value * 0.66),
        height: box.height * (1.18 + value * 0.90)
      ),
      opacity: 0.09 + value * 0.15,
      blurRadius: 6 + CGFloat(value) * 9
    )
  }

  private static func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }
}

// MARK: - Previews

/// Fixture bars. The component owns no time, so a preview is just an array —
/// which is the whole point of keeping the roll out of the view.
private enum WaveformFixture {

  /// A take with a shape to it: a quiet start, a loud middle, a tail.
  static let take: [Float] = (0..<420).map { index in
    let position = Double(index) / 419
    let envelope = sin(position * .pi)
    let detail = 0.55 + 0.45 * sin(position * 47)
    return Float(max(0.06, envelope * detail * 0.92))
  }

  /// A live meter caught mid-roll, with two bars over the clip threshold.
  static let hot: [Float] = (0..<48).map { index in
    index == 19 || index == 32 ? 0.95 : Float(0.25 + 0.5 * abs(sin(Double(index) * 0.7)))
  }

  /// Only nine bars in — the case that has to grow into place from the right
  /// rather than jump once the strip fills.
  static let starting: [Float] = (0..<9).map { Float(0.3 + 0.4 * abs(sin(Double($0)))) }
}

/// Every mode and every state the ticket names, at both ends of the Enhance
/// range, in one scroll. The first row is live so the scrub gesture — including
/// what happens when a drag runs past an end — can be checked in the canvas.
private struct WaveformGallery: View {

  @State private var progress: Double = 0.5
  @State private var enhance: Double = 0.5

  var body: some View {
    ScrollView {
      VStack(spacing: DesignTokens.Spacing.block) {
        interactive

        specimen(".resting — flat line, ignores input") {
          Waveform(bars: [], mode: .resting)
        }

        specimen(".live — mid-fill, grows in from the right") {
          Waveform(bars: WaveformFixture.starting, mode: .live, enhance: 0.2)
        }

        specimen(".live — clipping, two bars ≥ 0.9") {
          Waveform(bars: WaveformFixture.hot, mode: .live, enhance: 0.35)
        }

        specimen(".live — Enhance 1.0") {
          Waveform(bars: WaveformFixture.hot, mode: .live, enhance: 1)
        }

        ForEach([0.0, 0.5, 1.0], id: \.self) { position in
          specimen(".scrub — progress \(position.formatted(.number.precision(.fractionLength(1))))")
          {
            Waveform(bars: WaveformFixture.take, progress: position, mode: .scrub, enhance: 0.25)
          }
        }

        specimen(".scrub — Enhance 0.0") {
          Waveform(bars: WaveformFixture.take, progress: 0.5, mode: .scrub, enhance: 0)
        }

        specimen(".scrub — Enhance 1.0") {
          Waveform(bars: WaveformFixture.take, progress: 0.5, mode: .scrub, enhance: 1)
        }

        specimen(".scrub — one-bar take") {
          Waveform(bars: [0.7], progress: 1, mode: .scrub, enhance: 0.5)
        }
      }
      .padding(DesignTokens.Spacing.margin)
    }
    .background(DesignTokens.Palette.pageBackground)
  }

  private var interactive: some View {
    VStack(spacing: DesignTokens.Spacing.hairline) {
      Text("interactive — drag the waveform to scrub")
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(DesignTokens.Palette.textTertiary)
      Waveform(
        bars: WaveformFixture.take,
        progress: progress,
        mode: .scrub,
        enhance: enhance,
        onScrub: { progress = $0 }
      )
      EnhanceDial(value: $enhance)
    }
  }

  private func specimen(_ caption: String, @ViewBuilder content: () -> some View) -> some View {
    VStack(spacing: DesignTokens.Spacing.hairline) {
      Text(caption)
        .font(DesignTokens.Typography.caption)
        .foregroundStyle(DesignTokens.Palette.textTertiary)
      content()
    }
  }
}

#Preview("Waveform — light") { WaveformGallery().preferredColorScheme(.light) }
#Preview("Waveform — dark") { WaveformGallery().preferredColorScheme(.dark) }
