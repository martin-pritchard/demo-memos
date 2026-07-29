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

  /// The take ``position`` and ``duration`` refer to. Nil until a take has been
  /// played or scrubbed.
  ///
  /// The playhead outlives the graph, so callers need to know *which* take it
  /// belongs to — otherwise a freshly recorded take inherits the last one's
  /// position and length.
  var loadedTake: URL? { get }

  /// Where the loaded take is up to, in seconds. `0` when nothing is loaded.
  /// Survives a stop, so a paused take still has a playhead to draw.
  var position: TimeInterval { get }

  /// The loaded take's length, `0` if not known yet. Known only once a take has
  /// been decoded, which happens on `play` — a take that has only been recorded
  /// has a length, but nothing here has read it.
  var duration: TimeInterval { get }

  /// Move the playhead of `take`. Applied live if that take is playing,
  /// remembered for its next `play` otherwise — scrubbing a paused take is the
  /// case this exists for, and it has to work before the take's first play.
  func seek(to position: TimeInterval, in take: URL)
}

/// An `AVAudioEngine` graph hosting Unit 1's hand-written warmth DSP (rung 5 of
/// the `ios-audio` ladder — Enhance needs sample access the file-in/file-out
/// players can't give) followed by Apple's reverb (rung 3 — never a hand-rolled
/// reverb). The graph:
///
///   `AVAudioSourceNode` (mono; reads the preloaded take + runs `WarmthKernel`)
///     → `AVAudioUnitReverb` (a touch of space; late and parallel, wet-against-dry)
///     → `mainMixerNode` → `outputNode`
///
/// The reverb's *output* connection is **stereo** (#31): `AVAudioUnitReverb` is a
/// stereo processor, so a mono take fed into a stereo output bus comes out as a
/// centred dry signal under a decorrelated stereo wet tail — width on headphones
/// for free, without touching mono capture or the mono warmth DSP. The dry stays
/// mono/centred; only the wet field opens up. Everything up to and including the
/// source stays mono.
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

  /// The take the playhead below belongs to, and its shape. These outlive the
  /// engine on purpose: `stop` tears the graph down, but a stopped take still
  /// has to draw a playhead and be scrubbable.
  ///
  /// `loadedDuration` and `loadedSampleRate` stay `0` until the take is actually
  /// decoded, which only `play` does — so a take that has been scrubbed but
  /// never played has a `loadedTake` and a `restingPosition` but no length.
  private(set) var loadedTake: URL?
  private var loadedDuration: TimeInterval = 0
  private var loadedSampleRate: Double = 0
  /// Where the playhead sits while no graph is running.
  private var restingPosition: TimeInterval = 0

  var isPlaying: Bool { engine?.isRunning ?? false }

  var duration: TimeInterval { loadedDuration }

  var position: TimeInterval {
    guard let core, loadedSampleRate > 0 else { return restingPosition }
    return Double(core.framesRendered) / loadedSampleRate
  }

  func seek(to position: TimeInterval, in take: URL) {
    // Scrubbing a take we know nothing about yet is the normal case straight
    // after recording: adopt it, so the position is not thrown away and the
    // next `play` starts where the user put it.
    if take != loadedTake {
      stop()
      loadedTake = take
      loadedDuration = 0
      loadedSampleRate = 0
      restingPosition = 0
    }
    // Only clamp against a length we actually know.
    restingPosition = loadedDuration > 0 ? min(max(position, 0), loadedDuration) : max(position, 0)
    guard let core, loadedSampleRate > 0 else { return }
    core.seek(toFrame: Int(restingPosition * loadedSampleRate))
  }

  func play(_ url: URL) throws {
    stop()

    // Swaps the session out of capture's `.measurement` configuration.
    try AudioSession.activateForPlayback()

    let (samples, sampleRate) = try TakeDecoder.mono(url)
    guard sampleRate > 0,
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    else {
      throw AudioSession.Failure.configuration("Could not read the take's format")
    }

    let core = WarmthRenderCore(sampleRate: sampleRate)
    core.setTargetWarmth(warmth)
    core.load(samples: samples)  // snaps to the current dial — no glide on start

    // A different take starts from its own beginning, never from the last one's
    // playhead. The same take keeps whatever the user scrubbed to, including a
    // scrub made before it had ever been played.
    if url != loadedTake { restingPosition = 0 }
    loadedTake = url
    loadedSampleRate = sampleRate
    loadedDuration = Double(samples.count) / sampleRate

    // A take parked at its end restarts from the top — the design's "the next
    // Play restarts from 0". A take scrubbed somewhere else resumes from there,
    // which is the whole point of remembering the position across a stop.
    let start = restingPosition >= loadedDuration ? 0 : restingPosition
    if start > 0 { core.seek(toFrame: Int(start * sampleRate)) }

    // The only realtime code in the app. Captures `core` (Sendable) and nothing
    // main-actor. See `docs/PRINCIPLES.ios.md` #1.
    let render: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard let raw = buffers.first?.mData else { return noErr }
      let out = raw.assumingMemoryBound(to: Float.self)
      core.render(into: UnsafeMutableBufferPointer(start: out, count: Int(frameCount)))
      return noErr
    }

    // The reverb feeds the mixer in stereo (#31): mono in, decorrelated stereo
    // wet out, dry stays centred. `mainMixerNode`/`outputNode` are already stereo,
    // so only this connection's format changes from the mono capture format.
    guard
      let stereoFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)
    else {
      throw AudioSession.Failure.configuration("Could not build the stereo playback format")
    }

    let engine = AVAudioEngine()
    let source = AVAudioSourceNode(format: format, renderBlock: render)
    // Apple's reverb, after the warmth node. Preset and wet amount are tuned by
    // ear like the warmth curve; `.mediumHall` is smoother and bigger than a room.
    let reverb = AVAudioUnitReverb()
    reverb.loadFactoryPreset(.mediumHall)
    engine.attach(source)
    engine.attach(reverb)
    engine.connect(source, to: reverb, format: format)  // mono in
    engine.connect(reverb, to: engine.mainMixerNode, format: stereoFormat)  // stereo wet out
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
    // Park the playhead before the core goes, so a stopped take keeps one. A
    // take that ran to the end parks at the end, which is what the design draws.
    restingPosition = position
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

}
