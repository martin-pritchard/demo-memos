import AVFAudio
import Foundation

/// The playback seam. Fake half in `Fakes.swift`.
@MainActor
protocol Playing: AnyObject {
  var isPlaying: Bool { get }
  /// Fires when a take reaches its end, or playback is cut short.
  var onFinish: (() -> Void)? { get set }

  func play(_ url: URL) throws
  func stop()
}

/// `AVAudioPlayer` over the same session the recorder uses.
///
/// The category is `.playAndRecord` with `.defaultToSpeaker` and is set once in
/// `AudioSession`, so playback does not tear down capture configuration or come
/// out of the earpiece.
@MainActor
final class AudioPlayer: NSObject, Playing {

  var onFinish: (() -> Void)?

  private var player: AVAudioPlayer?

  var isPlaying: Bool { player?.isPlaying ?? false }

  func play(_ url: URL) throws {
    stop()
    let player = try AVAudioPlayer(contentsOf: url)
    player.delegate = self
    guard player.play() else {
      throw AudioSession.Failure.configuration("AVAudioPlayer refused to start")
    }
    self.player = player
  }

  func stop() {
    guard let player else { return }
    self.player = nil
    player.stop()
  }
}

extension AudioPlayer: AVAudioPlayerDelegate {

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor [weak self] in
      guard let self, self.player === player else { return }
      self.player = nil
      self.onFinish?()
    }
  }

  nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
    Task { @MainActor [weak self] in
      guard let self, self.player === player else { return }
      self.player = nil
      self.onFinish?()
    }
  }
}
