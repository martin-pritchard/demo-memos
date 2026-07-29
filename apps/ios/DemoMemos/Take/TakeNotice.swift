import Core
import Foundation

/// How a notice reaches the user.
///
/// Two forms, not three. Design turn `#16` is FINAL on this: the row and the
/// full-block empty state were explored and dropped, because one reserved slot
/// "keeps the screen identical in every state — nothing above it moves, nothing
/// below it jumps". Anything that is not in the slot is an alert, and an alert
/// is only for capture that stopped or never started *against expectation*.
enum TakeNoticeForm: Equatable {
  /// Occupies the screen's one reserved slot, above the transport.
  case line
  /// A system alert. Deliberately does *not* occupy the slot: it interrupts.
  case alert
}

/// The way out of a notice, when there is one.
///
/// One case today because one notice today has a route out. `#15g` is explicit
/// that restricted and no-microphone offer *none* — sending someone to a switch
/// that will not move is the worst version of that screen — so this is a real
/// choice rather than a placeholder waiting to be filled in.
enum TakeNoticeAction: Equatable {
  case openSettings
}

/// Precedence for the one slot, lowest rank first (`#16`).
///
/// The design's rule is `mic state → playback failure → capacity → coaching`.
/// Coaching is not in here because it is not a notice: it is what the slot falls
/// back to, and it always loses (see ``TakeSlot``).
enum TakeNoticeRank: Int, Comparable {
  case micState = 0
  case playbackFailure = 1
  case capacity = 2

  static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One thing the capture layer has to tell the user, in the shape the screen
/// renders it.
///
/// `Core` decides *what happened* (`CaptureNotice`); this decides *how the user
/// meets it*. The split is the same one `CaptureNotice+Wording.swift` already
/// makes for prose, extended to form and precedence — and it lives in `Take/`
/// rather than `Audio/` so the audio layer keeps no screen types
/// (`docs/PRINCIPLES.md` #1).
struct TakeNotice: Equatable {

  /// The sentence in the slot, or the alert's message.
  let line: String

  /// A second line under the first. `#15g` uses it to name who to ask when
  /// there is no route out; nothing reachable today needs one.
  let sub: String?

  /// The tinted capsule at the end of the line. Alerts carry their buttons
  /// themselves, so this is `nil` for them.
  let action: TakeNoticeAction?

  let form: TakeNoticeForm

  let rank: TakeNoticeRank

  /// Alert-only, and `nil` whenever ``form`` is ``TakeNoticeForm/line``.
  let alertTitle: String?

  /// Route a domain fact to the way the user meets it — the `#16f` table.
  ///
  /// `nil` is a real answer, not a gap. Interruption and route loss both leave
  /// the take intact and both were already lived through, so the design says
  /// nothing about them: "a notice explaining the thing you just lived through
  /// is noise". The screen still changes — it lands in `.stopped` with the take
  /// loaded — but it does not speak.
  init?(_ notice: CaptureNotice) {
    switch notice {
    case .permissionDenied:
      // `#15g`'s final string. Deliberately *not* `CaptureNotice.wording`, which
      // reads "…Turn it on in Settings to record." — that bakes the route into
      // the prose, and the design puts it on the capsule instead. Never red:
      // this is a state, not an error.
      self.init(
        line: "Microphone access is off",
        sub: nil,
        action: .openSettings,
        form: .line,
        rank: .micState,
        alertTitle: nil)

    case .stopped(.user), .stopped(.interrupted), .stopped(.routeLost):
      return nil

    case .stopped(.mediaServicesReset), .stopped(.failed):
      // Capture stopped against expectation. `#15e`: the alert leads with what
      // survived, which `wording` already does — every stop wording ends "Your
      // take was saved", because it always was.
      self.init(alert: "Recording Stopped", message: notice.wording)

    case .startFailed, .unexpectedFormat:
      // Capture never started against expectation. Same rung as a failed stop:
      // the user asked for a take and has not got one.
      self.init(alert: "Couldn't Start Recording", message: notice.wording)
    }
  }

  private init(
    line: String, sub: String?, action: TakeNoticeAction?, form: TakeNoticeForm,
    rank: TakeNoticeRank, alertTitle: String?
  ) {
    self.line = line
    self.sub = sub
    self.action = action
    self.form = form
    self.rank = rank
    self.alertTitle = alertTitle
  }

  private init(alert title: String, message: String) {
    self.init(
      line: message, sub: nil, action: nil, form: .alert, rank: .micState, alertTitle: title)
  }
}

/// What the Take screen's one reserved slot is showing.
///
/// "One slot, one resolver" (`#16`). The screen picks the highest-precedence
/// message and renders it; there is no second channel to fall out of sync with.
enum TakeSlot: Equatable {
  case empty
  case coaching(CoachingLevel)
  case notice(TakeNotice)

  /// A notice always takes the slot from coaching.
  ///
  /// The design's reasoning, worth keeping next to the rule: coaching is
  /// transient and unactionable and only speaks while capture is running, and
  /// every mic notice means capture *cannot* run — so in practice they barely
  /// compete. Alerts never occupy the slot, because they are not in it.
  static func resolve(notice: TakeNotice?, coaching: CoachingLevel) -> TakeSlot {
    if let notice, notice.form == .line { return .notice(notice) }
    return coaching == .clear ? .empty : .coaching(coaching)
  }
}
