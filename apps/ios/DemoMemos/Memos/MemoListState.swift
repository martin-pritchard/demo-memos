import Foundation

/// 1a / 4a. Loads the index, deletes rows (and their audio with them), and
/// resolves the file URL a share action needs.
@MainActor
@Observable
final class MemoListState {
  private(set) var memos: [Memo] = []
  private(set) var errorMessage: String?
  var shareTarget: ShareTarget?

  private let store: MemoStore

  init(store: MemoStore) {
    self.store = store
  }

  var isEmpty: Bool { memos.isEmpty }

  func load() {
    do {
      memos = try store.memos()
      errorMessage = nil
    } catch {
      memos = []
      errorMessage = "Couldn't load your demos."
    }
  }

  /// Immediate, no confirmation — undo is out of scope.
  func delete(_ memo: Memo) {
    do {
      try store.delete(memo)
      memos.removeAll { $0 === memo }
    } catch {
      errorMessage = "Couldn't delete that demo."
    }
  }

  func share(_ memo: Memo) {
    shareTarget = ShareTarget(url: store.fileURL(for: memo))
  }
}
