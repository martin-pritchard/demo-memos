import Foundation
import Testing

@testable import DemoMemos

@Suite("OnboardingStore")
struct OnboardingStoreTests {
  @Test("given a fresh install, when the flag is read, then it is false")
  func freshInstallReadsFalse() {
    let suiteName = "OnboardingStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsOnboardingStore(defaults: defaults)

    #expect(store.hasOnboarded == false)
  }

  @Test("given a fresh store, when markOnboarded is called, then the flag reads true")
  func markOnboardedReadsTrue() {
    let suiteName = "OnboardingStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsOnboardingStore(defaults: defaults)
    store.markOnboarded()

    #expect(store.hasOnboarded == true)
  }

  @Test(
    "given onboarding was marked, when a new store reads the same defaults, then the flag survives relaunch"
  )
  func flagPersistsAcrossRelaunch() {
    let suiteName = "OnboardingStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    UserDefaultsOnboardingStore(defaults: defaults).markOnboarded()

    let relaunched = UserDefaultsOnboardingStore(defaults: defaults)

    #expect(relaunched.hasOnboarded == true)
  }

  @Test("given a different cleared defaults, when the flag is read, then it is false again")
  func flagAbsentAfterReinstall() {
    let onboardedSuite = "OnboardingStoreTests.\(UUID().uuidString)"
    let onboardedDefaults = UserDefaults(suiteName: onboardedSuite)!
    defer { onboardedDefaults.removePersistentDomain(forName: onboardedSuite) }
    UserDefaultsOnboardingStore(defaults: onboardedDefaults).markOnboarded()

    let freshSuite = "OnboardingStoreTests.\(UUID().uuidString)"
    let freshDefaults = UserDefaults(suiteName: freshSuite)!
    defer { freshDefaults.removePersistentDomain(forName: freshSuite) }

    let store = UserDefaultsOnboardingStore(defaults: freshDefaults)

    #expect(store.hasOnboarded == false)
  }

  @Test(
    "given onboarding was already marked, when markOnboarded is called again, then the flag stays true"
  )
  func markOnboardedIsIdempotent() {
    let suiteName = "OnboardingStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsOnboardingStore(defaults: defaults)
    store.markOnboarded()
    store.markOnboarded()

    #expect(store.hasOnboarded == true)
  }
}
