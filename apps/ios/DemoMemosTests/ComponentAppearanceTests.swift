import Foundation
import SwiftUI
import Testing

@testable import DemoMemos

// MARK: - TransportAppearance

struct TransportAppearanceTests {

  // Acceptance criterion 1.
  @Test func recordIsADiscAtSeventyEightPercent() {
    let appearance = TransportAppearance(for: .record)
    #expect(appearance.figure == .disc(scale: 0.78))
    #expect(appearance.hasRing)
    #expect(appearance.label == "Record")
  }

  // Acceptance criterion 2.
  @Test func stopIsARoundedSquareAtFortyPercentWithRadiusNine() {
    let appearance = TransportAppearance(for: .stop)
    #expect(appearance.figure == .roundedSquare(scale: 0.40, radius: 9))
    #expect(appearance.hasRing)
    #expect(appearance.label == "Stop")
  }

  // Acceptance criterion 3.
  @Test func countInShowsTheNumeral() {
    let appearance = TransportAppearance(for: .countIn(3))
    #expect(appearance.figure == .numeral("3"))
  }

  // Acceptance criterion 3: the ring is unchanged from `.record`, so the
  // button cannot resize as capture moves from count-in into recording.
  @Test func countInKeepsTheRingAndLabelOfRecord() {
    let record = TransportAppearance(for: .record)
    let countIn = TransportAppearance(for: .countIn(3))
    #expect(countIn.hasRing == record.hasRing)
    #expect(countIn.hasRing)
    #expect(countIn.label == record.label)
    #expect(countIn.label == "Record")
  }

  @Test func countInRendersEachRemainingBeatAsItsOwnNumeral() {
    #expect(TransportAppearance(for: .countIn(4)).figure == .numeral("4"))
    #expect(TransportAppearance(for: .countIn(2)).figure == .numeral("2"))
    #expect(TransportAppearance(for: .countIn(1)).figure == .numeral("1"))
  }

  @Test func countInAtZeroIsStillANumeral() {
    let appearance = TransportAppearance(for: .countIn(0))
    #expect(appearance.figure == .numeral("0"))
    #expect(appearance.hasRing)
    #expect(appearance.label == "Record")
  }

  @Test func countInAtDoubleDigitsRendersBothDigits() {
    #expect(TransportAppearance(for: .countIn(12)).figure == .numeral("12"))
  }

  @Test func resumeIsASmallerDiscThanRecord() {
    let appearance = TransportAppearance(for: .resume)
    #expect(appearance.figure == .disc(scale: 0.40))
    #expect(appearance.hasRing)
    #expect(appearance.label == "Resume")
  }

  @Test func playIsARinglessGlyph() {
    let appearance = TransportAppearance(for: .play)
    #expect(appearance.figure == .symbol(name: "play.fill", scale: 0.42))
    #expect(appearance.hasRing == false)
    #expect(appearance.label == "Play")
  }

  @Test func pauseIsARinglessGlyph() {
    let appearance = TransportAppearance(for: .pause)
    #expect(appearance.figure == .symbol(name: "pause.fill", scale: 0.42))
    #expect(appearance.hasRing == false)
    #expect(appearance.label == "Pause")
  }

  @Test func recordingRolesRingAndPlaybackRolesDoNot() {
    let ringed: [TransportRole] = [.record, .countIn(3), .stop, .resume]
    for role in ringed {
      #expect(TransportAppearance(for: role).hasRing, "\(role) should carry the ring")
    }
    for role in [TransportRole.play, .pause] {
      #expect(TransportAppearance(for: role).hasRing == false, "\(role) should have no ring")
    }
  }

  @Test func playAndPauseShareASingleGlyphScale() {
    #expect(TransportAppearance(for: .play).figure == .symbol(name: "play.fill", scale: 0.42))
    #expect(TransportAppearance(for: .pause).figure == .symbol(name: "pause.fill", scale: 0.42))
  }

  @Test func stopAndResumeShareAFigureScale() {
    #expect(TransportAppearance(for: .stop).figure == .roundedSquare(scale: 0.40, radius: 9))
    #expect(TransportAppearance(for: .resume).figure == .disc(scale: 0.40))
  }

  @Test func everyRoleHasANonEmptyLabel() {
    let roles: [TransportRole] = [.record, .countIn(3), .stop, .resume, .play, .pause]
    for role in roles {
      #expect(TransportAppearance(for: role).label.isEmpty == false, "\(role) needs a label")
    }
  }

  @Test func appearanceIsAValueDerivedOnlyFromItsRole() {
    #expect(TransportAppearance(for: .record) == TransportAppearance(for: .record))
    #expect(TransportAppearance(for: .countIn(3)) == TransportAppearance(for: .countIn(3)))
    #expect(TransportAppearance(for: .countIn(3)) != TransportAppearance(for: .countIn(2)))
    #expect(TransportAppearance(for: .play) != TransportAppearance(for: .pause))
    #expect(TransportAppearance(for: .record) != TransportAppearance(for: .resume))
  }
}

struct TransportButtonMetricsTests {

  @Test func diameterIsSixtySix() {
    #expect(TransportButton.diameter == 66)
  }

  @Test func ringWidthIsFour() {
    #expect(TransportButton.ringWidth == 4)
  }

  // The button is one fixed size for every role: nothing about the appearance
  // can make it grow or shrink between states.
  @Test func metricsAreConstantsAndNotDerivedFromARole() {
    let diameter = TransportButton.diameter
    let ringWidth = TransportButton.ringWidth
    let roles: [TransportRole] = [.record, .countIn(3), .stop, .resume, .play, .pause]
    for role in roles {
      _ = TransportAppearance(for: role)
      #expect(TransportButton.diameter == diameter)
      #expect(TransportButton.ringWidth == ringWidth)
    }
  }

  @Test func ringFitsInsideTheButton() {
    #expect(TransportButton.ringWidth < TransportButton.diameter / 2)
  }
}

// MARK: - TimerParts

struct TimerPartsTests {

  // Acceptance criterion 4.
  @Test func zeroReadsAsAllZeroes() {
    let parts = TimerParts(elapsed: 0)
    #expect(parts.major == "00:00")
    #expect(parts.hundredths == "00")
  }

  // Acceptance criterion 4.
  @Test func aMinuteAndAHalfSecondSplitsIntoMajorAndHundredths() {
    let parts = TimerParts(elapsed: 61.5)
    #expect(parts.major == "01:01")
    #expect(parts.hundredths == "50")
  }

  // Acceptance criterion 4.
  @Test func minutesDoNotRollOverIntoHours() {
    let parts = TimerParts(elapsed: 3600)
    #expect(parts.major == "60:00")
    #expect(parts.hundredths == "00")
  }

  @Test func minutesKeepCountingPastAnHour() {
    let parts = TimerParts(elapsed: 3661.23)
    #expect(parts.major == "61:01")
    #expect(parts.hundredths == "23")
  }

  // Acceptance criterion 5.
  @Test func negativeElapsedClampsToZero() {
    let parts = TimerParts(elapsed: -5)
    #expect(parts.major == "00:00")
    #expect(parts.hundredths == "00")
  }

  @Test func aTinyNegativeElapsedAlsoClampsToZero() {
    let parts = TimerParts(elapsed: -0.001)
    #expect(parts.major == "00:00")
    #expect(parts.hundredths == "00")
  }

  @Test func aLargeNegativeElapsedNeverRendersAMinusSign() {
    let parts = TimerParts(elapsed: -3600)
    #expect(parts.major.contains("-") == false)
    #expect(parts.hundredths.contains("-") == false)
    #expect(parts.major == "00:00")
    #expect(parts.hundredths == "00")
  }

  @Test func justUnderAnHourKeepsItsHundredths() {
    let parts = TimerParts(elapsed: 3599.99)
    #expect(parts.major == "59:59")
    #expect(parts.hundredths == "99")
  }

  // Rounding, not truncation: 59.999 s is one minute on the readout.
  @Test func roundingCarriesUpIntoTheNextMinute() {
    let parts = TimerParts(elapsed: 59.999)
    #expect(parts.major == "01:00")
    #expect(parts.hundredths == "00")
  }

  @Test func belowHalfACentisecondRoundsDownToZero() {
    let parts = TimerParts(elapsed: 0.004)
    #expect(parts.major == "00:00")
    #expect(parts.hundredths == "00")
  }

  @Test func aboveHalfACentisecondRoundsUpToOne() {
    let parts = TimerParts(elapsed: 0.006)
    #expect(parts.major == "00:00")
    #expect(parts.hundredths == "01")
  }

  @Test func roundingCarriesUpIntoTheNextSecond() {
    let parts = TimerParts(elapsed: 1.9999)
    #expect(parts.major == "00:02")
    #expect(parts.hundredths == "00")
  }

  @Test func hundredthsCarryDoesNotLeaveASixtiethSecond() {
    let parts = TimerParts(elapsed: 119.999)
    #expect(parts.major == "02:00")
    #expect(parts.hundredths == "00")
  }

  @Test func singleDigitMinutesAndSecondsAreZeroPadded() {
    let parts = TimerParts(elapsed: 63.07)
    #expect(parts.major == "01:03")
    #expect(parts.hundredths == "07")
  }

  @Test func hundredthsHaveNoLeadingDot() {
    let parts = TimerParts(elapsed: 12.34)
    #expect(parts.hundredths == "34")
    #expect(parts.hundredths.hasPrefix(".") == false)
  }

  @Test func partsAreAlwaysTwoDigitFields() {
    let samples: [TimeInterval] = [0, 0.006, 1.9999, 59.999, 61.5, 599.99, 3599.99, 3600, 3661.23]
    for elapsed in samples {
      let parts = TimerParts(elapsed: elapsed)
      #expect(parts.hundredths.count == 2, "hundredths not two digits for \(elapsed)")
      let fields = parts.major.split(separator: ":", omittingEmptySubsequences: false)
      #expect(fields.count == 2, "major should be MM:SS for \(elapsed)")
      #expect(fields.allSatisfy { $0.count == 2 }, "major fields not two digits for \(elapsed)")
    }
  }

  @Test func secondsNeverReachSixty() {
    let samples: [TimeInterval] = [0, 0.999, 59.999, 60, 119.999, 3599.996, 3600]
    for elapsed in samples {
      let parts = TimerParts(elapsed: elapsed)
      let seconds = parts.major.split(separator: ":", omittingEmptySubsequences: false).last
      #expect(seconds.map { Int($0) ?? -1 } ?? -1 < 60, "seconds field out of range for \(elapsed)")
    }
  }

  @Test(
    "elapsed maps to the specified readout",
    arguments: [
      (TimeInterval(0), "00:00", "00"),
      (TimeInterval(0.004), "00:00", "00"),
      (TimeInterval(0.006), "00:00", "01"),
      (TimeInterval(9.99), "00:09", "99"),
      (TimeInterval(59.999), "01:00", "00"),
      (TimeInterval(60), "01:00", "00"),
      (TimeInterval(61.5), "01:01", "50"),
      (TimeInterval(599.99), "09:59", "99"),
      (TimeInterval(3599.99), "59:59", "99"),
      (TimeInterval(3600), "60:00", "00"),
      (TimeInterval(-5), "00:00", "00"),
    ]
  )
  func readoutMatchesTheTable(elapsed: TimeInterval, major: String, hundredths: String) {
    let parts = TimerParts(elapsed: elapsed)
    #expect(parts.major == major)
    #expect(parts.hundredths == hundredths)
  }

  @Test func partsAreAValueDerivedOnlyFromElapsed() {
    #expect(TimerParts(elapsed: 61.5) == TimerParts(elapsed: 61.5))
    #expect(TimerParts(elapsed: -5) == TimerParts(elapsed: 0))
    #expect(TimerParts(elapsed: 61.5) != TimerParts(elapsed: 61.51))
  }
}

// MARK: - CoachingLevel

struct CoachingLevelTests {

  // Acceptance criterion 6.
  @Test func clearSaysNothingButStillReservesItsSlot() {
    #expect(CoachingLevel.clear.message == "")
    #expect(CoachingLevel.clear.isWarning == false)
    #expect(CoachingLine.slotHeight == 24)
  }

  @Test func lowAsksForALittleMoreProximity() {
    #expect(CoachingLevel.low.message == "Move a little closer")
    #expect(CoachingLevel.low.isWarning == false)
  }

  @Test func hotIsTheOnlyWarning() {
    #expect(CoachingLevel.hot.message == "A little hot \u{2014} ease back")
    #expect(CoachingLevel.hot.isWarning)
    #expect(CoachingLevel.allCases.filter(\.isWarning) == [.hot])
  }

  @Test func hotUsesAnEmDashSurroundedBySpaces() {
    #expect(CoachingLevel.hot.message.contains(" \u{2014} "))
    #expect(CoachingLevel.hot.message.contains("-") == false)
    #expect(CoachingLevel.hot.message.contains("\u{2013}") == false)
  }

  @Test func onlyClearIsSilent() {
    for level in CoachingLevel.allCases where level != .clear {
      #expect(level.message.isEmpty == false, "\(level) should have something to say")
    }
  }

  // The slot is a property of the component, not of the string it happens to
  // hold: an empty message must not collapse the line.
  @Test func theSlotHeightIsTheSameForEveryLevel() {
    for level in CoachingLevel.allCases {
      _ = level.message
      #expect(CoachingLine.slotHeight == 24, "slot height changed for \(level)")
    }
  }

  @Test func thereAreExactlyThreeLevels() {
    #expect(CoachingLevel.allCases.count == 3)
    #expect(CoachingLevel.allCases.contains(.clear))
    #expect(CoachingLevel.allCases.contains(.low))
    #expect(CoachingLevel.allCases.contains(.hot))
  }

  @Test func levelsAreDistinguishableByValue() {
    #expect(CoachingLevel.clear != CoachingLevel.low)
    #expect(CoachingLevel.low != CoachingLevel.hot)
    #expect(CoachingLevel.hot != CoachingLevel.clear)
  }
}
