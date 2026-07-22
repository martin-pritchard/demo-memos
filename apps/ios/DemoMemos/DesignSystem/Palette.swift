import SwiftUI
import UIKit

/// The design's tokens. Orange is the single accent — waveform, record button
/// and Enhance control — over an otherwise system-neutral surface.
enum Palette {
  static let accent = Color(red: 1.0, green: 0.624, blue: 0.039)  // #ff9f0a
  static let accentDeep = Color(red: 1.0, green: 0.478, blue: 0.0)  // #ff7a00

  /// The accent as it reads on each appearance: deep in light, bright in dark.
  static let accentText = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1)
        : UIColor(red: 1.0, green: 0.478, blue: 0.0, alpha: 1)
    })

  static let pageBackground = LinearGradient(
    colors: [
      Color(
        uiColor: UIColor {
          $0.userInterfaceStyle == .dark
            ? UIColor(white: 0.11, alpha: 1)
            : UIColor(red: 0.984, green: 0.984, blue: 0.992, alpha: 1)
        }),
      Color(
        uiColor: UIColor {
          $0.userInterfaceStyle == .dark
            ? UIColor(white: 0.0, alpha: 1)
            : UIColor(red: 0.949, green: 0.949, blue: 0.965, alpha: 1)
        }),
    ],
    startPoint: .top,
    endPoint: .bottom
  )

  /// List card — solid white on light, the design's #2c2c2e on dark.
  static let card = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.172, alpha: 1) : .white
    })

  static let barIdle = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.921, green: 0.921, blue: 0.960, alpha: 0.22)
        : UIColor(red: 0.470, green: 0.470, blue: 0.502, alpha: 0.28)
    })

  /// The ring around the Record / Stop / Resume button.
  static let transportRing = Color(
    uiColor: UIColor {
      $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.24) : UIColor(white: 0, alpha: 0.14)
    })

  /// The design's `warmColor(w)`: neutral warm grey at 0 → amber at 1.
  /// The played side of the waveform rides this ramp with Enhance.
  static func warm(_ amount: Double, opacity: Double = 1) -> Color {
    let w = min(max(amount, 0), 1)
    let red = 0.690 + (0.847 - 0.690) * w
    let green = 0.675 + (0.533 - 0.675) * w
    let blue = 0.647 + (0.114 - 0.647) * w
    return Color(red: red, green: green, blue: blue, opacity: opacity)
  }

  /// The design's `toneName` — the word beside the Enhance dial.
  static func toneName(_ value: Double) -> String {
    switch value {
    case ..<0.06: "Dry"
    case ..<0.32: "Room"
    case ..<0.62: "Warm"
    case ..<0.85: "Studio"
    default: "Hall"
    }
  }
}

extension TimeInterval {
  /// `0:37` — the list's length column and the share sheet's subtitle.
  var shortTimeLabel: String {
    let total = Int(rounded())
    return "\(total / 60):\(String(format: "%02d", total % 60))"
  }

  /// `mm:ss` and hundredths, split so the transport can dim the decimals.
  var transportLabel: (major: String, hundredths: String) {
    let clamped = max(self, 0)
    let minutes = Int(clamped) / 60
    let seconds = Int(clamped) % 60
    let hundredths = Int(clamped * 100) % 100
    return (
      String(format: "%02d:%02d", minutes, seconds),
      String(format: ".%02d", hundredths)
    )
  }
}

extension Date {
  /// `Today · 3:14 PM` — the list row's middle line.
  var listMetaLabel: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(self) {
      return "Today · \(formatted(date: .omitted, time: .shortened))"
    }
    if calendar.isDateInYesterday(self) {
      return "Yesterday"
    }
    if let days = calendar.dateComponents([.day], from: self, to: .now).day, days < 7 {
      return formatted(.dateTime.weekday(.wide))
    }
    return formatted(date: .abbreviated, time: .omitted)
  }
}
