import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// What the header's Share button hands to the system sheet: not a file, a
/// **promise** of one.
///
/// Design turn `#17` is FINAL that the sheet opens on the tap rather than after
/// the render — "what they wanted (send this to Dan) is knowable now, while the
/// render is still running". An async `FileRepresentation` is exactly the
/// `UIActivityItemProvider` the design names, in the form `ShareLink` takes: the
/// sheet is up from the first frame, every destination live, and the render only
/// has to have finished by the time a destination has been chosen.
///
/// The render itself is `TakeExporter`'s, so this type carries no audio and no
/// file handling — only the four values that identify *which* render, and
/// somewhere to report a failure that the system sheet would otherwise swallow.
struct SharedTake: Transferable {

  /// The dry capture. Never modified — the render reads it and writes elsewhere.
  let take: URL

  /// The dial position to render at, which is also half the cache key: share the
  /// same take twice without touching Enhance and the second one is free.
  let warmth: Double

  /// The demo's name. Becomes the file name the recipient sees.
  let name: String

  let exporter: any Exporting

  /// Called when the render fails, so the screen can put a line in its slot.
  /// The system's own error UI says only that sharing failed; `#17e` wants
  /// "Couldn’t prepare this demo" with a way back.
  let onFailure: @Sendable () -> Void

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .mpeg4Audio) { shared in
      do {
        let url = try await shared.exporter.rendered(
          take: shared.take, warmth: shared.warmth, named: shared.name)
        return SentTransferredFile(url)
      } catch is CancellationError {
        // The user dismissed the sheet or the system gave up on us. `#17e`:
        // "you asked for it to stop and it stopped" — nothing is said afterwards.
        throw CancellationError()
      } catch {
        shared.onFailure()
        throw error
      }
    }
  }
}
