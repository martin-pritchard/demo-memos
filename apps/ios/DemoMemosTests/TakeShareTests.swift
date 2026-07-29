import Core
import Foundation
import Testing

@testable import DemoMemos

/// The wiring between a share and the screen: what the header hands the system
/// sheet, and what the screen says when the render fails.
@Suite("Sharing a take from the Take screen")
@MainActor
struct TakeShareTests {

  private func makeModel(
    capture: CaptureState,
    exporter: FakeExporter = FakeExporter()
  ) -> TakeScreenModel {
    TakeScreenModel(capture: capture, exporter: exporter, now: { Date(timeIntervalSince1970: 0) })
  }

  // MARK: - What gets shared

  @Test("there is nothing to promise before a take exists")
  func noTakeNoPromise() {
    let model = makeModel(capture: .empty)

    #expect(model.sharedTake == nil)
  }

  @Test("the promise names the current take, dial and demo")
  func promiseCarriesTheCurrentValues() throws {
    let capture = CaptureState.populated
    capture.warmth = 0.8
    let model = makeModel(capture: capture)

    let shared = try #require(model.sharedTake)

    #expect(shared.take == capture.latestTake)
    // The dial is read at share time, not at record time — a take shared after
    // the dial moves is shared as it now sounds.
    #expect(shared.warmth == 0.8)
    #expect(shared.name == model.state.title)
  }

  @Test("moving the dial changes what the next share would render")
  func promiseFollowsTheDial() throws {
    let capture = CaptureState.populated
    let model = makeModel(capture: capture)

    capture.warmth = 0.1
    let quiet = try #require(model.sharedTake).warmth
    capture.warmth = 0.9
    let loud = try #require(model.sharedTake).warmth

    #expect(quiet != loud)
  }

  // MARK: - When the render fails

  @Test("a failed render puts a line in the slot, not an alert")
  func failureBecomesANotice() throws {
    let model = makeModel(capture: .populated)
    _ = try #require(model.sharedTake)

    model.shareFailed()

    #expect(model.shareNotice == .couldNotPrepare)
    #expect(model.state.notice?.form == .line)
    #expect(model.state.slot == .notice(.couldNotPrepare))
  }

  @Test("Try Again clears the line")
  func tryAgainClearsTheNotice() throws {
    let model = makeModel(capture: .populated)
    model.shareFailed()

    model.perform(.tryAgain)

    #expect(model.shareNotice == nil)
    #expect(model.state.notice == nil)
  }

  @Test("a microphone notice outranks a failed share")
  func captureNoticeWins() async throws {
    // Both are true at once: the mic was refused *and* an earlier share failed.
    // `#16` gives the one slot to the higher-precedence message rather than
    // opening a second channel for the loser. Built here rather than from the
    // `.denied` scenario because that one raises the prompt in a detached task,
    // and this test needs the refusal to have landed before it reads the slot.
    let capture = CaptureState(
      recorder: FakeRecorder(permission: .denied),
      player: FakePlayer(),
      folder: FileManager.default.temporaryDirectory,
      latestTake: FileManager.default.temporaryDirectory.appending(path: "take.wav"))
    await capture.recordTapped()
    let model = makeModel(capture: capture)
    model.shareFailed()

    #expect(model.shareNotice == .couldNotPrepare)
    #expect(model.state.notice?.rank == .micState)
  }
}
