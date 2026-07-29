import Core
import SwiftUI
import UIKit

/// A record button and a play button. No styling — that is the issue's scope,
/// not an oversight.
///
/// State in, events out: the screen never reaches for a recorder, a player, or
/// the filesystem. Everything it shows comes from `CaptureState`, which is
/// constructed in `DemoMemosApp`.
///
/// Lives beside the composition root rather than in `Audio/`, which imports no
/// UI framework (`docs/PRINCIPLES.ios.md` #2). One screen does not yet earn a
/// feature folder (`docs/PRINCIPLES.md` #8).
struct RecordingScreen: View {

  @Bindable var state: CaptureState

  var body: some View {
    VStack(spacing: 24) {
      Button(state.mode == .recording ? "Stop" : "Record") {
        Task { await state.recordTapped() }
      }
      .disabled(!state.canRecord)

      Button(state.mode == .playing ? "Stop" : "Play") {
        state.playTapped()
      }
      .disabled(!state.canPlay)

      // The one Enhance dial. Functional, unstyled — same precedent as the
      // buttons above. 0 is a true bypass; the curve is tuned by ear on device.
      VStack {
        Text("Enhance")
        Slider(value: $state.warmth, in: 0...1)
      }
      .disabled(state.latestTake == nil)

      if let notice = state.notice {
        Text(notice)
          .multilineTextAlignment(.center)
      }

      if state.isDenied, let settings = URL(string: UIApplication.openSettingsURLString) {
        Link("Open Settings", destination: settings)
      }
    }
    .padding()
  }
}

#Preview("Empty") { RecordingScreen(state: .empty) }
#Preview("Populated") { RecordingScreen(state: .populated) }
#Preview("Enhance up") {
  let state = CaptureState.populated
  state.warmth = 0.8
  return RecordingScreen(state: state)
}
#Preview("Recording") { RecordingScreen(state: .recording) }
#Preview("Playing") { RecordingScreen(state: .playing) }
#Preview("Denied") { RecordingScreen(state: .denied) }
#Preview("Interrupted") { RecordingScreen(state: .interrupted) }
