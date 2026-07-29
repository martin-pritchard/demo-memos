import SwiftUI

/// The one screen a take is captured, reviewed, renamed, adjusted and shared on.
///
/// **Everything below the header is constant.** Only the header and the
/// right-hand transport button change between the five modes, which is what
/// stops the layout jumping as capture moves through them — the handoff says so
/// in as many words, and `TakePresentation` is where that table lives.
///
/// State in, events out. The screen owns no recorder, no player and no clock:
/// it draws a `TakeScreenState` and reports taps. The bindings that write back —
/// the Enhance dial, the scrub, the title field — write into that state and
/// nowhere else.
///
/// **No `NavigationStack` here.** The header is a `.toolbar`, so the container
/// that presents this screen supplies the stack. Which container that is — a
/// sheet from the list, a push — is a routing decision this ticket defers.
struct TakeScreen: View {

  @Binding var state: TakeScreenState

  /// Discard the take and leave. The record flow's header-left.
  var onCancel: () -> Void = {}

  /// Leave a saved take alone and go back to the list. Playback's header-left.
  ///
  /// Separate from ``onCancel`` even though this ticket routes neither: they are
  /// different actions, and `screen-states.md` lists what `‹ Demos` does to an
  /// unsaved rename and a changed Enhance value as an open question. One closure
  /// for both would answer it here, in the wrong ticket, and answer it wrong.
  var onBack: () -> Void = {}

  var onDone: () -> Void = {}

  /// The tapped transport role, whichever button it came from. The screen has
  /// no opinion on what recording or playing *does*.
  var onTransport: (TransportRole) -> Void = { _ in }

  private var presentation: TakePresentation { state.presentation }

  var body: some View {
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(DesignTokens.Palette.pageBackground.ignoresSafeArea())
      .safeAreaInset(edge: .bottom) { transportTray }
      .toolbar { header }
  }

  // MARK: - Content

  /// Title over meta, then the waveform, then the timer with the coaching slot
  /// under it — the handoff's 30pt blocks, top-anchored below the header.
  private var content: some View {
    VStack(spacing: DesignTokens.Spacing.block) {
      VStack(spacing: DesignTokens.Spacing.hairline) {
        title
        Text(state.meta)
          .font(DesignTokens.Typography.meta)
          .foregroundStyle(DesignTokens.Palette.textSecondary)
      }

      Waveform(
        bars: state.bars,
        progress: state.progress,
        mode: presentation.waveformMode,
        enhance: state.enhance,
        onScrub: { state.progress = $0 }
      )

      VStack(spacing: DesignTokens.Spacing.label) {
        TimerReadout(elapsed: state.timerReading, isActive: presentation.isTimerActive)
        // The slot is reserved in every mode, not just the one that fills it:
        // collapsing it would let a hint arriving mid-take shove the tray down.
        CoachingLine(level: presentation.showsCoaching ? state.coaching : .clear)
      }
    }
    .padding(.top, DesignTokens.Spacing.contentTop)
    .padding(.horizontal, DesignTokens.Spacing.margin)
  }

  @ViewBuilder private var title: some View {
    if presentation.isTitleEditable {
      // Inline rename, playback only — centred, transparent, no border, which
      // is what `.plain` in a bare `TextField` already is.
      TextField("Name", text: $state.title)
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(DesignTokens.Typography.screenTitle)
        .foregroundStyle(DesignTokens.Palette.text)
    } else {
      Text(state.title)
        .font(DesignTokens.Typography.screenTitle)
        .foregroundStyle(DesignTokens.Palette.text)
        .multilineTextAlignment(.center)
    }
  }

  // MARK: - Header

  @ToolbarContentBuilder private var header: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      switch presentation.leading {
      case .cancel:
        Button("Cancel", action: onCancel)
      case .backToDemos:
        // An explicit stack rather than a `Label`: iOS 26's toolbar renders a
        // `Label` icon-only however it is styled, and the design's back control
        // is "‹ Demos" — the chevron alone loses where it goes back *to*.
        Button(action: onBack) {
          HStack(spacing: DesignTokens.Spacing.hairline) {
            Image(systemName: "chevron.left")
            Text("Demos")
          }
        }
      }
    }

    if presentation.showsShareAndDone {
      ToolbarItem(placement: .topBarTrailing) {
        // The take's name stands in for the file: rendering Enhance into a
        // shareable asset is audio work, and the list has nothing real to point
        // at yet. The sheet itself is the system's, per the handoff.
        ShareLink(item: state.title) {
          Image(systemName: "square.and.arrow.up")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button("Done", action: onDone).fontWeight(.semibold)
      }
    }
  }

  // MARK: - Transport tray

  private var transportTray: some View {
    // The handoff puts 20pt between the dial and the buttons (26 in playback).
    // No token names that gap, so this borrows the nearest one — `margin`'s doc
    // line calls it the side margin, and 24 sits between the handoff's two
    // values. Layout, not pixel values, is what the ticket asks to match.
    VStack(spacing: DesignTokens.Spacing.margin) {
      EnhanceDial(value: $state.enhance)

      HStack(spacing: DesignTokens.Spacing.group) {
        TransportButton(role: presentation.leftRole) { onTransport(presentation.leftRole) }
          .disabled(!presentation.isLeftEnabled)
        TransportButton(role: presentation.rightRole) { onTransport(presentation.rightRole) }
          .disabled(!presentation.isRightEnabled)
      }
    }
    // The handoff's 42pt tray inset is the bottom safe area (34) plus this,
    // which is the mapping `DesignTokens.swift` records for it.
    .padding(.bottom, 8)
  }
}

// MARK: - Previews

/// Every state in `docs/design/screen-states.md` §4, one preview each, driven by
/// the named scenarios on `TakeScreenState`. The dial and the scrub are live in
/// all of them — the bindings write back into the preview's own state.
private struct TakePreview: View {

  @State var state: TakeScreenState

  var body: some View {
    NavigationStack {
      TakeScreen(state: $state)
    }
  }
}

#Preview("4.1 ready") { TakePreview(state: .ready) }
#Preview("4.2 count-in") { TakePreview(state: .countIn()) }
#Preview("4.3 recording") { TakePreview(state: .recording) }
#Preview("4.3 recording — low") { TakePreview(state: .recordingQuiet) }
#Preview("4.3 recording — hot + clipping") { TakePreview(state: .recordingHot) }
#Preview("4.4 stopped") { TakePreview(state: .stopped) }
#Preview("4.4 stopped — playing, Resume dimmed") { TakePreview(state: .stoppedPlaying) }
#Preview("4.5 playback") { TakePreview(state: .playback) }
#Preview("4.5 playing — pause, Resume dimmed") { TakePreview(state: .playing) }
#Preview("Enhance — Hall") { TakePreview(state: .playbackHall) }
#Preview("Zero-length take") { TakePreview(state: .zeroLength) }

#Preview("4.1 ready — dark") {
  TakePreview(state: .ready).preferredColorScheme(.dark)
}
#Preview("4.3 recording — dark") {
  TakePreview(state: .recording).preferredColorScheme(.dark)
}
#Preview("4.5 playback — dark") {
  TakePreview(state: .playback).preferredColorScheme(.dark)
}
