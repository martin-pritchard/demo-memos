import Foundation

/// Which take the Take screen was opened for.
///
/// The identifier is opaque on purpose. Today it is a stub `DemoListItem.id`;
/// when #61 gives the list a real `Demo`, the route keeps its shape and only the
/// thing minting the `UUID` changes.
public enum TakeEntry: Hashable, Sendable {

  /// The New Demo capsule — the Take screen opens ready to capture.
  case newDemo

  /// A row in the Demos list — the Take screen opens on that take.
  case demo(id: UUID)
}

/// Where the app is: which screen is at the base, and what is pushed over it.
///
/// A value rather than a scatter of `@State` flags, and in `Core` rather than
/// the app target, so the whole of "where can you get to from here" is decided
/// under `swift test` with no simulator (`docs/PRINCIPLES.md` #3).
///
/// **Not a reducer.** `CaptureMachine` earns `next(state, event) -> (State,
/// [Effect])` because a transport transition fans out into recorder and player
/// work. Routing has exactly one effect — writing `hasOnboarded` — and that is
/// the composition root's to perform, so the ceremony would not pay for itself
/// here.
public struct AppRoute: Equatable, Sendable {

  /// The screen at the base of the app. `.onboarding` only until it is completed
  /// once, ever.
  public enum Root: Equatable, Sendable {
    case onboarding
    case demos
  }

  public private(set) var root: Root

  /// The stack above ``root``, and **at most one deep**. The Take screen is the
  /// only destination there is, and two rows must not be able to stack two of
  /// them — so opening while one is open replaces rather than pushes.
  public private(set) var open: [TakeEntry]

  public init(hasOnboarded: Bool) {
    self.root = hasOnboarded ? .demos : .onboarding
    self.open = []
  }

  /// Continue was tapped. Idempotent: onboarding is a one-way door, and arriving
  /// at it a second time is a bug rather than a state to model.
  public mutating func onboardingCompleted() {
    root = .demos
  }

  /// Push the Take screen, or swap what it is showing if it is already up.
  public mutating func openTake(_ entry: TakeEntry) {
    open = [entry]
  }

  /// Back to the list — whichever exit was used. `‹ Demos`, Cancel and Done all
  /// land here; what each *does to the take* is #64, and deliberately not a
  /// distinction the route draws.
  public mutating func closeTake() {
    open = []
  }
}
