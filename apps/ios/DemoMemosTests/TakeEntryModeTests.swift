import Core
import Foundation
import Testing

@testable import DemoMemos

private let existingDemoID = UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!

/// Every capture mode that leaves the take at rest — the three the entry and
/// `capturedThisVisit` have to disambiguate between.
private let restingModes: [CaptureMode] = [.idle, .awaitingPermission, .playing]

/// The projection under test, reduced to the one property these tests care about.
@MainActor
private func projectedMode(
  _ mode: CaptureMode,
  entry: TakeEntry,
  capturedThisVisit: Bool
) -> TakeMode {
  TakeScreenModel.project(
    mode: mode,
    entry: entry,
    capturedThisVisit: capturedThisVisit,
    elapsed: 0,
    position: 0,
    duration: 0,
    enhance: 0.5,
    title: "New Demo 1",
    notice: nil,
    coaching: .clear
  ).mode
}

@Suite("TakeScreenModel.project: recording")
@MainActor
struct TakeEntryModeRecordingTests {

  @Test(arguments: [false, true])
  func recordingANewDemoIsAlwaysTheRecordingMode(capturedThisVisit: Bool) {
    #expect(
      projectedMode(.recording, entry: .newDemo, capturedThisVisit: capturedThisVisit)
        == .recording
    )
  }

  @Test(arguments: [false, true])
  func recordingOverAnExistingDemoIsAlwaysTheRecordingMode(capturedThisVisit: Bool) {
    #expect(
      projectedMode(
        .recording,
        entry: .demo(id: existingDemoID),
        capturedThisVisit: capturedThisVisit
      ) == .recording
    )
  }
}

@Suite("TakeScreenModel.project: a demo opened from the list")
@MainActor
struct TakeEntryModeExistingDemoTests {

  @Test(arguments: restingModes, [false, true])
  func anExistingDemoIsAlwaysInPlayback(mode: CaptureMode, capturedThisVisit: Bool) {
    #expect(
      projectedMode(
        mode,
        entry: .demo(id: existingDemoID),
        capturedThisVisit: capturedThisVisit
      ) == .playback
    )
  }
}

@Suite("TakeScreenModel.project: a new demo")
@MainActor
struct TakeEntryModeNewDemoTests {

  @Test(arguments: restingModes)
  func aNewDemoWithNothingCapturedThisVisitIsReady(mode: CaptureMode) {
    #expect(projectedMode(mode, entry: .newDemo, capturedThisVisit: false) == .ready)
  }

  @Test(arguments: restingModes)
  func aNewDemoCapturedThisVisitIsStopped(mode: CaptureMode) {
    #expect(projectedMode(mode, entry: .newDemo, capturedThisVisit: true) == .stopped)
  }

  /// The bug this projection fixes: the mode used to be decided by whether a
  /// recording existed on disk, so tapping New Demo after any earlier take
  /// opened straight into `.stopped` — a take the user never made. Only
  /// something captured during *this* visit may produce `.stopped`.
  @Test func tappingNewDemoWithAnOlderTakeOnDiskOpensReadyNotStopped() {
    let state = TakeScreenModel.project(
      mode: .idle,
      entry: .newDemo,
      capturedThisVisit: false,
      elapsed: 0,
      position: 0,
      // Stands in for the older take already on disk: a non-zero duration that
      // must no longer decide the mode.
      duration: 12.5,
      enhance: 0.5,
      title: "New Demo 1",
      notice: nil,
      coaching: .clear
    )

    #expect(state.mode == .ready)
  }
}
