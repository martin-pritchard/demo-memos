import Core
import Foundation
import Testing

@testable import DemoMemos

/// The parts of #60's route shell that are not `Core`'s pure `AppRoute`: the
/// flag's persistence, leaving a take, and the one transport rule holding over
/// a row that names no audio.
///
/// Runs entirely on the fakes and a scratch `UserDefaults` — no session, no
/// microphone, no files, and nothing written to the real defaults.

// MARK: - The onboarding flag

@MainActor
@Suite("hasOnboarded is written when onboarding is finished, not when it is seen")
struct AppRouterFlagTests {

  /// A defaults suite of its own per test, so one test cannot see another's
  /// flag and none of them touch `.standard`.
  private static func scratch(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "route-shell-\(name)")!
    defaults.removePersistentDomain(forName: "route-shell-\(name)")
    return defaults
  }

  @Test("starts at onboarding when the flag has never been written")
  func startsAtOnboardingWhenTheFlagHasNeverBeenWritten() {
    let router = AppRouter(defaults: Self.scratch(#function))

    #expect(router.route.root == .onboarding)
  }

  @Test("merely reaching onboarding writes nothing — a force-quit shows it again")
  func merelyReachingOnboardingWritesNothing() {
    let defaults = Self.scratch(#function)
    _ = AppRouter(defaults: defaults)

    // The whole point of writing on Continue rather than on arrival: a second
    // launch after quitting mid-onboarding must land back at onboarding.
    #expect(AppRouter(defaults: defaults).route.root == .onboarding)
  }

  @Test("finishing onboarding moves to the list and survives the next launch")
  func finishingOnboardingMovesToTheListAndSurvivesTheNextLaunch() {
    let defaults = Self.scratch(#function)
    let router = AppRouter(defaults: defaults)

    router.onboardingCompleted()

    #expect(router.route.root == .demos)
    #expect(AppRouter(defaults: defaults).route.root == .demos)
  }
}

// MARK: - Leaving a take

@MainActor
@Suite("Leaving the Take screen leaves nothing running behind the list")
struct LeaveTakeTests {

  private static func make(latestTake: URL? = nil) -> (TakeScreenModel, CaptureState) {
    let capture = CaptureState(
      recorder: FakeRecorder(permission: .granted),
      player: FakePlayer(),
      folder: URL.temporaryDirectory.appending(path: "Recordings"),
      latestTake: latestTake)
    return (TakeScreenModel(capture: capture, exporter: FakeExporter()), capture)
  }

  @Test("stops a recording that is still rolling")
  func stopsARecordingThatIsStillRolling() async {
    let (model, capture) = Self.make()
    await capture.recordTapped()
    #expect(capture.mode == .recording)

    model.leaveTake()
    // `recordTapped` is async on the capture side; the exit uses the same path
    // the Stop button does, so it settles the same way.
    await Task.yield()
    try? await Task.sleep(for: .milliseconds(50))

    #expect(capture.mode != .recording)
  }

  @Test("stops playback that is still running")
  func stopsPlaybackThatIsStillRunning() {
    let take = URL(filePath: "/tmp/route-shell-take.wav")
    let (model, capture) = Self.make(latestTake: take)
    capture.playTapped()
    #expect(capture.mode == .playing)

    model.leaveTake()

    #expect(capture.mode != .playing)
  }

  @Test("leaving an idle screen changes nothing")
  func leavingAnIdleScreenChangesNothing() {
    let (model, capture) = Self.make()

    model.leaveTake()

    #expect(capture.mode == .idle)
  }
}

// MARK: - A visit

@MainActor
@Suite("Opening the Take screen starts a visit")
struct OpenedAsTests {

  private static func make(latestTake: URL? = nil) -> TakeScreenModel {
    TakeScreenModel(
      capture: CaptureState(
        recorder: FakeRecorder(permission: .granted),
        player: FakePlayer(),
        folder: URL.temporaryDirectory.appending(path: "Recordings"),
        latestTake: latestTake),
      exporter: FakeExporter())
  }

  /// The bug #60 fixes, at the level the user meets it: a take on disk used to
  /// decide the mode, so New Demo opened onto a take nobody made this visit.
  @Test("New Demo opens ready even with a take already on disk")
  func newDemoOpensReadyEvenWithATakeAlreadyOnDisk() {
    let model = Self.make(latestTake: URL(filePath: "/tmp/an-older-take.wav"))

    model.opened(as: .newDemo)

    #expect(model.state.mode == .ready)
    #expect(model.state.elapsed == 0)
  }

  @Test("a row opens in playback")
  func aRowOpensInPlayback() {
    let model = Self.make(latestTake: URL(filePath: "/tmp/an-older-take.wav"))

    model.opened(as: .demo(id: UUID()))

    #expect(model.state.mode == .playback)
  }

  /// The one transport rule (`#16f`): never enabled-and-inert. The list is stub
  /// rows until #61, so a row can name a take that was never recorded.
  @Test("a row with no audio behind it opens with Play dim, not enabled and inert")
  func aRowWithNoAudioBehindItOpensWithPlayDim() {
    let model = Self.make(latestTake: nil)

    model.opened(as: .demo(id: UUID()))

    #expect(model.state.mode == .playback)
    #expect(model.state.presentation.isLeftEnabled == false)
  }

  @Test("a row with audio behind it opens with Play live")
  func aRowWithAudioBehindItOpensWithPlayLive() {
    let model = Self.make(latestTake: URL(filePath: "/tmp/an-older-take.wav"))

    model.opened(as: .demo(id: UUID()))

    #expect(model.state.presentation.isLeftEnabled)
  }
}
