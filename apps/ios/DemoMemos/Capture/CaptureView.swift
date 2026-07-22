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
  @State private var shareTarget: ShareTarget?
  @State private var scrubOrigin: Double?

  var body: some View {
    VStack(spacing: 0) {
      header
      content
      Spacer(minLength: 0)
      tray
    }
    .background(Palette.pageBackground.ignoresSafeArea())
    .task { await state.onAppear() }
    .onDisappear { state.onDisappear() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { state.handleBackground() }
    }
    .onChange(of: state.isFinished) { _, finished in
      if finished { onFinish() }
    }
    .sheet(item: $shareTarget) { ShareSheet(url: $0.url) }
  }

  // MARK: - Header

  private var header: some View {
    HStack {
      leading
      Spacer()
      trailing
    }
    .font(.system(size: 17, weight: .medium))
    .tint(Palette.accent)
    .frame(height: 26)
    .padding(.top, 56)
    .padding(.horizontal, 20)
  }

  @ViewBuilder private var leading: some View {
    if state.status == .playback {
      Button {
        state.commitRename()
        onFinish()
      } label: {
        HStack(spacing: 3) {
          Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
          Text("Demos")
        }
      }
    } else {
      Button("Cancel") { state.cancel() }
    }
  }

  @ViewBuilder private var trailing: some View {
    switch state.status {
    case .ready, .recording:
      EmptyView()
    case .stopped:
      Button("Done") { state.done() }
        .fontWeight(.semibold)
    case .playback:
      Button {
        if let url = state.shareURL { shareTarget = ShareTarget(url: url) }
      } label: {
        Image(systemName: "square.and.arrow.up").font(.system(size: 20, weight: .medium))
      }
      .accessibilityLabel("Share")
    }
  }

  // MARK: - Title · waveform · timer

  private var content: some View {
    VStack(spacing: 0) {
      title
      Text(createdAt.listMetaLabel)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
        .padding(.bottom, 30)

      waveform

      timer
        .padding(.top, 30)

      // Reserved so the layout below never shifts when an error appears.
      Text(state.errorMessage ?? " ")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(state.errorMessage == nil ? .clear : Color(.systemRed))
        .frame(height: 24)
        .padding(.top, 14)
    }
    .padding(.top, 90)
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
        .font(.system(size: 24, weight: .bold))
        .tint(Palette.accent)
    } else {
      Text(state.name)
        .font(.system(size: 24, weight: .bold))
        .lineLimit(1)
    }
  }

  private var waveform: some View {
    Group {
      if state.isLive {
        WaveformView(levels: state.levels, mode: .live, enhance: state.enhance)
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
      if state.canRecord || state.status == .playback {
        transport
      } else {
        permissionNotice
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
      }
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
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }

  /// Permission denied — a plain explanation and a way to fix it. The record
  /// button is never present-but-dead.
  private var permissionNotice: some View {
    VStack(spacing: 12) {
      Text("Demo Memos needs the microphone to record.")
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button("Open Settings") {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
      }
      .font(.system(size: 17, weight: .semibold))
      .tint(Palette.accent)
    }
    .frame(height: 90)
    .padding(.horizontal, 32)
  }
}

// MARK: - Previews — every state in 1d, with no microphone and no files

#Preview("1b · ready") {
  CaptureView(state: CapturePreview.state(.ready), createdAt: .now, onFinish: {})
}

#Preview("1b · recording") {
  CaptureView(state: CapturePreview.state(.recording), createdAt: .now, onFinish: {})
}

#Preview("1b · stopped") {
  CaptureView(state: CapturePreview.state(.stopped), createdAt: .now, onFinish: {})
}

#Preview("1c · playback") {
  CaptureView(
    state: CapturePreview.playbackState(),
    createdAt: PreviewScenario.sampleMemo.createdAt,
    onFinish: {}
  )
}

#Preview("2c · playback (dark)") {
  CaptureView(
    state: CapturePreview.playbackState(),
    createdAt: PreviewScenario.sampleMemo.createdAt,
    onFinish: {}
  )
  .preferredColorScheme(.dark)
}

#Preview("Microphone denied") {
  CaptureView(
    state: CapturePreview.state(.ready, permission: .denied), createdAt: .now, onFinish: {})
}

#Preview("Save failed") {
  CaptureView(state: CapturePreview.failedSaveState(), createdAt: .now, onFinish: {})
}
