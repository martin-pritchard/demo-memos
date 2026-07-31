import Foundation
import Testing

@testable import Core

private let firstDemoID = UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!
private let secondDemoID = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")!

@Suite("AppRoute: initial state")
struct AppRouteInitialStateTests {

  @Test func initialisingWithoutHavingOnboardedStartsAtOnboardingWithNothingOpen() {
    let route = AppRoute(hasOnboarded: false)

    #expect(route.root == .onboarding)
    #expect(route.open == [])
  }

  @Test func initialisingHavingOnboardedStartsAtDemosWithNothingOpen() {
    let route = AppRoute(hasOnboarded: true)

    #expect(route.root == .demos)
    #expect(route.open == [])
  }
}

@Suite("AppRoute: completing onboarding")
struct AppRouteOnboardingCompletedTests {

  @Test func completingOnboardingMovesTheRootToDemos() {
    var route = AppRoute(hasOnboarded: false)

    route.onboardingCompleted()

    #expect(route.root == .demos)
  }

  @Test func completingOnboardingWhenAlreadyAtDemosLeavesTheRouteUnchanged() {
    var route = AppRoute(hasOnboarded: true)
    let before = route

    route.onboardingCompleted()

    #expect(route == before)
  }

  @Test func completingOnboardingTwiceIsTheSameAsCompletingItOnce() {
    var once = AppRoute(hasOnboarded: false)
    once.onboardingCompleted()

    var twice = AppRoute(hasOnboarded: false)
    twice.onboardingCompleted()
    twice.onboardingCompleted()

    #expect(twice == once)
  }

  @Test func completingOnboardingLeavesAnOpenTakeInPlace() {
    var route = AppRoute(hasOnboarded: false)
    route.openTake(.newDemo)

    route.onboardingCompleted()

    #expect(route.open == [.newDemo])
  }

  @Test func completingOnboardingLeavesAnEmptyPathEmpty() {
    var route = AppRoute(hasOnboarded: false)

    route.onboardingCompleted()

    #expect(route.open == [])
  }
}

@Suite("AppRoute: opening a take")
struct AppRouteOpenTakeTests {

  @Test func openingANewDemoPutsItOnThePath() {
    var route = AppRoute(hasOnboarded: true)

    route.openTake(.newDemo)

    #expect(route.open == [.newDemo])
  }

  @Test func openingADemoPutsThatSameDemoOnThePath() {
    var route = AppRoute(hasOnboarded: true)

    route.openTake(.demo(id: firstDemoID))

    #expect(route.open == [.demo(id: firstDemoID)])
  }

  @Test func openingASecondDemoReplacesTheFirstRatherThanStackingOnIt() {
    var route = AppRoute(hasOnboarded: true)
    route.openTake(.demo(id: firstDemoID))

    route.openTake(.demo(id: secondDemoID))

    #expect(route.open.count == 1)
    #expect(route.open == [.demo(id: secondDemoID)])
  }

  @Test func openingADemoOverANewDemoReplacesIt() {
    var route = AppRoute(hasOnboarded: true)
    route.openTake(.newDemo)

    route.openTake(.demo(id: firstDemoID))

    #expect(route.open == [.demo(id: firstDemoID)])
  }

  @Test func openingTheSameDemoTwiceStillLeavesOneTakeOpen() {
    var route = AppRoute(hasOnboarded: true)
    route.openTake(.demo(id: firstDemoID))

    route.openTake(.demo(id: firstDemoID))

    #expect(route.open == [.demo(id: firstDemoID)])
  }

  @Test func openingATakeLeavesTheRootAtDemos() {
    var route = AppRoute(hasOnboarded: true)

    route.openTake(.newDemo)

    #expect(route.root == .demos)
  }

  @Test func openingATakeWhileOnboardingLeavesTheRootAtOnboarding() {
    var route = AppRoute(hasOnboarded: false)

    route.openTake(.demo(id: firstDemoID))

    #expect(route.root == .onboarding)
  }
}

@Suite("AppRoute: closing a take")
struct AppRouteCloseTakeTests {

  @Test func closingATakeEmptiesThePath() {
    var route = AppRoute(hasOnboarded: true)
    route.openTake(.newDemo)

    route.closeTake()

    #expect(route.open == [])
  }

  @Test func closingAnOpenDemoEmptiesThePath() {
    var route = AppRoute(hasOnboarded: true)
    route.openTake(.demo(id: firstDemoID))

    route.closeTake()

    #expect(route.open == [])
  }

  @Test func closingWhenNothingIsOpenLeavesTheRouteUnchanged() {
    var route = AppRoute(hasOnboarded: true)
    let before = route

    route.closeTake()

    #expect(route == before)
  }

  @Test func closingATakeLeavesTheRootAtDemos() {
    var route = AppRoute(hasOnboarded: true)
    route.openTake(.newDemo)

    route.closeTake()

    #expect(route.root == .demos)
  }

  @Test func closingATakeWhileOnboardingLeavesTheRootAtOnboarding() {
    var route = AppRoute(hasOnboarded: false)
    route.openTake(.newDemo)

    route.closeTake()

    #expect(route.root == .onboarding)
  }
}

@Suite("AppRoute: equality")
struct AppRouteEqualityTests {

  @Test func routesBuiltTheSameWayCompareEqual() {
    var one = AppRoute(hasOnboarded: true)
    var other = AppRoute(hasOnboarded: true)

    one.openTake(.demo(id: firstDemoID))
    other.openTake(.demo(id: firstDemoID))

    #expect(one == other)
  }

  @Test func freshRoutesWithTheSameOnboardingFlagCompareEqual() {
    #expect(AppRoute(hasOnboarded: false) == AppRoute(hasOnboarded: false))
  }

  @Test func routesDifferingInRootCompareUnequal() {
    #expect(AppRoute(hasOnboarded: false) != AppRoute(hasOnboarded: true))
  }

  @Test func routesDifferingInWhatIsOpenCompareUnequal() {
    var opened = AppRoute(hasOnboarded: true)
    opened.openTake(.newDemo)

    #expect(opened != AppRoute(hasOnboarded: true))
  }

  @Test func routesOpenToDifferentDemosCompareUnequal() {
    var one = AppRoute(hasOnboarded: true)
    var other = AppRoute(hasOnboarded: true)

    one.openTake(.demo(id: firstDemoID))
    other.openTake(.demo(id: secondDemoID))

    #expect(one != other)
  }
}

@Suite("TakeEntry: identity")
struct TakeEntryIdentityTests {

  @Test func demosWithTheSameIdentifierAreEqual() {
    #expect(TakeEntry.demo(id: firstDemoID) == TakeEntry.demo(id: firstDemoID))
  }

  @Test func demosWithTheSameIdentifierHashTheSame() {
    #expect(
      TakeEntry.demo(id: firstDemoID).hashValue == TakeEntry.demo(id: firstDemoID).hashValue
    )
  }

  @Test func demosWithDifferentIdentifiersAreNotEqual() {
    #expect(TakeEntry.demo(id: firstDemoID) != TakeEntry.demo(id: secondDemoID))
  }

  @Test func newDemoIsNotEqualToAnyDemo() {
    #expect(TakeEntry.newDemo != TakeEntry.demo(id: firstDemoID))
    #expect(TakeEntry.newDemo != TakeEntry.demo(id: secondDemoID))
  }

  @Test func newDemoIsEqualToItself() {
    #expect(TakeEntry.newDemo == TakeEntry.newDemo)
  }

  @Test func aSetHoldsOneEntryPerDistinctTake() {
    let entries: Set<TakeEntry> = [
      .newDemo,
      .newDemo,
      .demo(id: firstDemoID),
      .demo(id: firstDemoID),
      .demo(id: secondDemoID),
    ]

    #expect(entries.count == 3)
  }
}
