/// What the capture surface is doing right now.
public enum CaptureMode: Equatable, Sendable {
  case idle
  /// The microphone prompt is on screen and we are waiting on the answer. A
  /// mode of its own so a second record tap during that window is ignored
  /// rather than raising a second prompt.
  case awaitingPermission
  /// Recording, or asked to stop and not yet told the file is finalised. The
  /// two are deliberately the same mode: `latestTake` must only ever name a
  /// finished file.
  case recording
  case playing
}
