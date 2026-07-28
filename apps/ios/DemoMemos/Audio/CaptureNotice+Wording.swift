import Core
import Foundation

/// The app half of the notice seam: `Core` decides *what happened*, this decides
/// what to say about it.
///
/// The wording lives here rather than in `Core` because it is derived from
/// `AudioSession.Failure`, an AVFAudio type — moving the strings across would
/// drag the framework in behind them (`docs/PRINCIPLES.ios.md` #2). Both
/// directions of the mapping are here so the pair stays readable together: an
/// error becomes a `CaptureNotice`, a `CaptureNotice` becomes a line of text.
extension CaptureNotice {

  /// One line of plain text. No jargon, and every wording that follows a stop
  /// says the take was saved — because it always was.
  var wording: String {
    switch self {
    case .permissionDenied:
      "Microphone access is off. Turn it on in Settings to record."

    case .stopped(let reason):
      switch reason {
      case .user:
        // Unreachable: `CaptureMachine` raises no notice for a stop the user
        // asked for. Worded anyway rather than crashing if that ever changes.
        "Your take was saved."
      case .interrupted:
        "Interrupted. Your take was saved."
      case .routeLost:
        "Audio device disconnected. Your take was saved."
      case .mediaServicesReset:
        "The audio system restarted. Your take was saved."
      case .failed(let message):
        "Recording stopped: \(message). Your take was saved."
      }

    case .startFailed(let message):
      // Passed through as-is. `describing(_:)` below owns the phrasing, because
      // only it can tell a configuration failure (which gets a prefix) from an
      // arbitrary error (whose `localizedDescription` already reads as a
      // sentence and gains nothing from one).
      message

    case .unexpectedFormat(let granted, let wanted):
      """
      This route runs at \(Int(granted)) Hz, but takes are \
      \(Int(wanted)) Hz. Recording would resample. \
      Not recording rather than saving something else.
      """
    }
  }

  /// Turn a thrown error into the domain fact `Core` understands.
  ///
  /// A format we did not ask for is surfaced, never swallowed — recording a
  /// resampled 44.1 while claiming 48 kHz is the outcome the read-back exists to
  /// prevent.
  static func describing(_ error: any Error) -> CaptureNotice {
    guard let failure = error as? AudioSession.Failure else {
      return .startFailed(error.localizedDescription)
    }
    switch failure {
    case .configuration(let message):
      return .startFailed("Could not start recording: \(message)")
    case .unexpectedFormat(let granted, let wanted):
      return .unexpectedFormat(granted: granted.sampleRate, wanted: wanted.sampleRate)
    }
  }
}
