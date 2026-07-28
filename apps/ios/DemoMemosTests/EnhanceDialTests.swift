import Foundation
import SwiftUI
import Testing

@testable import DemoMemos

struct ToneTests {

  // Acceptance criterion 1.
  @Test func zeroIsDry() {
    #expect(Tone.name(for: 0.0) == "Dry")
  }

  // Acceptance criterion 1.
  @Test func justBelowTheRoomEdgeIsDry() {
    #expect(Tone.name(for: 0.05) == "Dry")
  }

  // Acceptance criterion 1.
  @Test func theRoomEdgeItselfIsRoom() {
    #expect(Tone.name(for: 0.06) == "Room")
  }

  // Acceptance criterion 1.
  @Test func justBelowTheWarmEdgeIsRoom() {
    #expect(Tone.name(for: 0.31) == "Room")
  }

  // Acceptance criterion 1.
  @Test func theWarmEdgeItselfIsWarm() {
    #expect(Tone.name(for: 0.32) == "Warm")
  }

  // Acceptance criterion 1.
  @Test func justBelowTheStudioEdgeIsWarm() {
    #expect(Tone.name(for: 0.59) == "Warm")
  }

  // Acceptance criterion 1.
  @Test func theStudioEdgeItselfIsStudio() {
    #expect(Tone.name(for: 0.60) == "Studio")
  }

  // Acceptance criterion 1.
  @Test func justBelowTheHallEdgeIsStudio() {
    #expect(Tone.name(for: 0.84) == "Studio")
  }

  // Acceptance criterion 1.
  @Test func theHallEdgeItselfIsHall() {
    #expect(Tone.name(for: 0.85) == "Hall")
  }

  // Acceptance criterion 1.
  @Test func oneIsHall() {
    #expect(Tone.name(for: 1.0) == "Hall")
  }

  // Acceptance criterion 1.
  @Test func theDefaultValueIsWarm() {
    #expect(Tone.name(for: 0.5) == "Warm")
  }

  // Acceptance criterion 1. The whole table in one pass, so a band that drifts
  // shows up as a shifted sequence rather than a single isolated failure.
  @Test func everyBoundaryValueResolvesInOrder() {
    let values: [Double] = [0.0, 0.05, 0.06, 0.31, 0.32, 0.59, 0.60, 0.84, 0.85, 1.0]
    let expected = [
      "Dry", "Dry", "Room", "Room", "Warm", "Warm", "Studio", "Studio", "Hall", "Hall",
    ]
    #expect(values.map(Tone.name(for:)) == expected)
  }

  @Test func theBandsAreMonotonicAcrossTheDialsRange() {
    let order = ["Dry": 0, "Room": 1, "Warm": 2, "Studio": 3, "Hall": 4]
    var previous = 0
    for step in 0...1000 {
      let value = Double(step) / 1000.0
      guard let rank = order[Tone.name(for: value)] else {
        Issue.record("Unexpected tone \(Tone.name(for: value)) at \(value)")
        return
      }
      #expect(rank >= previous)
      previous = rank
    }
  }

  @Test func onlyTheFiveNamedTonesAreEverReturned() {
    let allowed: Set<String> = ["Dry", "Room", "Warm", "Studio", "Hall"]
    for step in 0...1000 {
      let value = Double(step) / 1000.0
      #expect(allowed.contains(Tone.name(for: value)))
    }
  }

  @Test func everyBandIsReachableSomewhereInTheRange() {
    var seen: Set<String> = []
    for step in 0...1000 {
      seen.insert(Tone.name(for: Double(step) / 1000.0))
    }
    #expect(seen == ["Dry", "Room", "Warm", "Studio", "Hall"])
  }
}

struct DialGestureTests {

  // Acceptance criterion 2. Half the 300pt track leftward covers the top half
  // of the range: 0.5 + 150/300 == 1.0.
  @Test func aFullLeftwardDragReachesTheTop() {
    #expect(DialGesture.value(from: 0.5, translation: -150, trackWidth: 300) == 1.0)
  }

  // Acceptance criterion 2.
  @Test func aFullRightwardDragReachesTheBottom() {
    #expect(DialGesture.value(from: 0.5, translation: 150, trackWidth: 300) == 0.0)
  }

  // Acceptance criterion 3.
  @Test func draggingLeftRaisesTheValue() {
    let result = DialGesture.value(from: 0.5, translation: -12, trackWidth: 300)
    #expect(result > 0.5)
  }

  // Acceptance criterion 3.
  @Test func draggingRightLowersTheValue() {
    let result = DialGesture.value(from: 0.5, translation: 12, trackWidth: 300)
    #expect(result < 0.5)
  }

  // Acceptance criterion 3. A mid-range move that never touches a clamp, so the
  // arithmetic itself is pinned: 0.5 + 30/300 == 0.6.
  @Test func aMidRangeLeftwardDragIsExactArithmetic() {
    let result = DialGesture.value(from: 0.5, translation: -30, trackWidth: 300)
    #expect(abs(result - 0.6) < 0.0001)
  }

  // Acceptance criterion 3.
  @Test func aMidRangeRightwardDragIsExactArithmetic() {
    let result = DialGesture.value(from: 0.5, translation: 30, trackWidth: 300)
    #expect(abs(result - 0.4) < 0.0001)
  }

  @Test func aNarrowerTrackMovesTheValueFurtherForTheSameDrag() {
    let result = DialGesture.value(from: 0.5, translation: -30, trackWidth: 150)
    #expect(abs(result - 0.7) < 0.0001)
  }

  @Test func aZeroTranslationLeavesTheValueWhereItStarted() {
    #expect(DialGesture.value(from: 0.42, translation: 0, trackWidth: 300) == 0.42)
  }

  // Acceptance criterion 4. -600 on a 300pt track is +2.0 of range; it lands on
  // exactly 1.0, not 2.5, and there is no rubber-band overshoot.
  @Test func draggingWellPastTheTopClampsToOne() {
    #expect(DialGesture.value(from: 0.5, translation: -600, trackWidth: 300) == 1.0)
  }

  // Acceptance criterion 4.
  @Test func draggingWellPastTheBottomClampsToZero() {
    #expect(DialGesture.value(from: 0.5, translation: 600, trackWidth: 300) == 0.0)
  }

  // Acceptance criterion 4.
  @Test func draggingLeftFromTheTopStaysAtTheTop() {
    #expect(DialGesture.value(from: 1.0, translation: -90, trackWidth: 300) == 1.0)
  }

  // Acceptance criterion 4.
  @Test func draggingRightFromTheBottomStaysAtTheBottom() {
    #expect(DialGesture.value(from: 0.0, translation: 90, trackWidth: 300) == 0.0)
  }

  // Acceptance criterion 4. Even an absurd translation stays inside the range.
  @Test func anAbsurdTranslationStillLandsInsideTheRange() {
    let up = DialGesture.value(from: 0.5, translation: -100_000, trackWidth: 300)
    let down = DialGesture.value(from: 0.5, translation: 100_000, trackWidth: 300)
    #expect(up == 1.0)
    #expect(down == 0.0)
  }

  // Acceptance criterion 5. The caller re-anchors on the clamped value, so
  // coming back tracks from 1.0 — not from an accumulated off-scale 2.5.
  @Test func comingBackFromTheTopTracksFromTheClamp() {
    let clamped = DialGesture.value(from: 0.5, translation: -600, trackWidth: 300)
    #expect(clamped == 1.0)
    let returned = DialGesture.value(from: clamped, translation: 150, trackWidth: 300)
    #expect(abs(returned - 0.5) < 0.0001)
  }

  // Acceptance criterion 5.
  @Test func comingBackFromTheBottomTracksFromTheClamp() {
    let clamped = DialGesture.value(from: 0.5, translation: 600, trackWidth: 300)
    #expect(clamped == 0.0)
    let returned = DialGesture.value(from: clamped, translation: -150, trackWidth: 300)
    #expect(abs(returned - 0.5) < 0.0001)
  }

  // Acceptance criterion 6.
  @Test func aZeroWidthTrackReturnsTheStartValueUnchanged() {
    let leftward = DialGesture.value(from: 0.5, translation: -120, trackWidth: 0)
    let rightward = DialGesture.value(from: 0.5, translation: 120, trackWidth: 0)
    #expect(leftward == 0.5)
    #expect(rightward == 0.5)
    #expect(!leftward.isNaN)
    #expect(!rightward.isNaN)
    #expect(leftward.isFinite)
    #expect(rightward.isFinite)
  }

  // Acceptance criterion 7.
  @Test func aNegativeWidthTrackReturnsTheStartValueUnchanged() {
    let leftward = DialGesture.value(from: 0.5, translation: -120, trackWidth: -300)
    let rightward = DialGesture.value(from: 0.5, translation: 120, trackWidth: -300)
    #expect(leftward == 0.5)
    #expect(rightward == 0.5)
    #expect(leftward.isFinite)
    #expect(rightward.isFinite)
  }

  // Acceptance criteria 6 and 7. The degenerate guard returns whatever it was
  // given, including the ends of the range.
  @Test func aDegenerateTrackPreservesEndValuesToo() {
    #expect(DialGesture.value(from: 0.0, translation: -120, trackWidth: 0) == 0.0)
    #expect(DialGesture.value(from: 1.0, translation: 120, trackWidth: 0) == 1.0)
    #expect(DialGesture.value(from: 0.0, translation: -120, trackWidth: -1) == 0.0)
    #expect(DialGesture.value(from: 1.0, translation: 120, trackWidth: -1) == 1.0)
  }

  // The function has no memory of previous calls.
  @Test func theSameArgumentsAlwaysGiveTheSameResult() {
    let first = DialGesture.value(from: 0.5, translation: -30, trackWidth: 300)
    _ = DialGesture.value(from: 0.9, translation: -600, trackWidth: 300)
    _ = DialGesture.value(from: 0.1, translation: 600, trackWidth: 300)
    let second = DialGesture.value(from: 0.5, translation: -30, trackWidth: 300)
    #expect(first == second)
  }

  // A gesture resolved in one call matches the same gesture re-anchored partway,
  // which is what the caller relies on when it re-anchors on clamping.
  @Test func aDragSplitInTwoMatchesTheSameDragInOne() {
    let whole = DialGesture.value(from: 0.2, translation: -90, trackWidth: 300)
    let firstHalf = DialGesture.value(from: 0.2, translation: -45, trackWidth: 300)
    let secondHalf = DialGesture.value(from: firstHalf, translation: -45, trackWidth: 300)
    #expect(abs(whole - secondHalf) < 0.0001)
  }

  // The resolved value always lands in the dial's declared 0...1 range.
  @Test func everyResolvedValueStaysWithinTheDialsRange() {
    let starts: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
    let translations: [CGFloat] = [-900, -300, -75, -1, 0, 1, 75, 300, 900]
    for start in starts {
      for translation in translations {
        let result = DialGesture.value(from: start, translation: translation, trackWidth: 300)
        #expect(result >= 0.0)
        #expect(result <= 1.0)
        #expect(result.isFinite)
      }
    }
  }

  // The seams meet: a resolved value is always a value Tone can name.
  @Test func aResolvedValueAlwaysNamesATone() {
    let allowed: Set<String> = ["Dry", "Room", "Warm", "Studio", "Hall"]
    for translation in stride(from: CGFloat(-600), through: 600, by: 25) {
      let result = DialGesture.value(from: 0.5, translation: translation, trackWidth: 300)
      #expect(allowed.contains(Tone.name(for: result)))
    }
  }
}
