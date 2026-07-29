import Foundation

/// One row's worth of the Demos list.
///
/// **Stub state, not a domain model.** The meta line and the duration arrive
/// already formatted, exactly as `DemoRow` takes them: there is no `Demo` type
/// yet, and take persistence is a seam this ticket defers. Inventing the model
/// here to feed a list would be that decision made in passing.
///
/// The `enhanced: Bool` the prototype's seed data carries is deliberately absent
/// — `screen-states.md` flags it as a field nothing draws, and it needs a
/// decision before it reaches any model.
struct DemoListItem: Identifiable, Equatable {

  let id = UUID()

  let name: String

  /// Already formatted — "Today · 3:14 PM", "Yesterday", "Monday".
  let meta: String

  /// Already formatted — "0:37".
  let duration: String
}

// MARK: - Scenarios

/// Named lists covering every state `screen-states.md` §3 draws.
///
/// They hang off the element type rather than off `[DemoListItem]` because a
/// static stored property cannot live in an extension of a generic type, and
/// `Array` is one.
extension DemoListItem {

  /// The handoff's own sample list (`docs/design/README.md` § Demos).
  static let sample: [DemoListItem] = [
    DemoListItem(name: "New Demo 3", meta: "Today · 3:14 PM", duration: "0:37"),
    DemoListItem(name: "Chorus — fast", meta: "Today · 11:02 AM", duration: "0:21"),
    DemoListItem(name: "Bridge hum", meta: "Yesterday", duration: "1:12"),
    DemoListItem(name: "Verse idea 2", meta: "Monday", duration: "0:48"),
    DemoListItem(name: "Riff in D", meta: "Sunday", duration: "0:15"),
  ]

  /// First launch, nothing captured. The empty state is a real state, not the
  /// absence of one.
  static let empty: [DemoListItem] = []

  /// Long enough to scroll under the capsule, which is state 3.7.
  static let many: [DemoListItem] = (0..<24).map { index in
    DemoListItem(
      name: "New Demo \(index + 1)",
      meta: index < 3 ? "Today · 3:14 PM" : "Monday",
      duration: "0:\(String(format: "%02d", 12 + index * 2))"
    )
  }

  /// The two cases the handoff does not draw: a name long enough to truncate,
  /// and a take past ten minutes.
  static let awkward: [DemoListItem] = [
    DemoListItem(
      name: "A working title far too long to fit on one line",
      meta: "Today · 9:41 AM",
      duration: "12:04"
    ),
    DemoListItem(name: "Riff in D", meta: "Sunday", duration: "0:15"),
  ]
}
