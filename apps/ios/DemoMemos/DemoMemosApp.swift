//
//  DemoMemosApp.swift
//  DemoMemos
//
//  Created by Martin Pritchard on 28/07/2026.
//

import Core
import SwiftUI

@main
struct DemoMemosApp: App {

  /// The one place dependencies are constructed (`docs/PRINCIPLES.md` #6).
  @State private var model = DemoMemosApp.makeModel()

  /// One router for the app, holding `Core`'s pure `AppRoute`.
  @State private var router = AppRouter()

  var body: some Scene {
    WindowGroup {
      switch router.route.root {
      case .onboarding:
        // No stack: onboarding is a one-way door with no back and no title.
        OnboardFeatures(onContinue: router.onboardingCompleted)
      case .demos:
        demos
      }
    }
  }

  /// The list, and the Take screen pushed over it.
  ///
  /// Neither screen brings a `NavigationStack` — each says so in its own doc
  /// comment — because the large title and the header are `.navigationTitle` and
  /// `.toolbar`, which need a container to belong to. This is that container.
  private var demos: some View {
    NavigationStack(path: takePath) {
      DemosListScreen(
        // Still stub rows: the storage decision is #61, and inventing a domain
        // model to feed a list would be that decision made in passing.
        demos: DemoListItem.sample,
        onOpen: { router.openTake(.demo(id: $0.id)) },
        onDelete: { _ in },  // #63
        onNewDemo: { router.openTake(.newDemo) }
      )
      .navigationDestination(for: TakeEntry.self) { entry in
        TakeScreen(
          state: model.binding,
          onCancel: leaveTake,
          onBack: leaveTake,
          onDone: leaveTake,
          onTransport: model.transport,
          onNoticeAction: model.perform,
          share: model.sharedTake
        )
        // The push is what starts a visit — the model outlives it, so nothing
        // here builds a recorder, a player or an engine.
        .onAppear { model.opened(as: entry) }
        // The design gives the Take screen its own leading control in every
        // mode — Cancel while capturing, `‹ Demos` on playback (§2's header
        // table). The system's chevron would be a second one, and it pops
        // without going through `leaveTake`, so capture would keep running
        // behind the list. Hiding it also takes the edge-swipe with it.
        .navigationBarBackButtonHidden(true)
      }
    }
  }

  /// The path `NavigationStack` writes through.
  ///
  /// Emptying it is a pop by any route, so it goes through the same
  /// ``leaveTake()`` the three header controls do — the router alone cannot do
  /// this, because quieting capture needs the model and routing does not know
  /// about it.
  private var takePath: Binding<[TakeEntry]> {
    Binding(
      get: { router.route.open },
      set: { entries in
        if entries.isEmpty {
          leaveTake()
        } else if let last = entries.last {
          router.openTake(last)
        }
      })
  }

  /// All three exits land in the same place. What each one *does to the take* —
  /// discard it, keep an edited title, keep a moved dial — is #64, and this
  /// ticket deliberately answers none of it.
  private func leaveTake() {
    model.leaveTake()
    router.closeTake()
  }

  @MainActor
  private static func makeModel() -> TakeScreenModel {
    // A share that was interrupted — the app killed, the phone out of space —
    // leaves a rendered copy in `tmp/`. Nothing processed is meant to survive a
    // launch, so the area is emptied before anything can read a stale render as
    // a cache hit. Cheap: it is one directory listing on a folder that is
    // usually empty.
    if let scratch = try? ShareScratch.directory(inTemporary: .temporaryDirectory) {
      ShareScratch.sweep(in: scratch)
    }

    return TakeScreenModel(capture: makeCaptureState(), exporter: TakeExporter())
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
      latestTake: RecordingsFolder.takes(in: folder).last,
      // The design's starting position for the dial — mid-scale, which the tone
      // bands name "Warm". A product default, so it belongs here at the
      // composition root rather than baked into the machine, which keeps 0 (true
      // bypass) as its own neutral starting point.
      warmth: 0.5)
  }
}
