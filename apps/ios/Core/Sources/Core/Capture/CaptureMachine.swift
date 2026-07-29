import Foundation

/// The capture/playback transport, as a pure function.
///
/// Every transition the screen can make lives in `next`: it takes the current
/// state and one event and returns the next state plus the side effects someone
/// else should perform. It touches no clock, no filesystem, no audio session and
/// no UI, so the whole transport is testable with `swift test` — no simulator,
/// no microphone, no files (`docs/PRINCIPLES.md` #3).
///
/// The split is what makes that possible. `CaptureState` in the app owns the
/// *doing* — building take URLs, driving `AVAudioRecorder`/`AVAudioEngine`,
/// wording notices — and this owns the *deciding*. An effect is a request, not
/// an action: `.startRecording` names no URL because the destination is a folder
/// and a clock the app owns, and threading both through here to keep it pure
/// would buy nothing.
///
/// An enum with no cases, used as a namespace: `State`, `Event` and `Effect` are
/// only meaningful together, and nesting them keeps `Core` from growing four
/// more top-level names.
public enum CaptureMachine {

  /// Everything the screen renders from. A value type with no references, so a
  /// test can build any situation directly instead of driving the machine into
  /// it.
  public struct State: Equatable, Sendable {
    public var mode: CaptureMode
    public var permission: MicrophonePermission
    /// The most recent finished take. Only ever set from `.recordingStopped`,
    /// so it never names a file still being written.
    public var latestTake: URL?
    /// Whatever just happened that is worth a line of explanation. `nil` when
    /// there is nothing to say.
    public var notice: CaptureNotice?
    /// The Enhance dial, `0...1`. Always in range — `next` clamps on write.
    public var warmth: Double

    public init(
      mode: CaptureMode = .idle,
      permission: MicrophonePermission = .undetermined,
      latestTake: URL? = nil,
      notice: CaptureNotice? = nil,
      warmth: Double = 0
    ) {
      self.mode = mode
      self.permission = permission
      self.latestTake = latestTake
      self.notice = notice
      self.warmth = warmth
    }

    /// Denied is the only permission that rules recording out — undetermined
    /// still gets a prompt.
    public var canRecord: Bool { permission != .denied }

    /// Needs a finished take, and never mid-record: a play tap must not
    /// interrupt a take.
    public var canPlay: Bool { latestTake != nil && mode != .recording }

    public var isDenied: Bool { permission == .denied }
  }

  /// Something that happened: a tap, or a seam reporting back. Events are facts
  /// about the past — `next` decides what they mean.
  public enum Event: Equatable, Sendable {
    case recordTapped
    case playTapped
    /// The prompt was answered — or dismissed, which arrives as
    /// `.undetermined`.
    case permissionResolved(MicrophonePermission)
    /// The recorder accepted the take. An acknowledgement: the mode moved to
    /// `.recording` when the effect was emitted, so nothing is left to change.
    case recordingStarted
    case recordingFailed(CaptureNotice)
    /// A take finished. Fires exactly once per take, whatever ended it, and the
    /// file at the URL is always finalised and playable.
    case recordingStopped(StopReason, URL)
    case playbackFailed(CaptureNotice)
    /// A take reached its end, or playback was cut short. Not sent for a
    /// user-requested stop.
    case playbackFinished
    case warmthChanged(Double)
  }

  /// Something the app should do. Data, not a closure, so a test asserts on the
  /// decision without performing it.
  public enum Effect: Equatable, Sendable {
    case requestPermission
    /// Start a take. The app picks the destination — see the type comment.
    case startRecording
    case stopRecording
    case startPlayback(URL)
    case stopPlayback
    case setWarmth(Double)
  }

  /// Decide. Pure: same input, same output, and the input state is never
  /// mutated.
  public static func next(_ state: State, _ event: Event) -> (State, [Effect]) {
    var state = state

    switch event {

    case .recordTapped:
      // Ignored outright while the prompt is up. Not "no effects but clear the
      // notice" — a tap that does nothing should leave no trace, and a notice
      // cannot be showing here anyway, because the tap that raised the prompt
      // cleared it.
      guard state.mode != .awaitingPermission else { return (state, []) }

      state.notice = nil

      // Stop is a request, not an arrival: the mode stays `.recording` until
      // `.recordingStopped` says the file is finalised.
      if state.mode == .recording { return (state, [.stopRecording]) }

      // Record wins over playback — tapping record mid-playback is a decision to
      // record, not an ambiguity. Stopping first keeps the two out of the
      // session at once.
      var effects: [Effect] = state.mode == .playing ? [.stopPlayback] : []

      switch state.permission {
      case .granted:
        state.mode = .recording
        effects.append(.startRecording)
      case .undetermined:
        state.mode = .awaitingPermission
        effects.append(.requestPermission)
      case .denied:
        // Never re-prompt: iOS shows the prompt once, so asking again does
        // nothing and the user needs pointing at Settings instead.
        state.mode = .idle
        state.notice = .permissionDenied
      }
      return (state, effects)

    case .permissionResolved(let permission):
      // Recorded whatever the mode, so a late answer still updates `canRecord`.
      state.permission = permission
      // Only an answer we are actually waiting on resumes the take.
      guard state.mode == .awaitingPermission else { return (state, []) }

      switch permission {
      case .granted:
        state.mode = .recording
        return (state, [.startRecording])
      case .denied:
        state.mode = .idle
        state.notice = .permissionDenied
        return (state, [])
      case .undetermined:
        // Dismissed without answering. No notice — nothing was refused, and the
        // next tap prompts again.
        state.mode = .idle
        return (state, [])
      }

    case .recordingStarted:
      return (state, [])

    case .recordingFailed(let notice):
      state.mode = .idle
      state.notice = notice
      return (state, [])

    case .recordingStopped(let reason, let url):
      // Unconditional: every stop reason leaves a playable file, so the take is
      // kept whatever ended it. Only the wording differs.
      state.mode = .idle
      state.latestTake = url
      state.notice = reason == .user ? nil : .stopped(reason)
      return (state, [])

    case .playTapped:
      switch state.mode {
      case .playing:
        state.notice = nil
        state.mode = .idle
        return (state, [.stopPlayback])
      case .idle:
        guard let take = state.latestTake else { return (state, []) }
        state.notice = nil
        state.mode = .playing
        return (state, [.startPlayback(take)])
      case .recording, .awaitingPermission:
        return (state, [])
      }

    case .playbackFailed(let notice):
      state.mode = .idle
      state.notice = notice
      return (state, [])

    case .playbackFinished:
      // Guarded because this can arrive late — after a record tap already tore
      // playback down — and an unguarded reset would knock a live take to idle.
      guard state.mode == .playing else { return (state, []) }
      state.mode = .idle
      return (state, [])

    case .warmthChanged(let value):
      // Clamped once, here, so the state and the effect can never disagree
      // about what the dial is.
      let warmth = min(max(value, 0), 1)
      state.warmth = warmth
      return (state, [.setWarmth(warmth)])
    }
  }
}
