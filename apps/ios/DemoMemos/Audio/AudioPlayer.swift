import AVFAudio
import Core
import Foundation

/// The playback seam. Fake half in `Fakes.swift`.
@MainActor
protocol Playing: AnyObject {
  var isPlaying: Bool { get }
  /// Fires when a take reaches its end, or playback is cut short (interruption,
  /// route loss, media reset). Not fired for a user-requested `stop`.
  var onFinish: (() -> Void)? { get set }

  func play(_ url: URL) throws
  func stop()

  /// The Enhance dial, `0...1`. Applied live if playing, remembered for the next
  /// `play` otherwise. `0` is a true bypass. In-memory only — no persistence.
  func setWarmth(_ value: Double)
}

/// An `AVAudioEngine` graph hosting Unit 1's hand-written warmth DSP (rung 5 of
/// the `ios-audio` ladder — Enhance needs sample access the file-in/file-out
/// players can't give) followed by Apple's reverb (rung 3 — never a hand-rolled
/// reverb). The graph:
///
///   `AVAudioSourceNode` (reads the preloaded take + runs `WarmthKernel`)
///     → `AVAudioUnitReverb` (a touch of space; late and parallel, wet-against-dry)
///     → `mainMixerNode` → `outputNode`
///
/// The source node is *both* transport and warmth effect: on `play` the whole
/// take is decoded to a mono `[Float]` here on the main actor — off the realtime
/// thread — and the render block only copies frames and colours them, so it never
/// allocates, locks, or awaits (`docs/PRINCIPLES.ios.md` #1). All the realtime
/// arithmetic lives in `WarmthRenderCore`, which is unit-tested with no engine.
///
/// The reverb wet mix is not its own control: it rides the same Enhance dial
/// (#22), driven off `warmthParameters(_:).reverbWetMix` so a touch of space
/// folds in with the warmth along one curve. At `warmth == 0` the node is bypassed
/// for a true dry passthrough.
///
/// A fresh engine is built per `play` and torn down on `stop`/finish, so a
/// `mediaServicesWereReset` is handled simply by rebuilding on the next `play`.
/// The category is still owned by `AudioSession` — this file never calls
/// `setCategory`.
@MainActor
final class AudioPlayer: Playing {

  var onFinish: (() -> Void)?

  private var engine: AVAudioEngine?
  private var core: WarmthRenderCore?
  private var reverb: AVAudioUnitReverb?
  private var endPoll: Timer?
  private var observers: [NSObjectProtocol] = []

  /// Latest dial value, kept across takes for the session. Not persisted.
  private var warmth: Double = 0

  var isPlaying: Bool { engine?.isRunning ?? false }

  func play(_ url: URL) throws {
    stop()

    // Swaps the session out of capture's `.measurement` configuration.
    try AudioSession.activateForPlayback()

    let (samples, sampleRate) = try Self.decodeMono(url)
    guard sampleRate > 0,
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    else {
      throw AudioSession.Failure.configuration("Could not read the take's format")
    }

    let core = WarmthRenderCore(sampleRate: sampleRate)
    core.setTargetWarmth(warmth)
    core.load(samples: samples)  // snaps to the current dial — no glide on start

    // The only realtime code in the app. Captures `core` (Sendable) and nothing
    // main-actor. See `docs/PRINCIPLES.ios.md` #1.
    let render: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard let raw = buffers.first?.mData else { return noErr }
      let out = raw.assumingMemoryBound(to: Float.self)
      core.render(into: UnsafeMutableBufferPointer(start: out, count: Int(frameCount)))
      return noErr
    }

    let engine = AVAudioEngine()
    let source = AVAudioSourceNode(format: format, renderBlock: render)
    // Apple's reverb, after the warmth node. Preset and wet amount are tuned by
    // ear like the warmth curve; `.mediumHall` is smoother and bigger than a room.
    let reverb = AVAudioUnitReverb()
    reverb.loadFactoryPreset(.mediumHall)
    engine.attach(source)
    engine.attach(reverb)
    engine.connect(source, to: reverb, format: format)
    engine.connect(reverb, to: engine.mainMixerNode, format: format)
    engine.prepare()
    do {
      try engine.start()
    } catch {
      throw AudioSession.Failure.configuration(
        "AVAudioEngine refused to start: \(error.localizedDescription)")
    }

    self.engine = engine
    self.core = core
    self.reverb = reverb
    applyReverb()  // seed the wet mix from the current dial
    observeSessionEvents()
    startEndPoll()
  }

  func stop() {
    teardown()
  }

  func setWarmth(_ value: Double) {
    warmth = min(max(value, 0), 1)
    core?.setTargetWarmth(warmth)
    applyReverb()
  }

  /// Fold the dial's share of space onto the reverb. Set from the main actor, so
  /// no realtime concerns; the reverb tail smooths the change perceptually. At
  /// warmth 0 the node is bypassed so the dry path is a true passthrough.
  private func applyReverb() {
    guard let reverb else { return }
    let wet = warmthParameters(warmth).reverbWetMix  // 0...1
    reverb.bypass = wet == 0
    reverb.wetDryMix = Float(wet * 100)
  }

  // MARK: - Lifecycle

  /// Tear the graph down. Idempotent (guards on `engine`), and silent — no
  /// `onFinish`. The user asked to stop; nothing needs explaining.
  private func teardown() {
    guard let engine else { return }
    self.engine = nil
    core = nil
    reverb = nil
    endPoll?.invalidate()
    endPoll = nil
    stopObserving()
    engine.stop()
  }

  /// Playback ended on its own or was cut short. Tears down, then fires
  /// `onFinish` exactly once — the guard makes a double event (e.g. the poll and
  /// a route change racing) fire it just the once.
  private func finish() {
    guard engine != nil else { return }
    teardown()
    onFinish?()
  }

  /// The render thread never touches UI, so end-of-take is surfaced through an
  /// atomic flag the core sets and this main-actor timer drains — the same
  /// "drain on another thread" shape `docs/PRINCIPLES.ios.md` #1 prescribes.
  private func startEndPoll() {
    endPoll = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.core?.hasReachedEnd == true else { return }
        self.finish()
      }
    }
  }

  // MARK: - Session events

  private func observeSessionEvents() {
    let centre = NotificationCenter.default
    observers = [
      centre.addObserver(
        forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated { self?.handleInterruption(note) }
      },
      centre.addObserver(
        forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated { self?.handleRouteChange(note) }
      },
      centre.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.finish() }
      },
    ]
  }

  private func stopObserving() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
  }

  /// A call or Siri stops playback cleanly — mirrors capture (#24 spec). No
  /// auto-resume: `.ended` is ignored, and the warmth value is untouched because
  /// it lives on the state object, not the engine.
  private func handleInterruption(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
      AVAudioSession.InterruptionType(rawValue: raw) == .began
    else { return }
    finish()
  }

  /// Headphones out (`.oldDeviceUnavailable`) stops rather than blasting the take
  /// through the built-in speaker.
  private func handleRouteChange(_ note: Notification) {
    guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
    else { return }
    finish()
  }

  // MARK: - Decoding

  /// Decode a take fully into mono ±1.0 float. Whole-file, on the main actor
  /// before the engine starts — fine for short song-idea takes (~11.5 MB/min at
  /// 48 kHz). A streaming producer is the escalation only if takes grow long.
  private static func decodeMono(_ url: URL) throws -> (samples: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat  // always deinterleaved float32
    let frames = AVAudioFrameCount(file.length)
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
      return ([], format.sampleRate)
    }
    try file.read(into: buffer)

    let channelCount = Int(format.channelCount)
    let count = Int(buffer.frameLength)
    guard let channels = buffer.floatChannelData, channelCount > 0, count > 0 else {
      return ([], format.sampleRate)
    }

    var mono = [Float](repeating: 0, count: count)
    if channelCount == 1 {
      let source = channels[0]
      for i in 0..<count { mono[i] = source[i] }
    } else {
      // Capture is mono; this downmix is defensive so an unexpected stereo file
      // still plays rather than reading one channel.
      let scale = 1 / Float(channelCount)
      for i in 0..<count {
        var sum: Float = 0
        for c in 0..<channelCount { sum += channels[c][i] }
        mono[i] = sum * scale
      }
    }
    return (mono, format.sampleRate)
  }
}
