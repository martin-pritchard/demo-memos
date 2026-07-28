/// Whether the user has let us at the microphone. Mirrors the three states
/// `AVAudioApplication.recordPermission` reports, without the framework — the
/// app maps one to the other so `Core` stays UI- and AVFoundation-free
/// (`docs/PRINCIPLES.ios.md` #2).
public enum MicrophonePermission: Equatable, Sendable {
  /// Never asked. The prompt is raised on the first record tap, never on launch.
  case undetermined
  case denied
  case granted
}
