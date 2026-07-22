import SwiftUI

/// 1b / 1c — record and playback are one screen with four states (1d).
/// Everything below the header is constant; only the header and the right
/// transport button change, so nothing jumps as the state moves on.
struct CaptureView: View {
  @Bindable var state: CaptureState
  /// The date shown under the title — the memo's, or now for a fresh take.
  var createdAt: Date
  let onFinish: () -> Void

  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var scenePhase
  @FocusState private var titleFocused: Bool
  @State private var scrubOrigin: Double?

  var body: some View {
    VStack(spacing: 0) {
      content
      Spacer(minLength: 0)
      tray
    }
    .background(Palette.pageBackground.ignoresSafeArea())
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { toolbar }
    .task { await state.onAppear() }
    .onDisappear { state.onDisappear() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { state.handleBackground() }
    }
    .onChange(of: state.isFinished) { _, finished in
      if finished { onFinish() }
    }
  }

  // MARK: - Toolbar
  //
  // The design's header — Cancel/Done in the record flow, ‹ Demos + Share in
  // playback — is exactly a native nav bar. Cancel/Done use the system's
  // cancellation/confirmation placements; the playback back button comes from
  // the parent stack for free, and Share is a `ShareLink`.

  @ToolbarContentBuilder private var toolbar: some ToolbarContent {
    if state.status != .playback {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { state.cancel() }
      }
    }
    if state.status == .stopped {
      ToolbarItem(placement: .confirmationAction) {
        Button("Done") { state.done() }
      }
    }
    if state.status == .playback, let url = state.shareURL {
      ToolbarItem(placement: .confirmationAction) {
        ShareLink(item: url) {
          Image(systemName: "square.and.arrow.up")
        }
      }
    }
  }

  // MARK: - Title · waveform · timer

  private var content: some View {
    VStack(spacing: 0) {
      title
      Text(createdAt.listMetaLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .padding(.bottom, 30)

      waveform

      timer
        .padding(.top, 30)

      // Reserved so the layout below never shifts when an error appears.
      Text(state.errorMessage ?? " ")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(state.errorMessage == nil ? .clear : Color(.systemRed))
        .frame(height: 24)
        .padding(.top, 14)
    }
    .padding(.top, 40)
    .padding(.horizontal, 24)
  }

  @ViewBuilder private var title: some View {
    if state.status == .playback {
      TextField("Name", text: $state.name)
        .focused($titleFocused)
        .submitLabel(.done)
        .onSubmit { state.commitRename() }
        .onChange(of: titleFocused) { _, focused in
          if !focused { state.commitRename() }
        }
        .multilineTextAlignment(.center)
        .font(.title2.bold())
    } else {
      Text(state.name)
        .font(.title2.bold())
        .lineLimit(1)
    }
  }

  private var waveform: some View {
    Group {
      if state.isLive {
        // Ready is at rest: no bloom, no warmth, until something is captured.
        WaveformView(
          levels: state.levels,
          mode: .live,
          enhance: state.status == .ready ? 0 : state.enhance
        )
      } else {
        WaveformView(
          levels: state.takeLevels,
          mode: .scrub(progress: state.progress),
          enhance: state.enhance
        )
        .contentShape(Rectangle())
        .gesture(scrubGesture)
      }
    }
  }

  /// Drag the waveform to scrub — the take moves under the fixed marker, 1:1
  /// with the bars, exactly as the Enhance dial behaves.
  private var scrubGesture: some Gesture {
    DragGesture(minimumDistance: 1)
      .onChanged { gesture in
        let origin = scrubOrigin ?? state.progress
        scrubOrigin = origin
        let range = CGFloat(max(state.takeLevels.count - 1, 1)) * WaveformView.scrubStep
        state.scrub(to: origin - Double(gesture.translation.width / range))
      }
      .onEnded { _ in scrubOrigin = nil }
  }

  private var timer: some View {
    let label = state.displayTime.transportLabel
    return HStack(spacing: 0) {
      Text(label.major)
        .foregroundStyle(state.status == .ready ? Color(.quaternaryLabel) : Color.primary)
      Text(label.hundredths)
        .foregroundStyle(Color(.tertiaryLabel))
    }
    .font(.system(size: 56, weight: .light))
    .monospacedDigit()
    .kerning(-1)
  }

  // MARK: - Tray

  private var tray: some View {
    VStack(spacing: state.status == .playback ? 26 : 20) {
      EnhanceSlider(value: $state.enhance)
      // Only an actual denial earns the notice — while the system prompt is
      // still up, permission is undetermined and nothing has been refused yet.
      if state.permission == .denied {
        permissionNotice
      } else {
        transport
      }
    }
    .padding(.bottom, 42)
  }

  private var transport: some View {
    HStack(spacing: 44) {
      labelled(state.isPlaying ? "Pause" : "Play") {
        Button {
          state.togglePlay()
        } label: {
          Circle()
            .fill(Palette.accent.opacity(0.16))
            .overlay(
              Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26))
                .foregroundStyle(Palette.accentText)
            )
            .frame(width: 66, height: 66)
        }
        .disabled(!state.canPlay)
        .opacity(state.canPlay ? 1 : 0.35)
      }

      labelled(mainLabel) {
        Button {
          state.status == .recording ? state.stop() : state.record()
        } label: {
          Circle()
            .strokeBorder(Palette.transportRing, lineWidth: 4)
            .overlay(mainGlyph)
            .frame(width: 66, height: 66)
        }
        .disabled(!isMainEnabled)
        .opacity(isMainEnabled ? 1 : 0.35)
      }
    }
  }

  /// The right button dims rather than lying about being live — the same
  /// vocabulary the design uses for Play before a take exists. Resume is only
  /// offered while the take is still open; playback never captures.
  private var isMainEnabled: Bool {
    switch state.status {
    case .ready, .recording: true
    case .stopped: state.canResume
    case .playback: false
    }
  }

  private var mainLabel: String {
    switch state.status {
    case .ready: "Record"
    case .recording: "Stop"
    case .stopped, .playback: "Resume"
    }
  }

  @ViewBuilder private var mainGlyph: some View {
    switch state.status {
    case .ready:
      Circle().fill(Palette.accent).frame(width: 51, height: 51)
    case .recording:
      RoundedRectangle(cornerRadius: 9).fill(Palette.accent).frame(width: 26, height: 26)
    case .stopped, .playback:
      Circle().fill(Palette.accent).frame(width: 26, height: 26)
    }
  }

  private func labelled(_ label: String, @ViewBuilder button: () -> some View) -> some View {
    VStack(spacing: 8) {
      button()
      Text(label)
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  /// Permission denied — a plain explanation and a way to fix it. The record
  /// button is never present-but-dead.
  private var permissionNotice: some View {
    VStack(spacing: 12) {
      Text("Demo Memos needs the microphone to record.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
      }
      .font(.body.weight(.semibold))
    }
    .frame(height: 90)
    .padding(.horizontal, 32)
  }
}

// MARK: - Previews — every state in 1d, with no microphone and no files.
// Wrapped in a NavigationStack so the native toolbar (Cancel/Done/Share) shows.

private func capturePreview(_ state: CaptureState, createdAt: Date = .now) -> some View {
  NavigationStack {
    CaptureView(state: state, createdAt: createdAt, onFinish: {})
  }
}

#Preview("1b · ready") { capturePreview(CapturePreview.state(.ready)) }

#Preview("1b · recording") { capturePreview(CapturePreview.state(.recording)) }

#Preview("1b · stopped") { capturePreview(CapturePreview.state(.stopped)) }

#Preview("1c · playback") {
  capturePreview(CapturePreview.playbackState(), createdAt: PreviewScenario.sampleMemo.createdAt)
}

#Preview("2c · playback (dark)") {
  capturePreview(CapturePreview.playbackState(), createdAt: PreviewScenario.sampleMemo.createdAt)
    .preferredColorScheme(.dark)
}

#Preview("Microphone denied") {
  capturePreview(CapturePreview.state(.ready, permission: .denied))
}

#Preview("Save failed") { capturePreview(CapturePreview.failedSaveState()) }
