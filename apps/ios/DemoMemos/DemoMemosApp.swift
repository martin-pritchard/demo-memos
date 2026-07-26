//
//  DemoMemosApp.swift
//  DemoMemos
//
//  Created by Martin Pritchard on 22/07/2026.
//

import SwiftData
import SwiftUI

@main
struct DemoMemosApp: App {
  var body: some Scene {
    WindowGroup {
      RootView(services: .live())
    }
  }
}

/// The one place real services are constructed. Everything below takes them as
/// initialiser arguments; nothing reaches out for a singleton.
struct Services {
  let store: MemoStore
  let onboarding: UserDefaultsOnboardingStore
  let makeRecorder: () -> AudioRecorder
  let makePlayer: () -> AudioPlayer
  let makeCountInTicker: () -> CountInTicker

  static func live() -> Services {
    let container = try! ModelContainer(for: Memo.self)
    let directory = URL.documentsDirectory.appending(path: "Recordings")
    let store = SwiftDataMemoStore(modelContext: ModelContext(container), directory: directory)
    // A kill mid-record leaves a file with no index row. Clear it at startup
    // rather than letting it sit on disk forever.
    try? store.removeOrphanedFiles()
    return Services(
      store: store,
      onboarding: UserDefaultsOnboardingStore(),
      makeRecorder: { AVAudioRecorderAdapter() },
      makePlayer: { AVAudioPlayerAdapter() },
      makeCountInTicker: { SystemSoundCountInTicker() }
    )
  }
}

/// Routing: Demos → Record (a cover) and Demos → Playback (a push).
struct RootView: View {
  let services: Services

  @State private var listState: MemoListState
  @State private var captureState: CaptureState?
  @State private var playbackMemo: Memo?
  /// Read once at launch. Flipping it after Continue swaps the intro for the
  /// list; the flag itself is persisted through `services.onboarding`.
  @State private var hasOnboarded: Bool

  init(services: Services) {
    self.services = services
    _listState = State(initialValue: MemoListState(store: services.store))
    _hasOnboarded = State(initialValue: services.onboarding.hasOnboarded)
  }

  var body: some View {
    if hasOnboarded {
      mainFlow
    } else {
      OnboardingView {
        services.onboarding.markOnboarded()
        hasOnboarded = true
      }
    }
  }

  private var mainFlow: some View {
    NavigationStack {
      MemoListView(
        state: listState,
        onNewDemo: {
          captureState = CaptureState(
            store: services.store,
            recorder: services.makeRecorder(),
            player: services.makePlayer(),
            countInTicker: services.makeCountInTicker()
          )
        },
        onOpen: { playbackMemo = $0 }
      )
      .navigationDestination(item: $playbackMemo) { memo in
        // Pushed into this stack, so it gets the native "Demos" back button.
        CaptureView(
          state: CaptureState(
            memo: memo,
            store: services.store,
            recorder: services.makeRecorder(),
            player: services.makePlayer(),
            countInTicker: services.makeCountInTicker()
          ),
          createdAt: memo.createdAt,
          onFinish: {}
        )
      }
    }
    // The list reflects any rename / enhance change once playback is popped.
    .onChange(of: playbackMemo) { _, memo in
      if memo == nil { listState.load() }
    }
    .fullScreenCover(isPresented: isRecording) {
      if let captureState {
        // Its own stack, so Cancel / Done land in a real nav bar.
        NavigationStack {
          CaptureView(state: captureState, createdAt: .now) {
            self.captureState = nil
            listState.load()
          }
        }
      }
    }
  }

  private var isRecording: Binding<Bool> {
    Binding(
      get: { captureState != nil },
      set: { if !$0 { captureState = nil } }
    )
  }
}
