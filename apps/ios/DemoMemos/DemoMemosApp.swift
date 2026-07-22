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
  let makeRecorder: () -> AudioRecorder
  let makePlayer: () -> AudioPlayer

  static func live() -> Services {
    let container = try! ModelContainer(for: Memo.self)
    let directory = URL.documentsDirectory.appending(path: "Recordings")
    let store = SwiftDataMemoStore(modelContext: ModelContext(container), directory: directory)
    // A kill mid-record leaves a file with no index row. Clear it at startup
    // rather than letting it sit on disk forever.
    try? store.removeOrphanedFiles()
    return Services(
      store: store,
      makeRecorder: { AVAudioRecorderAdapter() },
      makePlayer: { AVAudioPlayerAdapter() }
    )
  }
}

/// Routing: Demos → Record (a cover) and Demos → Playback (a push).
struct RootView: View {
  let services: Services

  @State private var listState: MemoListState
  @State private var captureState: CaptureState?
  @State private var playbackMemo: Memo?

  init(services: Services) {
    self.services = services
    _listState = State(initialValue: MemoListState(store: services.store))
  }

  var body: some View {
    NavigationStack {
      MemoListView(
        state: listState,
        onNewDemo: {
          captureState = CaptureState(
            store: services.store,
            recorder: services.makeRecorder(),
            player: services.makePlayer()
          )
        },
        onOpen: { playbackMemo = $0 }
      )
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(item: $playbackMemo) { memo in
        CaptureView(
          state: CaptureState(
            memo: memo,
            store: services.store,
            recorder: services.makeRecorder(),
            player: services.makePlayer()
          ),
          createdAt: memo.createdAt,
          onFinish: {
            playbackMemo = nil
            listState.load()
          }
        )
        .toolbar(.hidden, for: .navigationBar)
      }
    }
    .fullScreenCover(isPresented: isRecording) {
      if let captureState {
        CaptureView(state: captureState, createdAt: .now) {
          self.captureState = nil
          listState.load()
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
