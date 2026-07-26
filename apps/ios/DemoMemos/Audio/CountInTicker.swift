import AudioToolbox
import Foundation

/// The soft tick the count-in plays on each beat (8a). A seam like the other
/// three, for the same reason: every unit test and every `#Preview` runs on the
/// fake, so counting in makes no sound outside the app.
protocol CountInTicker: AnyObject {
  func tick()
}

/// The system's own short tick, so a count-in sounds like the rest of iOS
/// rather than like a sample this app shipped.
final class SystemSoundCountInTicker: CountInTicker {
  /// `Tink` — the softest short click in the system set.
  private static let soundID: SystemSoundID = 1103

  func tick() {
    AudioServicesPlaySystemSound(Self.soundID)
  }
}
