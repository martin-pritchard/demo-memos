import Foundation
import SwiftUI
import Testing

@testable import DemoMemos

struct WaveformModeTests {

  // Criterion 6: an empty take renders the resting line, whatever mode was asked for.
  @Test func anEmptyTakeAlwaysDrawsTheRestingMode() {
    for mode in WaveformMode.allCases {
      #expect(WaveformGeometry.effectiveMode(mode, bars: []) == .resting)
    }
  }

  // A take with content keeps the mode it was asked for.
  @Test func aTakeWithBarsKeepsTheModeItWasAskedFor() {
    let bars: [Float] = [0.2, 0.4, 0.6]
    for mode in WaveformMode.allCases {
      #expect(WaveformGeometry.effectiveMode(mode, bars: bars) == mode)
    }
  }
}

struct WaveformResolvedBarsTests {

  // Criterion 6: the resting line is the resolved geometry for an empty take in every mode.
  @Test func anEmptyTakeResolvesToTheRestingLineInEveryMode() {
    for mode in WaveformMode.allCases {
      let resolved = WaveformGeometry.resolvedBars([], mode: mode)
      #expect(resolved.count == WaveformGeometry.liveBarCount)
      #expect(resolved.allSatisfy { $0 == WaveformGeometry.restingLevel })
    }
  }

  // The resting mode ignores its source entirely rather than drawing it flat.
  @Test func theRestingModeIgnoresItsSource() {
    let source: [Float] = Array(repeating: 0.8, count: 120)
    let resolved = WaveformGeometry.resolvedBars(source, mode: .resting)
    #expect(resolved.count == WaveformGeometry.liveBarCount)
    #expect(resolved.allSatisfy { $0 == WaveformGeometry.restingLevel })
  }

  // A live meter shorter than the window grows in from the right: newest bar last, left padded.
  @Test func aShortLiveStripIsRightAlignedAndPaddedOnTheLeft() {
    let source: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
    let resolved = WaveformGeometry.resolvedBars(source, mode: .live)
    #expect(resolved.count == WaveformGeometry.liveBarCount)
    #expect(Array(resolved.suffix(5)) == source)
    #expect(resolved.prefix(43).allSatisfy { $0 == WaveformGeometry.restingLevel })
  }

  // A live meter longer than the window keeps only its newest bars.
  @Test func anOverLongLiveStripKeepsOnlyItsNewestBars() {
    let source: [Float] = (0..<200).map { Float($0) / 200 }
    let resolved = WaveformGeometry.resolvedBars(source, mode: .live)
    #expect(resolved.count == WaveformGeometry.liveBarCount)
    #expect(resolved == Array(source.suffix(WaveformGeometry.liveBarCount)))
  }

  // Boundary: a live strip of exactly the window length passes through untouched.
  @Test func aLiveStripOfExactlyTheWindowLengthIsUnchanged() {
    let source: [Float] = (0..<48).map { Float($0) / 48 }
    #expect(WaveformGeometry.resolvedBars(source, mode: .live) == source)
  }

  // Scrub draws the take itself: same order, same count, no padding and no truncation.
  @Test func theScrubModePassesItsSourceThrough() {
    let source: [Float] = (0..<200).map { Float($0) / 200 }
    #expect(WaveformGeometry.resolvedBars(source, mode: .scrub) == source)
  }

  // Boundary: a scrub source shorter than the live window is still not padded.
  @Test func aShortScrubSourceIsNotPadded() {
    let source: [Float] = [0.3, 0.7, 0.1]
    #expect(WaveformGeometry.resolvedBars(source, mode: .scrub) == source)
  }
}

struct WaveformBarLayoutTests {

  // Criterion 1: 320pt over an 8pt step is 40 bars, and 322pt is still 40 — no partial bar.
  @Test func aPartialBarIsNotDrawn() {
    #expect(WaveformGeometry.visibleBarCount(width: 320) == 40)
    #expect(WaveformGeometry.visibleBarCount(width: 322) == 40)
    #expect(WaveformGeometry.visibleBarCount(width: 328) == 41)
  }

  // Boundary: exactly one step fits one bar, anything less fits none.
  @Test func aBoxNarrowerThanOneStepShowsNoBars() {
    #expect(WaveformGeometry.visibleBarCount(width: WaveformGeometry.barStep) == 1)
    #expect(WaveformGeometry.visibleBarCount(width: WaveformGeometry.barStep - 1) == 0)
  }

  // Boundary: a zero or negative box is never a negative bar count.
  @Test func aNonPositiveWidthShowsNoBars() {
    #expect(WaveformGeometry.visibleBarCount(width: 0) == 0)
    #expect(WaveformGeometry.visibleBarCount(width: -320) == 0)
  }

  // The bar under the playhead sits exactly on the horizontal centre marker.
  @Test func theBarUnderThePlayheadSitsOnTheCentre() {
    let x = WaveformGeometry.barCentreX(index: 12, playhead: 12, width: 320)
    #expect(abs(x - 160) < 0.0001)
  }

  // Neighbouring bars are one fixed step apart, either side of the marker.
  @Test func barsAreOneStepApartEitherSideOfTheMarker() {
    let ahead = WaveformGeometry.barCentreX(index: 5, playhead: 3, width: 320)
    let behind = WaveformGeometry.barCentreX(index: 2, playhead: 3, width: 320)
    #expect(abs(ahead - 176) < 0.0001)
    #expect(abs(behind - 152) < 0.0001)
  }

  // A fractional playhead offsets the whole strip, so the marker can sit between bars.
  @Test func aFractionalPlayheadOffsetsTheStrip() {
    let x = WaveformGeometry.barCentreX(index: 10, playhead: 9.5, width: 320)
    #expect(abs(x - 164) < 0.0001)
  }

  // The strip is free to run off either edge — the scroll is not clamped to the content.
  @Test func theStripRunsOffTheEdgesUnclamped() {
    let farLeft = WaveformGeometry.barCentreX(index: 0, playhead: 40, width: 320)
    let farRight = WaveformGeometry.barCentreX(index: 80, playhead: 40, width: 320)
    #expect(abs(farLeft - -160) < 0.0001)
    #expect(abs(farRight - 480) < 0.0001)
  }

  // The live meter spreads all 48 bars across the box with a 3pt gap between them.
  @Test func theLiveBarsFillTheWidthWithGapsBetweenThem() {
    let width: CGFloat = 320
    let bar = WaveformGeometry.liveBarWidth(width: width)
    #expect(abs(bar - 179.0 / 48.0) < 0.0001)
    let total = bar * 48 + WaveformGeometry.barGap * 47
    #expect(abs(total - width) < 0.0001)
  }

  // Boundary: a box too narrow for 48 bars floors the bar width at 1pt rather than going to zero.
  @Test func theLiveBarWidthNeverFallsBelowOnePoint() {
    #expect(WaveformGeometry.liveBarWidth(width: 100) == 1)
    #expect(WaveformGeometry.liveBarWidth(width: 0) == 1)
    #expect(WaveformGeometry.liveBarWidth(width: -320) == 1)
  }

  // The first live bar sits against the left edge and the last against the right.
  @Test func theFirstAndLastLiveBarsSitAgainstTheEdges() {
    let width: CGFloat = 320
    let bar = WaveformGeometry.liveBarWidth(width: width)
    let first = WaveformGeometry.liveBarCentreX(index: 0, width: width)
    let last = WaveformGeometry.liveBarCentreX(index: 47, width: width)
    #expect(abs(first - bar / 2) < 0.0001)
    #expect(abs((last + bar / 2) - width) < 0.0001)
  }

  // Live bars advance by one bar plus one gap per index.
  @Test func liveBarsAdvanceByABarAndAGapPerIndex() {
    let width: CGFloat = 320
    let bar = WaveformGeometry.liveBarWidth(width: width)
    let a = WaveformGeometry.liveBarCentreX(index: 10, width: width)
    let b = WaveformGeometry.liveBarCentreX(index: 11, width: width)
    #expect(abs((b - a) - (bar + WaveformGeometry.barGap)) < 0.0001)
  }
}

struct WaveformBarRectTests {

  // A bar extends equally above and below the horizontal midline.
  @Test func aBarIsSymmetricAboutTheMidline() {
    let rect = WaveformGeometry.barRect(level: 0.5, centreX: 100, barWidth: 5, in: 120)
    #expect(abs(rect.minY - 30) < 0.0001)
    #expect(abs(rect.maxY - 90) < 0.0001)
    #expect(abs(rect.midY - 60) < 0.0001)
  }

  // A bar's height is its level times the box height.
  @Test func aBarsHeightIsItsLevelTimesTheBoxHeight() {
    let rect = WaveformGeometry.barRect(level: 0.25, centreX: 100, barWidth: 5, in: 120)
    #expect(abs(rect.height - 30) < 0.0001)
  }

  // Boundary: a silent bar still draws as a cap of at least the bar width.
  @Test func aSilentBarStillDrawsAsACap() {
    let rect = WaveformGeometry.barRect(level: 0, centreX: 100, barWidth: 5, in: 120)
    #expect(abs(rect.height - 5) < 0.0001)
    #expect(abs(rect.origin.y - 57.5) < 0.0001)
  }

  // Boundary: a level whose height would fall under the bar width is lifted to the cap.
  @Test func aNearSilentBarIsLiftedToTheMinimumCap() {
    let rect = WaveformGeometry.barRect(level: 0.01, centreX: 100, barWidth: 5, in: 120)
    #expect(abs(rect.height - 5) < 0.0001)
  }

  // Boundary: a level above 1 clamps to a full-height bar.
  @Test func aLevelAboveOneClampsToAFullHeightBar() {
    let rect = WaveformGeometry.barRect(level: 4, centreX: 100, barWidth: 5, in: 120)
    #expect(abs(rect.height - 120) < 0.0001)
    #expect(rect.origin.y == 0)
  }

  // Boundary: a negative level clamps to zero and so draws the minimum cap.
  @Test func aNegativeLevelClampsToTheMinimumCap() {
    let rect = WaveformGeometry.barRect(level: -3, centreX: 100, barWidth: 5, in: 120)
    #expect(abs(rect.height - 5) < 0.0001)
  }

  // A bar is centred on the x it was given and is exactly the width it was given.
  @Test func aBarIsCentredOnItsGivenX() {
    let rect = WaveformGeometry.barRect(level: 0.5, centreX: 100, barWidth: 5, in: 120)
    #expect(abs(rect.origin.x - 97.5) < 0.0001)
    #expect(abs(rect.width - 5) < 0.0001)
    #expect(abs(rect.midX - 100) < 0.0001)
  }

  // The clip marker is the top 36% of the bar, sharing its x and width.
  @Test func theClipSegmentIsTheTopThirtySixPercentOfTheBar() {
    let bar = CGRect(x: 50, y: 10, width: 5, height: 100)
    let clip = WaveformGeometry.clipRect(in: bar)
    #expect(abs(clip.height - 36) < 0.0001)
    #expect(abs(clip.origin.y - bar.minY) < 0.0001)
    #expect(abs(clip.origin.x - bar.origin.x) < 0.0001)
    #expect(abs(clip.width - bar.width) < 0.0001)
  }

  // The clip segment tracks the bar it is drawn in rather than a fixed height.
  @Test func theClipSegmentScalesWithItsBar() {
    let bar = WaveformGeometry.barRect(level: 0.95, centreX: 100, barWidth: 5, in: 120)
    let clip = WaveformGeometry.clipRect(in: bar)
    #expect(abs(clip.height - bar.height * WaveformGeometry.clipTopFraction) < 0.0001)
    #expect(clip.maxY <= bar.maxY)
  }
}

struct WaveformPlayheadTests {

  // Criterion 3: zero progress puts the marker on the first bar.
  @Test func theMarkerSitsOnTheFirstBarAtZeroProgress() {
    #expect(WaveformGeometry.playhead(progress: 0, barCount: 200) == 0)
    #expect(WaveformGeometry.centredBarIndex(progress: 0, barCount: 200) == 0)
  }

  // Criterion 3: full progress puts the marker on the last bar.
  @Test func theMarkerSitsOnTheLastBarAtFullProgress() {
    #expect(abs(WaveformGeometry.playhead(progress: 1, barCount: 200) - 199) < 0.0001)
    #expect(WaveformGeometry.centredBarIndex(progress: 1, barCount: 200) == 199)
  }

  // Criterion 2: with 200 bars, half way through sits under bar 100.
  @Test func theCentredBarIsTheMidpointOfTheTake() {
    #expect(abs(WaveformGeometry.playhead(progress: 0.5, barCount: 200) - 99.5) < 0.0001)
    #expect(WaveformGeometry.centredBarIndex(progress: 0.5, barCount: 200) == 100)
  }

  // Criterion 8: progress above 1 clamps rather than scrolling the strip off into space.
  @Test func progressAboveOneClampsToTheLastBar() {
    #expect(abs(WaveformGeometry.playhead(progress: 12.5, barCount: 200) - 199) < 0.0001)
    #expect(WaveformGeometry.centredBarIndex(progress: 12.5, barCount: 200) == 199)
  }

  // Criterion 8: progress below 0 clamps to the first bar.
  @Test func progressBelowZeroClampsToTheFirstBar() {
    #expect(WaveformGeometry.playhead(progress: -4, barCount: 200) == 0)
    #expect(WaveformGeometry.centredBarIndex(progress: -4, barCount: 200) == 0)
  }

  // Boundary: a one-bar take has nowhere to scroll to.
  @Test func aSingleBarTakeKeepsThePlayheadAtZero() {
    #expect(WaveformGeometry.playhead(progress: 0.7, barCount: 1) == 0)
    #expect(WaveformGeometry.centredBarIndex(progress: 0.7, barCount: 1) == 0)
  }

  // Boundary: no bars at all is index zero, not a crash or a negative index.
  @Test func anEmptyTakeCentresOnIndexZero() {
    #expect(WaveformGeometry.playhead(progress: 0.5, barCount: 0) == 0)
    #expect(WaveformGeometry.centredBarIndex(progress: 0.5, barCount: 0) == 0)
  }

  // The centred index rounds a half away from zero rather than truncating.
  @Test func theCentredBarIndexRoundsToTheNearestBar() {
    #expect(WaveformGeometry.centredBarIndex(progress: 0.25, barCount: 3) == 1)
    #expect(WaveformGeometry.centredBarIndex(progress: 0.24, barCount: 3) == 0)
    #expect(WaveformGeometry.centredBarIndex(progress: 0.26, barCount: 3) == 1)
  }

  // The centred index is always a usable subscript into the take.
  @Test func theCentredBarIndexStaysInsideTheTake() {
    for step in 0...20 {
      let progress = Double(step) / 10 - 0.5
      let index = WaveformGeometry.centredBarIndex(progress: progress, barCount: 7)
      #expect(index >= 0 && index < 7)
    }
  }
}

struct WaveformVisibleRangeTests {

  // Criterion 2: the visible window is centred on the marked bar.
  @Test func theVisibleWindowIsCentredOnTheMarkedBar() {
    let range = WaveformGeometry.visibleRange(progress: 0.5, barCount: 200, width: 320)
    #expect(range == 78..<122)
    #expect(range.contains(100))
    let midpoint = Double(range.lowerBound + range.upperBound) / 2
    #expect(abs(midpoint - 100) < 0.0001)
  }

  // Criterion 7: drawing cost is bounded by the box, not by how long the take is.
  @Test func theVisibleWindowIsBoundedByTheBoxNotTheTakeLength() {
    let short = WaveformGeometry.visibleRange(progress: 0.5, barCount: 2_000, width: 320)
    let long = WaveformGeometry.visibleRange(progress: 0.5, barCount: 200_000, width: 320)
    #expect(short.count == long.count)
    #expect(long.count == 44)
    #expect(long.count < WaveformGeometry.visibleBarCount(width: 320) + 6)
  }

  // A wider box shows more bars; a narrower one shows fewer.
  @Test func aWiderBoxShowsMoreBars() {
    let narrow = WaveformGeometry.visibleRange(progress: 0.5, barCount: 2_000, width: 160)
    let wide = WaveformGeometry.visibleRange(progress: 0.5, barCount: 2_000, width: 640)
    #expect(narrow.count < wide.count)
  }

  // The window clamps at the start of the take rather than running to negative indices.
  @Test func theWindowClampsToTheStartOfTheTake() {
    let range = WaveformGeometry.visibleRange(progress: 0, barCount: 200, width: 320)
    #expect(range == 0..<22)
  }

  // The window clamps at the end of the take rather than running past the last bar.
  @Test func theWindowClampsToTheEndOfTheTake() {
    let range = WaveformGeometry.visibleRange(progress: 1, barCount: 200, width: 320)
    #expect(range == 178..<200)
  }

  // Boundary: an empty take has no visible bars.
  @Test func anEmptyTakeHasNoVisibleBars() {
    #expect(WaveformGeometry.visibleRange(progress: 0.5, barCount: 0, width: 320).isEmpty)
  }

  // Boundary: a zero or negative box has no visible bars.
  @Test func aNonPositiveWidthHasNoVisibleBars() {
    #expect(WaveformGeometry.visibleRange(progress: 0.5, barCount: 200, width: 0).isEmpty)
    #expect(WaveformGeometry.visibleRange(progress: 0.5, barCount: 200, width: -320).isEmpty)
  }

  // A take shorter than the window shows all of it and nothing beyond it.
  @Test func aShortTakeIsFullyVisible() {
    let range = WaveformGeometry.visibleRange(progress: 0.5, barCount: 6, width: 320)
    #expect(range == 0..<6)
  }

  // Every index the window yields is a valid subscript into the take.
  @Test func everyVisibleIndexIsAValidBarIndex() {
    for step in 0...10 {
      let range = WaveformGeometry.visibleRange(
        progress: Double(step) / 10, barCount: 137, width: 393)
      #expect(range.lowerBound >= 0)
      #expect(range.upperBound <= 137)
      #expect(range.lowerBound <= range.upperBound)
    }
  }
}

struct WaveformScrubTests {

  // Criterion 4: an 80pt leftward drag over 8pt bars advances exactly 10 bars.
  @Test func aLeftwardDragAdvancesOneBarPerStep() {
    let progress = WaveformGeometry.scrubProgress(from: 0, translation: -80, barCount: 200)
    #expect(abs(progress - 10.0 / 199.0) < 0.0001)
    #expect(abs(WaveformGeometry.playhead(progress: progress, barCount: 200) - 10) < 0.0001)
  }

  // Criterion 4: the drag is 1:1 with bar geometry, so the bars moved do not depend on take length.
  @Test func aDragMovesTheSameBarsWhateverTheTakeLength() {
    let short = WaveformGeometry.scrubProgress(from: 0, translation: -80, barCount: 200)
    let long = WaveformGeometry.scrubProgress(from: 0, translation: -80, barCount: 4_000)
    #expect(abs(WaveformGeometry.playhead(progress: short, barCount: 200) - 10) < 0.0001)
    #expect(abs(WaveformGeometry.playhead(progress: long, barCount: 4_000) - 10) < 0.0001)
  }

  // A rightward drag rewinds by the same geometry.
  @Test func aRightwardDragRewinds() {
    let progress = WaveformGeometry.scrubProgress(from: 0.5, translation: 80, barCount: 200)
    #expect(abs(progress - (0.5 - 10.0 / 199.0)) < 0.0001)
  }

  // A drag of nothing leaves the progress where it was.
  @Test func aZeroDragLeavesProgressUnchanged() {
    #expect(WaveformGeometry.scrubProgress(from: 0.37, translation: 0, barCount: 200) == 0.37)
  }

  // Criterion 5: a drag past the end clamps to 1.0.
  @Test func draggingPastTheEndClampsToOne() {
    #expect(WaveformGeometry.scrubProgress(from: 0.9, translation: -100_000, barCount: 200) == 1)
  }

  // Criterion 5: a drag before the start clamps to 0.0.
  @Test func draggingBeforeTheStartClampsToZero() {
    #expect(WaveformGeometry.scrubProgress(from: 0.1, translation: 100_000, barCount: 200) == 0)
  }

  // A starting progress outside 0…1 is clamped before the drag is applied.
  @Test func aStartingProgressOutsideTheRangeIsClampedFirst() {
    let above = WaveformGeometry.scrubProgress(from: 1.8, translation: 8, barCount: 200)
    #expect(abs(above - (1 - 1.0 / 199.0)) < 0.0001)
    let below = WaveformGeometry.scrubProgress(from: -0.8, translation: -8, barCount: 200)
    #expect(abs(below - (1.0 / 199.0)) < 0.0001)
  }

  // Boundary: a one-bar take has nothing to scrub, and must not divide by zero.
  @Test func aSingleBarTakeReturnsTheStartingProgress() {
    let progress = WaveformGeometry.scrubProgress(from: 0.3, translation: -800, barCount: 1)
    #expect(progress == 0.3)
    #expect(progress.isFinite)
  }

  // Boundary: an empty take likewise returns its clamped starting progress.
  @Test func anEmptyTakeReturnsTheClampedStartingProgress() {
    #expect(WaveformGeometry.scrubProgress(from: 0.4, translation: -800, barCount: 0) == 0.4)
    #expect(WaveformGeometry.scrubProgress(from: 1.9, translation: -800, barCount: 0) == 1)
    #expect(WaveformGeometry.scrubProgress(from: -1.9, translation: 800, barCount: 0) == 0)
  }

  // A very large drag stays inside the range and stays finite.
  @Test func aHugeDragStaysWithinTheRange() {
    let values: [CGFloat] = [-1_000_000, -5_000, 5_000, 1_000_000]
    for translation in values {
      let progress = WaveformGeometry.scrubProgress(
        from: 0.5, translation: translation, barCount: 3)
      #expect(progress.isFinite)
      #expect(progress >= 0 && progress <= 1)
    }
  }
}

struct WaveformClipTests {

  // Criterion 9: a bar at exactly the clip level clips.
  @Test func aBarAtTheClipLevelClips() {
    #expect(WaveformGeometry.clips(WaveformGeometry.clipLevel, in: .live))
    #expect(WaveformGeometry.clips(0.9, in: .live))
  }

  // Criterion 9: a bar just under the clip level does not.
  @Test func aBarJustBelowTheClipLevelDoesNotClip() {
    #expect(!WaveformGeometry.clips(0.899, in: .live))
  }

  // A bar above the clip level clips.
  @Test func aBarAboveTheClipLevelClips() {
    #expect(WaveformGeometry.clips(1, in: .live))
  }

  // Criterion 9: clipping is a live-meter idea only — never shown at rest or while scrubbing.
  @Test func onlyTheLiveModeClips() {
    for mode in WaveformMode.allCases where mode != .live {
      #expect(!WaveformGeometry.clips(1, in: mode))
      #expect(!WaveformGeometry.clips(0.9, in: mode))
      #expect(!WaveformGeometry.clips(0.95, in: mode))
    }
  }

  // A quiet bar never clips in any mode.
  @Test func aQuietBarNeverClips() {
    for mode in WaveformMode.allCases {
      #expect(!WaveformGeometry.clips(0, in: mode))
      #expect(!WaveformGeometry.clips(WaveformGeometry.restingLevel, in: mode))
    }
  }
}

struct WaveformFadeTests {

  // The bar under the marker is at the fade floor, so the marker separates from the amber.
  @Test func theBarUnderTheMarkerIsAtTheFadeFloor() {
    let opacity = WaveformGeometry.playedOpacity(index: 40, playhead: 40)
    #expect(opacity == WaveformGeometry.fadeFloor)
  }

  // A bar a full fade span behind the marker is fully opaque.
  @Test func aBarAFullSpanBehindIsFullyOpaque() {
    let opacity = WaveformGeometry.playedOpacity(index: 34, playhead: 40)
    #expect(abs(opacity - 1) < 0.0001)
  }

  // Half a span behind the marker is half way up the ramp.
  @Test func aBarHalfASpanBehindIsHalfFaded() {
    let opacity = WaveformGeometry.playedOpacity(index: 37, playhead: 40)
    #expect(abs(opacity - 0.725) < 0.0001)
  }

  // Beyond the fade span the ramp holds at fully opaque rather than overshooting.
  @Test func barsBeyondTheFadeSpanStayFullyOpaque() {
    #expect(abs(WaveformGeometry.playedOpacity(index: 0, playhead: 40) - 1) < 0.0001)
    #expect(abs(WaveformGeometry.playedOpacity(index: 10, playhead: 400) - 1) < 0.0001)
  }

  // Boundary: bars ahead of the marker are unplayed and sit at the floor, not below it.
  @Test func barsAheadOfTheMarkerSitAtTheFadeFloor() {
    #expect(WaveformGeometry.playedOpacity(index: 42, playhead: 40) == WaveformGeometry.fadeFloor)
    #expect(WaveformGeometry.playedOpacity(index: 900, playhead: 40) == WaveformGeometry.fadeFloor)
  }

  // The ramp never decreases as bars recede from the marker, and stays inside the floor and 1.
  @Test func theFadeRampIsMonotonicAndBounded() {
    var previous = WaveformGeometry.playedOpacity(index: 50, playhead: 40)
    for index in stride(from: 49, through: 30, by: -1) {
      let opacity = WaveformGeometry.playedOpacity(index: index, playhead: 40)
      #expect(opacity >= previous - 0.0001)
      #expect(opacity >= WaveformGeometry.fadeFloor - 0.0001)
      #expect(opacity <= 1.0001)
      previous = opacity
    }
  }

  // A fractional playhead still lands on the ramp between two whole bars.
  @Test func aFractionalPlayheadFadesBetweenBars() {
    let opacity = WaveformGeometry.playedOpacity(index: 37, playhead: 40.5)
    #expect(abs(opacity - (0.45 + 0.55 * 3.5 / 6)) < 0.0001)
  }
}

struct WaveformBloomTests {

  // Both endpoints, lower: no Enhance is the faintest, smallest, softest bloom.
  @Test func theBloomIsSmallestAtZeroEnhance() {
    let bloom = WaveformGeometry.bloom(enhance: 0, in: CGSize(width: 300, height: 120))
    #expect(abs(bloom.opacity - 0.09) < 0.0001)
    #expect(abs(bloom.size.width - 174) < 0.0001)
    #expect(abs(bloom.size.height - 141.6) < 0.0001)
    #expect(abs(bloom.blurRadius - 6) < 0.0001)
  }

  // Both endpoints, upper: full Enhance is the widest, strongest, softest bloom.
  @Test func theBloomIsLargestAtFullEnhance() {
    let bloom = WaveformGeometry.bloom(enhance: 1, in: CGSize(width: 300, height: 120))
    #expect(abs(bloom.opacity - 0.24) < 0.0001)
    #expect(abs(bloom.size.width - 372) < 0.0001)
    #expect(abs(bloom.size.height - 249.6) < 0.0001)
    #expect(abs(bloom.blurRadius - 15) < 0.0001)
  }

  // The ramp between the endpoints is linear.
  @Test func theBloomRampsLinearlyBetweenTheEndpoints() {
    let bloom = WaveformGeometry.bloom(enhance: 0.5, in: CGSize(width: 300, height: 120))
    #expect(abs(bloom.opacity - 0.165) < 0.0001)
    #expect(abs(bloom.size.width - 273) < 0.0001)
    #expect(abs(bloom.size.height - 195.6) < 0.0001)
    #expect(abs(bloom.blurRadius - 10.5) < 0.0001)
  }

  // Boundary: an Enhance value outside 0…1 clamps to the endpoint bloom.
  @Test func anEnhanceOutsideTheRangeIsClamped() {
    let box = CGSize(width: 300, height: 120)
    #expect(
      WaveformGeometry.bloom(enhance: -2, in: box)
        == WaveformGeometry.bloom(
          enhance: 0, in: box))
    #expect(
      WaveformGeometry.bloom(enhance: 7, in: box)
        == WaveformGeometry.bloom(
          enhance: 1, in: box))
  }

  // The bloom is always taller than the box it sits behind, so it reads as an aura.
  @Test func theBloomAlwaysOverflowsTheBoxVertically() {
    let box = CGSize(width: 300, height: 120)
    for step in 0...4 {
      let bloom = WaveformGeometry.bloom(enhance: Double(step) / 4, in: box)
      #expect(bloom.size.height > box.height)
    }
  }

  // Boundary: a zero-sized box gives a zero-sized bloom, with the opacity and blur still valid.
  @Test func aZeroSizedBoxProducesAZeroSizedBloom() {
    let bloom = WaveformGeometry.bloom(enhance: 0.5, in: .zero)
    #expect(bloom.size.width == 0)
    #expect(bloom.size.height == 0)
    #expect(abs(bloom.opacity - 0.165) < 0.0001)
    #expect(abs(bloom.blurRadius - 10.5) < 0.0001)
  }
}

struct WaveformDegenerateInputTests {

  // No layout value goes non-finite for a degenerate box or take.
  @Test func everyGeometryValueIsFiniteForDegenerateBoxes() {
    let widths: [CGFloat] = [-320, 0, 1, 320]
    let counts = [0, 1, 2, 200]
    for width in widths {
      #expect(WaveformGeometry.liveBarWidth(width: width).isFinite)
      #expect(WaveformGeometry.liveBarCentreX(index: 0, width: width).isFinite)
      #expect(WaveformGeometry.liveBarCentreX(index: 47, width: width).isFinite)
      for count in counts {
        let head = WaveformGeometry.playhead(progress: 0.5, barCount: count)
        #expect(head.isFinite)
        #expect(WaveformGeometry.barCentreX(index: 0, playhead: head, width: width).isFinite)
        #expect(
          WaveformGeometry.visibleRange(
            progress: 0.5, barCount: count, width: width
          ).lowerBound >= 0)
      }
    }
  }

  // A negative bar count is treated as nothing to draw rather than producing a negative playhead.
  @Test func aNegativeBarCountDrawsNothing() {
    #expect(WaveformGeometry.playhead(progress: 0.5, barCount: -5) == 0)
    #expect(WaveformGeometry.centredBarIndex(progress: 0.5, barCount: -5) == 0)
    #expect(WaveformGeometry.visibleRange(progress: 0.5, barCount: -5, width: 320).isEmpty)
  }

  // A bar rect stays finite in a zero-height box.
  @Test func theBarRectIsFiniteInAZeroHeightBox() {
    let rect = WaveformGeometry.barRect(level: 0.5, centreX: 0, barWidth: 5, in: 0)
    #expect(rect.origin.x.isFinite)
    #expect(rect.origin.y.isFinite)
    #expect(rect.width.isFinite)
    #expect(rect.height.isFinite)
    #expect(WaveformGeometry.clipRect(in: rect).height.isFinite)
  }

  // The played fade stays inside its range for extreme index and playhead values.
  @Test func theFadeStaysBoundedForExtremeIndices() {
    let cases: [(Int, Double)] = [(0, 0), (0, 1_000_000), (1_000_000, 0), (-50, 10)]
    for (index, playhead) in cases {
      let opacity = WaveformGeometry.playedOpacity(index: index, playhead: playhead)
      #expect(opacity.isFinite)
      #expect(opacity >= WaveformGeometry.fadeFloor - 0.0001)
      #expect(opacity <= 1.0001)
    }
  }
}
