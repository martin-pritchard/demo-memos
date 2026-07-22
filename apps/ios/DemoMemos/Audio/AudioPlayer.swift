import AVFoundation
import Foundation

/// Playback for one take. `currentTime` is settable so the centre-locked scrub
/// can drive the playhead directly.
protocol AudioPlayer: AnyObject {
  var isPlaying: Bool { get }
  var duration: TimeInterval { get }
  var currentTime: TimeInterval { get set }
  var onFinish: (() -> Void)? { get set }

  func load(url: URL) throws
  func play()
  func pause()
}

final class AVAudioPlayerAdapter: NSObject, AudioPlayer, AVAudioPlayerDelegate {
  private var player: AVAudioPlayer?

  var onFinish: (() -> Void)?

  var isPlaying: Bool { player?.isPlaying ?? false }
  var duration: TimeInterval { player?.duration ?? 0 }

  var currentTime: TimeInterval {
    get { player?.currentTime ?? 0 }
    set { player?.currentTime = newValue }
  }

  func load(url: URL) throws {
    let player = try AVAudioPlayer(contentsOf: url)
    player.delegate = self
    player.prepareToPlay()
    self.player = player
  }

  func play() {
    try? AudioSession.configureForPlayback()
    player?.play()
  }

  func pause() {
    player?.pause()
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    onFinish?()
  }
}
