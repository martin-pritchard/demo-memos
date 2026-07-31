import SwiftUI

/// Home: every take, with a swipe to share or delete one and a floating capsule
/// to start another.
///
/// **The chrome is all the system's.** The card, its radius, the inset dividers,
/// the 66pt row minimum, the large title, the swipe actions, the destructive
/// action sheet and the share sheet are `List { }.listStyle(.insetGrouped)`,
/// `.navigationTitle`, `.swipeActions`, `.confirmationDialog` and `ShareLink` —
/// the handoff asks for exactly that, and `DesignTokens.swift` records which
/// handoff number each one supplies. `DemoRow` draws what goes *inside* a row.
///
/// State in, events out. The list is handed its rows and reports what was tapped;
/// it stores nothing. `deleteTarget` is the one piece of state it does own, and
/// it is presentation — which dialog is up — rather than data.
///
/// **No `NavigationStack` here.** The large title is a `.navigationTitle`, so the
/// container supplies the stack — `DemoMemosApp` does, and a tapped row pushes
/// the Take screen onto it (#60). The rows themselves are still
/// `DemoListItem.sample`: what a real one is made of is #61.
struct DemosListScreen: View {

  let demos: [DemoListItem]

  var onOpen: (DemoListItem) -> Void = { _ in }
  var onDelete: (DemoListItem) -> Void = { _ in }
  var onNewDemo: () -> Void = {}

  /// Which row's delete is being confirmed, if any. `nil` is "no dialog".
  @State private var deleteTarget: DemoListItem?

  var body: some View {
    Group {
      if demos.isEmpty { emptyState } else { list }
    }
    .background(DesignTokens.Palette.pageBackground.ignoresSafeArea())
    .navigationTitle("Demos")
    .navigationBarTitleDisplayMode(.large)
    // The capsule floats over the content and the content clears it — which is
    // what a bottom safe-area inset means, rather than a hand-computed 120pt of
    // list padding.
    .safeAreaInset(edge: .bottom) { newDemoCapsule }
    .confirmationDialog(
      deleteTitle,
      isPresented: isConfirmingDelete,
      titleVisibility: .visible,
      presenting: deleteTarget
    ) { demo in
      // Cancel is the system's; `.confirmationDialog` adds it, and adding a
      // second one is how you end up with two.
      Button("Delete Recording", role: .destructive) { onDelete(demo) }
    }
  }

  // MARK: - List

  private var list: some View {
    List {
      Section {
        ForEach(demos) { demo in
          Button {
            onOpen(demo)
          } label: {
            DemoRow(name: demo.name, meta: demo.meta, duration: demo.duration)
          }
          .buttonStyle(.plain)
          // Declared edge-outwards: Delete lands furthest right, Share beside
          // it, which reads "Share ⃒ Delete" the way the design draws it.
          .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
              deleteTarget = demo
            }
            // The name stands in for the file — there is no take on disk to
            // point at until persistence lands.
            ShareLink(item: demo.name) {
              Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(DesignTokens.Palette.share)
          }
        }
      } footer: {
        Text("Swipe a demo to share")
          .font(DesignTokens.Typography.caption)
          .foregroundStyle(DesignTokens.Palette.textTertiary)
          .frame(maxWidth: .infinity)
          .multilineTextAlignment(.center)
      }
    }
    .listStyle(.insetGrouped)
    // The grouped background would otherwise sit over the page gradient.
    .scrollContentBackground(.hidden)
  }

  // MARK: - Empty

  /// The handoff's centred title-and-body block, with no illustration — which is
  /// `ContentUnavailableView` with its image slot left unfilled rather than a
  /// hand-built `VStack`. The capsule stays in place behind it.
  private var emptyState: some View {
    ContentUnavailableView {
      Text("Capture your first demo")
        .font(DesignTokens.Typography.screenTitle)
    } description: {
      Text(
        "Hit 'New Demo' to record an idea, shape it with Enhance, and share it anywhere."
      )
      .font(DesignTokens.Typography.secondaryBody)
    }
  }

  // MARK: - New Demo

  /// Accent over glass — `DesignTokens.swift` maps the handoff's
  /// `accent @ 0.9` over `blur(24px) saturate(1.6)`, its hairline and its shadow
  /// onto iOS 26's prominent glass button, which supplies all three.
  private var newDemoCapsule: some View {
    Button(action: onNewDemo) {
      Label("New Demo", systemImage: "mic.fill")
        .font(DesignTokens.Typography.featureTitle)
    }
    .buttonStyle(.glassProminent)
    .tint(DesignTokens.Palette.accent)
    .controlSize(.large)
    .padding(.bottom)
  }

  // MARK: - Delete confirmation

  private var deleteTitle: String {
    guard let name = deleteTarget?.name else { return "" }
    return "Delete \u{201C}\(name)\u{201D}? This can't be undone."
  }

  private var isConfirmingDelete: Binding<Bool> {
    Binding(
      get: { deleteTarget != nil },
      set: { if !$0 { deleteTarget = nil } }
    )
  }
}

// MARK: - Previews

/// Every state in `docs/design/screen-states.md` §3. The swiped-open row, the
/// mid-drag row and the share sheet are the system's own gestures over the
/// populated list rather than separate previews — there is no state to stub for
/// them, only a swipe to perform in the canvas.
private struct DemosPreview: View {

  let demos: [DemoListItem]

  var body: some View {
    NavigationStack {
      DemosListScreen(demos: demos)
    }
  }
}

#Preview("3.1 populated") { DemosPreview(demos: DemoListItem.sample) }
#Preview("3.2 empty") { DemosPreview(demos: DemoListItem.empty) }
#Preview("3.7 scrolled — content under the capsule") {
  DemosPreview(demos: DemoListItem.many)
}
#Preview("Long name, long take") { DemosPreview(demos: DemoListItem.awkward) }

#Preview("3.1 populated — dark") {
  DemosPreview(demos: DemoListItem.sample).preferredColorScheme(.dark)
}
#Preview("3.2 empty — dark") {
  DemosPreview(demos: DemoListItem.empty).preferredColorScheme(.dark)
}
