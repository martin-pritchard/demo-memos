import Core
import Foundation
import Testing

enum FixtureError: Error, Equatable {
  case notFound(String)
}

/// The committed fixtures, keyed by the name `loadFixture` takes. Regeneration
/// walks this table; a test names one entry.
let committedFixtures: [(name: String, buffer: SampleBuffer)] = [
  ("sine-18", Fixtures.sine(dbFS: -18)),
  ("sine-6", Fixtures.sine(dbFS: -6)),
  ("sine-0_5", Fixtures.sine(dbFS: -0.5)),
  ("noise-20", Fixtures.whiteNoise(rmsDBFS: -20)),
  ("silence", Fixtures.silence()),
  ("impulse", Fixtures.impulse()),
  ("sine-18-dc", Fixtures.sineWithDC(dbFS: -18, dc: 0.05)),
  // real-take.wav is a real iPhone export, not generated — it is committed as-is.
]

/// Reads a committed `.wav` from the test bundle through the pure-Swift reader —
/// the round-trip the acceptance criteria measure against.
func loadFixture(_ name: String) throws -> SampleBuffer {
  guard let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures") else {
    throw FixtureError.notFound(name)
  }
  return try WAVFile.read(Data(contentsOf: url))
}

/// Regenerating the fixtures writes into the source tree, so it is gated on an
/// env var and never runs in a normal `swift test`. Run it with
/// `REGENERATE_FIXTURES=1 swift test --filter regenerateCommittedFixtures` after
/// changing a generator, then commit the new bytes.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["REGENERATE_FIXTURES"] != nil))
struct FixtureRegeneration {
  @Test func regenerateCommittedFixtures() throws {
    let directory = URL(filePath: #filePath)
      .deletingLastPathComponent()  // AudioHarness/
      .deletingLastPathComponent()  // CoreTests/
      .appending(path: "Fixtures")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for fixture in committedFixtures {
      let data = try WAVFile.encode(fixture.buffer)
      try data.write(to: directory.appending(path: "\(fixture.name).wav"))
    }
  }
}
