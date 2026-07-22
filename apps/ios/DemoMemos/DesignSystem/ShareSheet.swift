import SwiftUI
import UIKit

/// The native share sheet over a file URL — the design's sheet is
/// `UIActivityViewController`, so this is it rather than a lookalike.
/// Used from the list's swipe action and from playback's share icon.
struct ShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file URL is not `Identifiable`, and `.sheet(item:)` needs one.
struct ShareTarget: Identifiable {
  let id = UUID()
  let url: URL
}
