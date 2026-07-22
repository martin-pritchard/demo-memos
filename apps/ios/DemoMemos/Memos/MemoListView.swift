import SwiftUI

/// 1a / 2a / 4a — Demos. A plain list of takes: name, when, length, newest
/// first. Swipe a row left for Share / Delete. The New Demo pill floats over
/// the list and stays in place when there is nothing to show yet (4a).
struct MemoListView: View {
  @Bindable var state: MemoListState
  let onNewDemo: () -> Void
  let onOpen: (Memo) -> Void

  var body: some View {
    ZStack(alignment: .bottom) {
      Palette.pageBackground.ignoresSafeArea()

      VStack(alignment: .leading, spacing: 0) {
        Text("Demos")
          .font(.system(size: 34, weight: .bold))
          // The design's 64pt is measured from the top of the screen, where its
          // status bar is absolutely positioned. That is the safe-area inset,
          // which SwiftUI has already applied — so nothing to add here.
          .padding(.horizontal, 20)
          .padding(.bottom, 12)

        if state.isEmpty {
          emptyState
        } else {
          list
        }
      }

      newDemoPill
    }
    .onAppear { state.load() }
    .sheet(item: $state.shareTarget) { ShareSheet(url: $0.url) }
  }

  // MARK: - 4a

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text("Capture your first demo")
        .font(.system(size: 22, weight: .bold))
      Text("Hit ‘New Demo’ to record an idea, shape it with Enhance, and share it anywhere.")
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
    }
    .frame(maxWidth: 252)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .offset(y: -20)
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
          .font(.system(size: 12.5))
          .foregroundStyle(Color(.tertiaryLabel))
          .frame(maxWidth: .infinity)
          .padding(.top, 6)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .scrollIndicators(.hidden)
    .contentMargins(.bottom, 110, for: .scrollContent)
  }

  private func row(for memo: Memo) -> some View {
    Button {
      onOpen(memo)
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(memo.name)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(memo.createdAt.listMetaLabel)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Text(memo.duration.shortTimeLabel)
          .font(.system(size: 15))
          .monospacedDigit()
          .foregroundStyle(Color(.tertiaryLabel))
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
      Button {
        state.share(memo)
      } label: {
        Label("Share", systemImage: "square.and.arrow.up")
      }
      .tint(.blue)
    }
  }

  // MARK: - The pill

  private var newDemoPill: some View {
    Button(action: onNewDemo) {
      HStack(spacing: 9) {
        Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold))
        Text("New Demo").font(.system(size: 16, weight: .semibold))
      }
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
  MemoListView(
    state: MemoListState(store: PreviewScenario.populatedStore), onNewDemo: {}, onOpen: { _ in }
  )
}

#Preview("2a · populated (dark)") {
  MemoListView(
    state: MemoListState(store: PreviewScenario.populatedStore), onNewDemo: {}, onOpen: { _ in }
  )
  .preferredColorScheme(.dark)
}

#Preview("4a · empty") {
  MemoListView(
    state: MemoListState(store: PreviewScenario.emptyStore), onNewDemo: {}, onOpen: { _ in }
  )
}
