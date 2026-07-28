import AVFAudio
import Foundation
import Testing

@testable import DemoMemos

/// The settings dictionary is the contract with the file on disk. Its keys were
/// verified against the iOS 26.5 SDK (`AVFAudio/AVAudioSettings.h`); this pins
/// the values so a later edit cannot quietly change what a take is.
struct AudioSessionTests {

  @Test func recorderSettingsDescribe48kMono24BitLinearPCM() {
    let settings = AudioSession.recorderSettings

    #expect(settings[AVFormatIDKey] as? Int == Int(kAudioFormatLinearPCM))
    #expect(settings[AVSampleRateKey] as? Double == 48_000)
    #expect(settings[AVNumberOfChannelsKey] as? Int == 1)
    #expect(settings[AVLinearPCMBitDepthKey] as? Int == 24)
    #expect(settings[AVLinearPCMIsFloatKey] as? Bool == false)
    #expect(settings[AVLinearPCMIsBigEndianKey] as? Bool == false)
  }

  /// `AVAudioRecorder` accepting the settings is a stronger check than asserting
  /// our own dictionary back to ourselves: it rejects an invalid combination.
  ///
  /// `format` is empty (0 Hz, 0 channels) until `prepareToRecord()` runs — it
  /// describes the file being written, which does not exist before then.
  @Test func avAudioRecorderAcceptsTheSettings() throws {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let recorder = try AVAudioRecorder(
      url: folder.appending(path: "probe.wav"), settings: AudioSession.recorderSettings)
    #expect(recorder.prepareToRecord())

    #expect(recorder.format.sampleRate == 48_000)
    #expect(recorder.format.channelCount == 1)
  }

  @Test func wantedGrantMatchesTheDeclaredConstants() {
    #expect(AudioSession.wanted == .init(sampleRate: 48_000, inputChannels: 1))
  }
}

struct RecordingsFolderTests {

  @Test func takeNamesSortChronologicallyAsStrings() {
    let folder = URL.temporaryDirectory
    let calendar = Calendar(identifier: .gregorian)

    let earlier = RecordingsFolder.newTakeURL(
      in: folder, at: Date(timeIntervalSince1970: 1_785_000_000), calendar: calendar)
    let later = RecordingsFolder.newTakeURL(
      in: folder, at: Date(timeIntervalSince1970: 1_785_086_400), calendar: calendar)

    #expect(earlier.pathExtension == "wav")
    #expect(earlier.lastPathComponent.hasPrefix("take-"))
    #expect(earlier.lastPathComponent < later.lastPathComponent)
  }

  @Test func listsOnlyWAVsNewestLast() throws {
    let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for name in ["take-20260728-090000.wav", "take-20260728-100000.wav", "notes.txt"] {
      try Data("x".utf8).write(to: folder.appending(path: name))
    }

    let takes = RecordingsFolder.takes(in: folder)

    #expect(
      takes.map(\.lastPathComponent) == ["take-20260728-090000.wav", "take-20260728-100000.wav"])
  }
}
