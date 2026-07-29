//
//  DemoMemosApp.swift
//  DemoMemos
//
//  Created by Martin Pritchard on 28/07/2026.
//

import SwiftUI

@main
struct DemoMemosApp: App {

  /// The one place dependencies are constructed (`docs/PRINCIPLES.md` #6).
  @State private var model = TakeScreenModel(capture: DemoMemosApp.makeCaptureState())

  var body: some Scene {
    WindowGroup {
      // `TakeScreen` draws its header as a `.toolbar` and brings no stack of its
      // own, so the container owes it one. Routing between screens is #5x — this
      // stack has exactly one thing in it.
      NavigationStack {
        TakeScreen(
          state: model.binding,
          onTransport: model.transport,
          onNoticeAction: model.perform)
      }
    }
  }

  @MainActor
  private static func makeCaptureState() -> CaptureState {
    let folder = (try? RecordingsFolder.defaultURL()) ?? URL.temporaryDirectory

    // Before anything reads the folder: a take that was interrupted by a jetsam
    // kill still has its samples on disk but a header claiming the length it had
    // when recording started. Rewriting that header here is what makes the
    // no-corrupt-files promise hold for the background case, which is the case
    // it is most likely to be tested by.
    for (url, result) in RecordingRepair.repairAll(in: folder) {
      if case .success(.repaired(let bytes)) = result {
        print("Recovered \(url.lastPathComponent): declared \(bytes) bytes of samples")
      }
    }

    return CaptureState(
      recorder: AudioRecorder(),
      player: AudioPlayer(),
      folder: folder,
      latestTake: RecordingsFolder.takes(in: folder).last)
  }
}
