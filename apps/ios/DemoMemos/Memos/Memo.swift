import Foundation
import SwiftData

/// The index row for one take. The audio itself lives on disk beside it,
/// addressed by `filename` — see `MemoStore`, which owns the pair so a delete
/// can never leave one without the other.
@Model
final class Memo {
  var id: UUID
  var name: String
  var createdAt: Date
  var duration: TimeInterval
  /// 0...1. Persisted now, cosmetic now: it drives the waveform bloom only.
  /// Storing it means the follow-up that adds real DSP is a playback-time
  /// change with no migration.
  var enhance: Double
  /// Basename only, e.g. "A1B2-….m4a". Resolved against the store's directory.
  var filename: String

  init(
    id: UUID,
    name: String,
    createdAt: Date,
    duration: TimeInterval,
    enhance: Double,
    filename: String
  ) {
    self.id = id
    self.name = name
    self.createdAt = createdAt
    self.duration = duration
    self.enhance = enhance
    self.filename = filename
  }

  /// The date-stamped name a take carries until the user renames it — and the
  /// one it falls back to if a rename is committed blank.
  static func defaultName(for date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
