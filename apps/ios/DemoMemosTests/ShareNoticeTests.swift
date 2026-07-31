import Core
import Testing

@testable import DemoMemos

/// The two capture-domain facts used as fixtures here. `.permissionDenied` is the
/// only sanctioned rank-`.micState` line; `.startFailed` is the only sanctioned
/// alert, and stands in for "anything that must not touch the slot". Its payload
/// only reaches the alert's wording, which nothing here asserts on.
@MainActor
private func micStateNotice() throws -> TakeNotice {
  try #require(TakeNotice(.permissionDenied))
}

@MainActor
private func alertNotice() throws -> TakeNotice {
  try #require(TakeNotice(.startFailed("The microphone is busy")))
}

@MainActor
@Suite("A failed share render")
struct CouldNotPrepareTests {

  @Test("reads the design's copy, apostrophe and all")
  func line() {
    #expect(TakeNotice.couldNotPrepare.line == "Couldn’t prepare this demo")
  }

  @Test("offers Try Again")
  func action() {
    #expect(TakeNotice.couldNotPrepare.action == .tryAgain)
  }

  // The central design point: nothing was lost and the original recording is
  // untouched, so a failed share must never be dramatised as an interruption.
  @Test("is a line, never an alert")
  func form() {
    #expect(TakeNotice.couldNotPrepare.form == .line)
    #expect(TakeNotice.couldNotPrepare.form != .alert)
  }

  @Test("sits at playback-failure precedence")
  func rank() {
    #expect(TakeNotice.couldNotPrepare.rank == .playbackFailure)
  }

  // alertTitle is nil whenever form is .line; a title here would mean the notice
  // was authored as an alert and then downgraded.
  @Test("carries no alert title")
  func alertTitle() {
    #expect(TakeNotice.couldNotPrepare.alertTitle == nil)
  }
}

@MainActor
@Suite("Precedence between two notices")
struct PrecedentTests {

  @Test("with nothing to say, says nothing")
  func bothAbsent() {
    #expect(TakeNotice.precedent(nil, nil) == nil)
  }

  @Test("a lone notice wins as the first argument")
  func secondAbsent() {
    #expect(TakeNotice.precedent(.couldNotPrepare, nil) == .couldNotPrepare)
  }

  @Test("a lone notice wins as the second argument")
  func firstAbsent() {
    #expect(TakeNotice.precedent(nil, .couldNotPrepare) == .couldNotPrepare)
  }

  @Test("mic state beats a failed share")
  func micStateWins() throws {
    let mic = try micStateNotice()
    #expect(TakeNotice.precedent(mic, .couldNotPrepare) == mic)
  }

  // Argument order must not decide the winner; only rank may.
  @Test("mic state beats a failed share whichever way round it is passed")
  func micStateWinsReversed() throws {
    let mic = try micStateNotice()
    #expect(TakeNotice.precedent(.couldNotPrepare, mic) == mic)
  }

  @Test("a tie goes to the first argument")
  func tie() {
    #expect(TakeNotice.precedent(.couldNotPrepare, .couldNotPrepare) == .couldNotPrepare)
  }

  // Guards against the function synthesising a merged or placeholder notice.
  @Test("returns one of its inputs and never a notice of its own making")
  func returnsAnInput() throws {
    let mic = try micStateNotice()
    let pairs: [(TakeNotice?, TakeNotice?)] = [
      (mic, .couldNotPrepare),
      (.couldNotPrepare, mic),
      (.couldNotPrepare, nil),
      (nil, mic),
    ]
    for (a, b) in pairs {
      let winner = TakeNotice.precedent(a, b)
      #expect(winner == a || winner == b)
    }
  }
}

@MainActor
@Suite("A failed share in the one reserved slot")
struct ShareNoticeSlotTests {

  @Test("takes the slot")
  func takesTheSlot() {
    #expect(
      TakeSlot.resolve(notice: .couldNotPrepare, coaching: .clear) == .notice(.couldNotPrepare))
  }

  // Coaching is the lowest-precedence speaker; a share failure silences it
  // rather than appearing beside it, because there is no second channel.
  @Test("silences coaching that would otherwise speak")
  func outranksCoaching() {
    #expect(TakeSlot.resolve(notice: .couldNotPrepare, coaching: .hot) == .notice(.couldNotPrepare))
  }

  // The boundary the share failure must stay on the right side of: an alert
  // interrupts instead, and leaves the slot untouched.
  @Test("an alert-form notice leaves the slot empty")
  func alertNeverTakesTheSlot() throws {
    let alert = try alertNotice()
    #expect(TakeSlot.resolve(notice: alert, coaching: .clear) == .empty)
  }

  @Test("an alert-form notice leaves coaching in the slot")
  func alertLeavesCoaching() throws {
    let alert = try alertNotice()
    #expect(TakeSlot.resolve(notice: alert, coaching: .hot) == .coaching(.hot))
  }
}
