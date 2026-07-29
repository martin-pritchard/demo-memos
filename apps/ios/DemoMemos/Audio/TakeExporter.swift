import AVFAudio
import Core
import Foundation

/// The export seam. Fake half in `Fakes.swift`.
///
/// Not `@MainActor`, unlike `Recording` and `Playing`: those drive a device from
/// the screen's actor, this one grinds through a file. The system resolves the
/// promised file on its own thread and a render must not land on the main actor
/// on the way past.
/// Explicitly `nonisolated`: this target builds with `-default-isolation=MainActor`,
/// so without it the render would quietly become main-actor work and grind the
/// UI for the length of a take.
nonisolated protocol Exporting: Sendable {

  /// A shareable file for `take` at this dial position, named for the demo.
  ///
  /// Returns immediately when the last render still matches — the silent path in
  /// `#17e`, and what stops a second share of an unchanged take paying for the
  /// same work twice. Honours `Task` cancellation: a cancelled render leaves
  /// nothing behind.
  func rendered(take: URL, warmth: Double, named name: String) async throws -> URL
}

/// Renders a take through **the same graph playback uses**, offline.
///
/// `AVAudioEngine` in `enableManualRenderingMode(.offline, …)` driving
/// `AVAudioSourceNode`(`WarmthRenderCore`) → `AVAudioUnitReverb` →
/// `mainMixerNode` — rung 3 of the `ios-audio` ladder, and not one line of new
/// DSP. That is the whole reason this is not a pure `Core` pass: the space in
/// Enhance is Apple's reverb (#31), which `Core` cannot host, and a shared file
/// that lacks it would not be the thing the user heard.
///
/// The engine is not connected to a device in manual rendering mode, so this
/// never activates `AudioSession` and never calls `setCategory` — sharing does
/// not interrupt playback, and playback does not colour a render.
///
/// Output is AAC in an `.m4a`: the render is stereo (the reverb widens the wet
/// field while the dry stays centred), and stereo linear PCM is ~17 MB/minute,
/// which Messages and Mail handle badly.
nonisolated final class TakeExporter: Exporting, Sendable {

  /// How long the reverb is given to ring out past the end of the take. Tuned by
  /// ear is the only way to settle this; 3s is `.mediumHall`'s decay to
  /// inaudibility at the wet mix the top of the dial asks for, and it is
  /// **unverified by listening** — see the PR.
  private static let reverbTail: TimeInterval = 3

  /// Manual rendering pulls in blocks; this is the size of one.
  private static let renderBlock: AVAudioFrameCount = 4096

  private let temporary: URL

  init(temporary: URL = .temporaryDirectory) {
    self.temporary = temporary
  }

  func rendered(take: URL, warmth: Double, named name: String) async throws -> URL {
    let directory = try ShareScratch.directory(inTemporary: temporary)

    if let hit = ShareScratch.cached(in: directory, take: take, warmth: warmth, named: name) {
      return hit
    }

    // At most one take's worth of processed audio on disk at a time. Done before
    // the render rather than after, so a cancelled or failed share still leaves
    // the area smaller than it found it.
    ShareScratch.prune(in: directory, keeping: take, warmth: warmth)

    let output = ShareScratch.fileURL(in: directory, take: take, warmth: warmth, named: name)
    let slot = output.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)

    do {
      try Self.render(take: take, warmth: warmth, to: output)
    } catch {
      // A half-written file is worse than none: it would satisfy `cached` on the
      // next tap and send silence to whoever the user picked.
      try? FileManager.default.removeItem(at: slot)
      throw error
    }
    return output
  }

  // MARK: - The render

  private static func render(take: URL, warmth: Double, to output: URL) throws {
    let (samples, sampleRate) = try TakeDecoder.mono(take)
    guard !samples.isEmpty, sampleRate > 0 else {
      throw AudioSession.Failure.configuration("There is nothing in this take to share")
    }
    guard
      let mono = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
      let stereo = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)
    else {
      throw AudioSession.Failure.configuration("Could not build the render format")
    }

    let core = WarmthRenderCore(sampleRate: sampleRate)
    core.setTargetWarmth(warmth)
    core.load(samples: samples)  // snaps to the dial — no glide on the first frame

    // Realtime-shaped even offline: manual rendering still pulls this block, so
    // `docs/PRINCIPLES.ios.md` #1 binds exactly as it does in `AudioPlayer`.
    let render: AVAudioSourceNodeRenderBlock = { _, _, frameCount, audioBufferList in
      let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard let raw = buffers.first?.mData else { return noErr }
      let out = raw.assumingMemoryBound(to: Float.self)
      core.render(into: UnsafeMutableBufferPointer(start: out, count: Int(frameCount)))
      return noErr
    }

    let engine = AVAudioEngine()
    let source = AVAudioSourceNode(format: mono, renderBlock: render)
    let reverb = AVAudioUnitReverb()
    reverb.loadFactoryPreset(.mediumHall)
    // The same one curve the live graph rides, so the file matches the playback.
    let wet = warmthParameters(warmth).reverbWetMix
    reverb.bypass = wet == 0
    reverb.wetDryMix = Float(wet * 100)

    engine.attach(source)
    engine.attach(reverb)
    engine.connect(source, to: reverb, format: mono)
    engine.connect(reverb, to: engine.mainMixerNode, format: stereo)

    try engine.enableManualRenderingMode(
      .offline, format: stereo, maximumFrameCount: renderBlock)
    try engine.start()
    defer {
      engine.stop()
      engine.disableManualRenderingMode()
    }

    let file = try AVAudioFile(forWriting: output, settings: settings(sampleRate: sampleRate))
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: engine.manualRenderingFormat,
        frameCapacity: engine.manualRenderingMaximumFrameCount)
    else {
      throw AudioSession.Failure.configuration("Could not allocate the render buffer")
    }

    // The take, then the tail. `WarmthRenderCore` zero-pads past the last frame,
    // so the reverb rings out over silence with nothing added to it — and with
    // the reverb bypassed there is nothing to ring, so no tail is appended
    // rather than three seconds of silence at the end of a dry share.
    let tail = wet == 0 ? 0 : AVAudioFramePosition(Self.reverbTail * sampleRate)
    let total = AVAudioFramePosition(samples.count) + tail

    while engine.manualRenderingSampleTime < total {
      try Task.checkCancellation()
      let remaining = total - engine.manualRenderingSampleTime
      let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))
      switch try engine.renderOffline(frames, to: buffer) {
      case .success:
        try file.write(from: buffer)
      case .insufficientDataFromInputNode:
        // No input node in this graph, so this cannot mean what it says. Treat it
        // as done rather than spinning.
        return
      case .cannotDoInCurrentContext, .error:
        throw AudioSession.Failure.configuration("The render stopped before the end of the take")
      @unknown default:
        throw AudioSession.Failure.configuration("The render stopped before the end of the take")
      }
    }
  }

  private static func settings(sampleRate: Double) -> [String: Any] {
    [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 2,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]
  }
}
