/// Why a take ended. Every one of these leaves a finalised, playable file —
/// which is why `CaptureMachine` keeps the take on all of them and only the
/// wording differs.
public enum StopReason: Equatable, Sendable {
  /// The user tapped stop.
  case user
  /// A call, Siri, or an alarm took the session.
  case interrupted
  /// Headphones or an interface went away mid-take.
  case routeLost
  /// The media server died and took the session, recorder and player with it.
  case mediaServicesReset
  case failed(String)
}
