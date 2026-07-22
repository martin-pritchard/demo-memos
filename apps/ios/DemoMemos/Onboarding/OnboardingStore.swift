import Foundation

/// Whether the one-time first-launch intro (design 5a) has been dismissed. A
/// single persisted flag, backed by `UserDefaults` — the native home for a
/// launch-scoped boolean (the memo index is SwiftData's job; this is not). False
/// on a fresh install so the intro shows; true for good once the user taps
/// Continue. A deleted app takes its defaults with it, so reinstalling shows the
/// intro again.
///
/// The `UserDefaults` is injected rather than reached for, so tests and previews
/// run against an isolated suite instead of `.standard`.
final class UserDefaultsOnboardingStore {
  private static let key = "hasOnboarded"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// False until onboarding has been completed at least once.
  var hasOnboarded: Bool {
    defaults.bool(forKey: Self.key)
  }

  /// Records that onboarding is complete. Persists immediately; never shows again.
  func markOnboarded() {
    defaults.set(true, forKey: Self.key)
  }
}
