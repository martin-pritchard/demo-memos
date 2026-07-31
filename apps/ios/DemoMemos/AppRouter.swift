import Core
import Foundation
import SwiftUI

/// Where the app is, and the one thing that can move it.
///
/// Holds `Core`'s pure ``AppRoute`` and performs the single effect routing has:
/// writing `hasOnboarded`. Everything *decided* is in the value; this type only
/// stores, persists and republishes.
///
/// **Beside `DemoMemosApp` rather than in a feature folder.** Routing and
/// dependency wiring belong to the composition root (`docs/PRINCIPLES.md` #6),
/// and a router owned by one of the three screens would be a screen deciding
/// where the other two live.
@MainActor
@Observable
final class AppRouter {

  private(set) var route: AppRoute

  /// The flag's home. `UserDefaults` directly rather than behind a protocol with
  /// one implementation (`docs/PRINCIPLES.md` #8) — a suite is injectable on its
  /// own, so a test gets a scratch one without a seam being invented for it.
  ///
  /// This is the ticket's only persistence, and #59 says so in as many words:
  /// takes stay unpersisted until #61.
  private let defaults: UserDefaults

  private static let hasOnboardedKey = "hasOnboarded"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.route = AppRoute(hasOnboarded: defaults.bool(forKey: Self.hasOnboardedKey))
  }

  /// Continue was tapped.
  ///
  /// The write happens here rather than on arrival, which is what makes
  /// force-quitting *on* onboarding show it again: the flag records that the
  /// user finished it, not that they saw it.
  func onboardingCompleted() {
    defaults.set(true, forKey: Self.hasOnboardedKey)
    route.onboardingCompleted()
  }

  func openTake(_ entry: TakeEntry) {
    route.openTake(entry)
  }

  func closeTake() {
    route.closeTake()
  }

  /// The binding `NavigationStack` wants. Writing through it is the system
  /// telling us the user went back — a swipe or the header's chevron — which is
  /// the same event as any of the three exits, so it lands in the same place.
  var path: Binding<[TakeEntry]> {
    Binding(
      get: { self.route.open },
      set: { entries in
        if entries.isEmpty {
          self.route.closeTake()
        } else if let last = entries.last {
          self.route.openTake(last)
        }
      })
  }
}
