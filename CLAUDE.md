# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

# Demo Memos

Voice Memos for song ideas: one-tap capture, a single **Enhance** dial, and a
list of takes. SwiftUI, iPhone only. See `README.md` for the product framing.

**Current state: a working capture → playback loop behind a deliberately
unstyled screen.** One take at a time, held as a file URL; the README describes
the finished product, not the tree. What exists today:

- **Capture** — `AudioRecorder` writes 48 kHz mono 24-bit linear PCM WAV through
  `AVAudioRecorder` (#18). `AudioSession` is the only place that calls
  `setCategory`. `RecordingRepair` rebuilds the RIFF header of a take that a
  jetsam kill left unfinalised.
- **Enhance** — real on playback (#24, #22, #28, #31, #32). `AudioPlayer` runs an
  `AVAudioEngine` graph: `AVAudioSourceNode` (mono, hosting `Core`'s
  `WarmthRenderCore`) → `AVAudioUnitReverb` (stereo output bus, so the wet field
  widens while the dry stays centred) → `mainMixerNode`. The warmth DSP itself —
  bells, shelf, drive, leveler, ceiling — is pure Swift in `Core`, tested offline
  against WAV fixtures.
- **Screen** — `RecordingScreen`: a Record button, a Play button, and a `Slider`
  for Enhance. Unstyled on purpose; `docs/design/` is the target.

**Not built — don't assume these exist:** the Demos list, take persistence,
naming, share, onboarding, count-in (it shipped in #12 and was lost to the #14
rebuild), and the waveform (#36, #37).

## Layout

- `apps/ios` — the app.
  - `DemoMemos.xcodeproj`, scheme `DemoMemos`. Targets: `DemoMemos`,
    `DemoMemosTests` (Swift Testing), `DemoMemosUITests` (XCTest).
    iOS 26.5 deployment target, Swift 5 language mode.
  - `DemoMemos/Audio/` — the audio seams and the state machine the screen binds
    to. Imports `AVFAudio` but no UI framework. Every seam ships both halves
    (`docs/PRINCIPLES.ios.md` #3); the fakes live in `Fakes.swift`, in the app
    target rather than the test bundle so `#Preview` can reach them.
  - `DemoMemos/RecordingScreen.swift` — the only screen, beside the composition
    root in `DemoMemosApp.swift`. One screen does not yet earn a feature folder.
  - `Core/` — local SPM package, scheme `Core`, Swift 6 language mode. This is
    the UI-free core (`docs/PRINCIPLES.md` #3). Today: `SampleBuffer`, the
    `AudioProcessor` seam, and the warmth chain (`WarmthParameters`,
    `WarmthProcessor`, `WarmthRenderCore`), plus an offline WAV harness and
    fixtures under `Tests/`. Domain models and persistence will land here too.
    **It must not import SwiftUI or UIKit** — that boundary is what keeps it
    testable with `swift test`, no simulator.
  - `Config/` — `Shared.xcconfig` is the target's `baseConfigurationReference`
    and holds no identity; it `#include?`s the gitignored `Local.xcconfig`.
- `apps/web` — placeholder. No stack chosen, no manifest, `apps/web/CLAUDE.md`
  still empty. `.claude/verify.sh` skips it loudly rather than pretending.
- `docs/PRINCIPLES.md` — placement rules. Read it before creating or moving
  files. Plugin-managed and overwritten wholesale on update, so never hand-edit
  it; project-specific adaptations go here or in the stack appendix.
- `docs/PRINCIPLES.ios.md` — the iOS appendix, and **not** plugin-managed. Hand-
  written Swift/Apple-framework rules live here. Read it before writing audio
  code: #1 is a hard rule about realtime threads that is expensive to discover
  by violating.
- `docs/SECURITY.md` — secret-handling rules. Read before adding any credential,
  key, or `.env`; the "a key in an iOS binary is not secret" section is a real
  architectural constraint, not boilerplate.
- `docs/design/` — the design handoff bundle: `README.md` is the implementation
  brief (tokens, screens, states, motion), `demo-memo.dc.html` the full doc, the
  `.jsx` files HTML/React prototypes. **They are references, not code to port** —
  recreate them in SwiftUI with system components. `app-icon/*.png` ships as-is.
  `screen-states.md` is the state inventory read out of the bundle — read it
  before building a screen: it lists the states the designs *don't* cover
  (permissions, interruptions, failures, save semantics) and where the bundle
  contradicts itself. Those are open questions, not settled design.
- `docs/DECISIONS.md` — why the audio calls were made the way they were. Append
  when a choice would otherwise be re-litigated; don't rewrite past entries.

## Commands

- **Verify** (lint + build + unit tests, all stacks): `.claude/verify.sh`
  Runs swift-format lint over every tracked `.swift`, `swift test` on `Core`,
  then `xcodebuild -only-testing:DemoMemosTests` against a booted iPhone
  simulator if there is one, else the first available. UI tests are CI's job.
  Exits non-zero if *nothing* was verifiable, so a green tick always means
  something ran.
- **Single app test**: `xcodebuild test -project apps/ios/DemoMemos.xcodeproj -scheme DemoMemos -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DemoMemosTests/SuiteName/testName`
- **Single Core test**: `swift test --package-path apps/ios/Core --filter testName`
- **Format one file**: `.claude/format.sh <path>` (runs automatically after every
  write). Formatting rules live in that script, not here. It no-ops when the
  formatter (`swift-format`, local `prettier`, `shfmt`) is absent — it never
  installs anything.
- **Fix a lint failure across the repo**:
  `git ls-files '*.swift' | xargs -n1 .claude/format.sh`
  Needed after Xcode generates a file, since Xcode indents 4 and swift-format
  indents 2. The write hook only fires on Claude's edits.

## Signing & on-device builds

For device builds, copy `apps/ios/Config/Local.xcconfig.example` to
`apps/ios/Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`. It is gitignored —
a Team ID isn't a secret but it is personal identity, and this repo is public.
Simulator builds need no signing, so fresh clones and CI work with the file
absent.

Never let a `DEVELOPMENT_TEAM` land in `project.pbxproj` — Xcode's Signing &
Capabilities UI re-stamps it, so check before committing. Credentials go in
neither file; see `docs/SECURITY.md`.

## Repo setup (once per clone)

```
brew install gitleaks
git config core.hooksPath .githooks
```

The pre-commit hook fails closed: no gitleaks, no commit. This repo is public.

## Conventions

Placement rules live in `docs/PRINCIPLES.md` — read it before creating or moving
files. Swift-specific rules are in `docs/PRINCIPLES.ios.md`.

Seam and definition-of-done rules live in the `sdlc:build-rules` skill. Anything
touching capture, playback, the Enhance dial or `apps/ios/DemoMemos/Audio/` goes
through the `ios-audio` skill (checked in at `.claude/skills/ios-audio/`) — it
carries the effect-ladder reasoning the `DECISIONS.md` entries lean on.

Merges are squash-only — the PR title and body become the commit, so they follow
Conventional Commits like everything else.
