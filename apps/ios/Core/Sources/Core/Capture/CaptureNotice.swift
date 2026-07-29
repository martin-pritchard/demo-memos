/// One thing worth telling the user about, as domain fact rather than prose.
///
/// `Core` owns *what happened*; the app owns the wording (see
/// `CaptureNotice+Wording.swift`). The split is not stylistic: the existing copy
/// is derived from `AudioSession.Failure`, an AVFAudio type, and moving the
/// strings here would drag the framework in behind them
/// (`docs/PRINCIPLES.ios.md` #2).
public enum CaptureNotice: Equatable, Sendable {
  /// Asked for the microphone and told no. Recording cannot proceed.
  case permissionDenied
  /// A take ended for a reason worth mentioning. Never `.user` — a tap the user
  /// made needs no explaining.
  case stopped(StopReason)
  /// Recording or playback refused to start. The payload is the underlying
  /// message, already localised by whoever produced it.
  case startFailed(String)
  /// The route runs at a sample rate we did not ask for, so nothing was
  /// recorded. Surfaced rather than swallowed — silently resampling is the
  /// outcome the read-back exists to prevent. Rates are in Hz.
  case unexpectedFormat(granted: Double, wanted: Double)
}
