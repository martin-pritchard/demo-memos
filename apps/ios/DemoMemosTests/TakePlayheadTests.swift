import Core
import Foundation
import Testing

@testable import DemoMemos

/// Regressions for the playhead's lifecycle across takes.
///
/// The bug these pin was one thing wearing three faces: the player's playhead
/// outlives the graph on purpose, so *whose* playhead it is has to be tracked as
/// carefully as where it points. Before this, a freshly recorded take inherited
/// the previous take's length and position, and a scrub made before a take's
/// first play was thrown away.
///
/// Runs entirely on the fakes: no session, no microphone, no files.
@MainActor
@Suite("The playhead belongs to exactly one take")
struct TakePlayheadTests {

  private static let otherTake = URL(filePath: "/tmp/some-other-take.wav")

  /// A hand-wound clock, so elapsed time is arithmetic rather than a wait.
  private final class Clock {
    private var instant = Date(timeIntervalSince1970: 1_785_000_000)
    var now: @Sendable () -> Date { { self.instant } }
    func advance(by seconds: TimeInterval) { instant += seconds }
  }

  private static func make(
    latestTake: URL? = nil,
    clock: Clock = Clock()
  ) -> (CaptureState, FakePlayer, Clock) {
    let player = FakePlayer()
    let state = CaptureState(
      recorder: FakeRecorder(permission: .granted),
      player: player,
      folder: URL.temporaryDirectory.appending(path: "Recordings"),
      latestTake: latestTake,
      now: clock.now)
    return (state, player, clock)
  }

  // MARK: - Whose playhead is it

  @Test("reports no length for a take the player has never seen")
  func reportsNoLengthForATakeThePlayerHasNeverSeen() {
    let take = URL(filePath: "/tmp/recorded.wav")
    let (state, player, _) = Self.make(latestTake: take)
    // The player is holding some other take's numbers.
    player.duration = 30

    #expect(state.duration == 0)
    #expect(state.position == 0)
  }

  @Test("does not lend one take's length to the next one")
  func doesNotLendOneTakesLengthToTheNextOne() async throws {
    let (state, player, _) = Self.make(latestTake: Self.otherTake)
    player.duration = 30
    try player.play(Self.otherTake)
    #expect(state.duration == 30, "the take the player is holding does have a length")

    // Record a new take. The player still holds the old one's numbers.
    await state.recordTapped()
    await state.recordTapped()

    #expect(state.latestTake != Self.otherTake)
    #expect(state.duration == 0, "the new take must not inherit the old one's 30 seconds")
    #expect(state.position == 0)
  }

  // MARK: - Scrubbing before a first play

  @Test("remembers a scrub made before the take has ever been played")
  func remembersAScrubMadeBeforeTheTakeHasEverBeenPlayed() async {
    let (state, player, _) = Self.make()
    await state.recordTapped()
    await state.recordTapped()

    // Nothing is decoded, so the player knows no length. The scrub must survive
    // rather than be clamped to zero against a length of zero.
    state.scrub(to: 15)

    #expect(player.position == 15)
    #expect(player.loadedTake == state.latestTake)
  }

  @Test("starts the next play from where the take was scrubbed to")
  func startsTheNextPlayFromWhereTheTakeWasScrubbedTo() async throws {
    let (state, player, _) = Self.make()
    await state.recordTapped()
    await state.recordTapped()
    state.scrub(to: 15)
    player.duration = 30

    state.playTapped()

    #expect(player.position == 15, "remembering the scrub is the whole point of keeping it")
  }

  // MARK: - The tick

  @Test("parks a freshly stopped take's playhead at its end")
  func parksAFreshlyStoppedTakesPlayheadAtItsEnd() async {
    let clock = Clock()
    let (state, _, _) = Self.make(clock: clock)
    let model = TakeScreenModel(capture: state, now: clock.now)

    await state.recordTapped()
    model.advance()
    clock.advance(by: 10)
    model.advance()
    await state.recordTapped()
    model.advance()

    #expect(model.takeDuration == 10)
    #expect(model.playhead == 10, "§4.4 opens a stopped take with its playhead at the end")
    #expect(model.state.progress == 1)
  }

  @Test("clears the previous take's length and playhead when a new one starts")
  func clearsThePreviousTakesLengthAndPlayheadWhenANewOneStarts() async {
    let clock = Clock()
    let (state, _, _) = Self.make(clock: clock)
    let model = TakeScreenModel(capture: state, now: clock.now)

    await state.recordTapped()
    model.advance()
    clock.advance(by: 10)
    model.advance()
    await state.recordTapped()
    model.advance()
    #expect(model.takeDuration == 10)

    // A second take begins.
    await state.recordTapped()
    model.advance()

    #expect(model.takeDuration == 0, "the new take has no length yet, and the old one's is not it")
    #expect(model.playhead == 0)
    #expect(model.elapsed == 0)
  }
}
