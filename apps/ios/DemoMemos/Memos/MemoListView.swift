import SwiftUI

/// 1a / 2a / 4a — Demos. A plain list of takes: name, when, length, newest
/// first. Swipe a row left for Share / Delete. The New Demo pill floats over
/// the list and stays in place when there is nothing to show yet (4a).
///
/// Chrome is the system's: a real large-title nav bar, a standard `List` with
/// native swipe actions, `ShareLink`, and `ContentUnavailableView` for empty.
struct MemoListView: View {
  @Bindable var state: MemoListState
  let onNewDemo: () -> Void
  let onOpen: (Memo) -> Void

  var body: some View {
    ZStack(alignment: .bottom) {
      Palette.pageBackground.ignoresSafeArea()

      if state.isEmpty {
        emptyState
      } else {
        list
      }

      newDemoPill
    }
    .navigationTitle("Demos")
    .onAppear { state.load() }
  }

  // MARK: - 4a

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Capture your first demo", systemImage: "waveform")
    } description: {
      Text("Hit ‘New Demo’ to record an idea, shape it with Enhance, and share it anywhere.")
    }
  }

  // MARK: - 1a

  /// A `List` rather than a hand-rolled stack: Share / Delete are the standard
  /// iOS row actions, and those only exist here.
  private var list: some View {
    List {
      Section {
        ForEach(state.memos, id: \.id) { memo in
          row(for: memo)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Palette.card)
        }
      } footer: {
        Text("Swipe a demo to share")
          .font(.footnote)
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity)
          .padding(.top, 6)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .contentMargins(.bottom, 110, for: .scrollContent)
  }

  private func row(for memo: Memo) -> some View {
    Button {
      onOpen(memo)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(memo.name)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(memo.createdAt.listMetaLabel)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Text(memo.duration.shortTimeLabel)
          .font(.subheadline)
          .monospacedDigit()
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 66)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        state.delete(memo)
      } label: {
        Label("Delete", systemImage: "trash")
      }
      ShareLink(item: state.fileURL(for: memo)) {
        Label("Share", systemImage: "square.and.arrow.up")
      }
      .tint(.blue)
    }
  }

  // MARK: - The pill

  private var newDemoPill: some View {
    Button(action: onNewDemo) {
      Label("New Demo", systemImage: "mic.fill")
        .font(.headline)
        .foregroundStyle(.white)
        .padding(.vertical, 13)
        .padding(.horizontal, 24)
        .background(Palette.accent.opacity(0.9), in: .capsule)
        .shadow(color: Palette.accent.opacity(0.35), radius: 12, y: 8)
    }
    .padding(.bottom, 40)
  }
}

#Preview("1a · populated") {
  NavigationStack {
    MemoListView(
      state: MemoListState(store: PreviewScenario.populatedStore), onNewDemo: {}, onOpen: { _ in }
    )
  }
}

#Preview("2a · populated (dark)") {
  NavigationStack {
    MemoListView(
      state: MemoListState(store: PreviewScenario.populatedStore), onNewDemo: {}, onOpen: { _ in }
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("4a · empty") {
  NavigationStack {
    MemoListView(
      state: MemoListState(store: PreviewScenario.emptyStore), onNewDemo: {}, onOpen: { _ in }
    )
  }
}
