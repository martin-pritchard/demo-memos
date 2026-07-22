import AVFoundation
import Foundation

/// One owner of session configuration, so record and playback can't fight over
/// the category.
enum AudioSession {
  static func configureForRecording() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
    try session.setActive(true)
  }

  static func configureForPlayback() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)
  }
}
