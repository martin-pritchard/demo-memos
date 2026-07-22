# apps/ios — the DemoMemos iOS app

SwiftUI, single Xcode target. Currently a scaffold: one "Hello World" scene, no
features. See @../../PRINCIPLES.md for where new code goes.

## Vocabulary

- **memo** — the one thing the app is about. Not "note", "entry", or "item".
  The site says "memo" too; the two must not drift.
- **app** / **site** — `apps/ios` and `apps/web`. They share no code, only this
  vocabulary.

## Commands (from the repo root)

| Command | What |
|---|---|
| `make test-ios` | Build and run both test targets |
| `make lint-ios` | Lint without writing |
| `make fmt-ios` | Format all Swift sources |

The last two also run on every file write — you should rarely need them by hand.

## Non-obvious

- **The simulator destination is machine-local.** `make test-ios` defaults to an
  iPhone 17. Override it rather than editing the Makefile:
  `make test-ios IOS_DESTINATION='platform=iOS Simulator,name=iPhone 16'`

- **`Local.xcconfig` is gitignored and absent from fresh clones.** It holds a
  per-developer `DEVELOPMENT_TEAM` for on-device builds; simulator builds don't
  need it. Never put a credential in it — an iOS binary is readable by anyone.
  See @../../docs/security.md.

- **No persistence, networking, or state library — deliberately.** Adding any is
  a decision, not an implementation detail: record it in @../../DECISIONS.md.

- **Unit tests use Swift Testing (`import Testing`), not XCTest.** The UI target
  stays XCUITest — Swift Testing has no UI automation equivalent.
