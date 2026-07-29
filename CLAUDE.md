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
- **The transport** — every record/play transition is decided by
  `Core`'s pure `CaptureMachine.next(state, event) -> (State, [Effect])` (#35),
  tested with `swift test` and no simulator. `CaptureState` decides nothing: it
  holds the state, turns taps and seam callbacks into events, and performs the
  effects it gets back.
- **Enhance** — real on playback (#24, #22, #28, #31, #32). `AudioPlayer` runs an
  `AVAudioEngine` graph: `AVAudioSourceNode` (mono, hosting `Core`'s
  `WarmthRenderCore`) → `AVAudioUnitReverb` (stereo output bus, so the wet field
  widens while the dry stays centred) → `mainMixerNode`. The warmth DSP itself —
  bells, shelf, drive, leveler, ceiling — is pure Swift in `Core`, tested offline
  against WAV fixtures.
- **Screens** — two parallel worlds, and they are not yet joined.
  `RecordingScreen` is the wired one: a Record button, a Play button and a
  `Slider`, unstyled on purpose, and still what `DemoMemosApp` shows. The
  designed ones — `OnboardFeatures`, `DemosListScreen`, `TakeScreen` — are
  assembled from `Components/` and driven entirely by stub state (#51). They
  match `docs/design/` and reach no recorder, player or disk; every state is a
  `#Preview` away and nothing routes between them.
- **Components** — `Waveform`, `TransportButton`, `EnhanceDial`, `TimerReadout`,
  `CoachingLine`, `DemoRow`, `FeatureRow` (#48–#50), over the tokens in
  `DesignTokens.swift` (#43).

**Not built — don't assume these exist:** take persistence, naming, real share
payloads, the `hasOnboarded` flag, any navigation between the three screens, and
count-in (it shipped in #12 and was lost to the #14 rebuild — `TakeScreen` draws
the mode, nothing drives it).

## Vocabulary

The names the code uses for its own ideas. Match them; don't introduce a
synonym for one that already exists.

- **Demo** — a saved recording as the user meets it: a row in the Demos list
  (`DemoListItem`). The product noun, and what a share sends.
- **Take** — the same recording while it is being captured or reviewed on the
  Take screen (`TakeScreen`, `TakeScreenState`). One at a time.
- **Enhance** — the single control, `0…1`. The user-facing name, and the only
  one above the audio layer: `EnhanceDial`, `TakeScreenState.enhance`.
- **warmth** — the DSP parameter Enhance drives, and the only name for it from
  `Audio/` down: `CaptureMachine.warmth`, `setWarmth`, `Core`'s `Warmth*`.
  Enhance is what the user turns; warmth is what the signal gets. The split is
  deliberate — don't rename either into the other.
- **Capture** — recording, as a domain rather than an act: `CaptureMachine`
  decides it, `CaptureMode` is where it is, `CaptureState` performs it.
- **Notice** — anything the capture machine has to tell the user
  (`CaptureNotice`): denied permission, why a take stopped, a failed start.
- **Count-in** — the beats before capture rolls. **Coaching** — the live input
  hint under the timer (`CoachingLevel`: `clear`, `low`, `hot`).
- **Transport** — the record/play/stop pair (`TransportRole`). **Bars** — the
  waveform's levels, `0…1`. **Scrub** — dragging the **playhead**.

## Layout

- `apps/ios` — the app.
  - `DemoMemos.xcodeproj`, scheme `DemoMemos`. Targets: `DemoMemos` and
    `DemoMemosTests` (Swift Testing). iOS 26.5 deployment target, Swift 5
    language mode. There is no UI test target and no CI — `.claude/verify.sh`
    on the Stop hook is the whole safety net, so anything it doesn't run is
    unverified.
  - `DemoMemos/Audio/` — the audio seams, and the main-actor shell the screen
    binds to. The transitions are not here: `CaptureState` performs what
    `Core`'s `CaptureMachine` decides, and holds only what cannot be pure —
    minting take URLs from a folder and a clock, driving the recorder and
    player, and wording notices (`CaptureNotice+Wording.swift`). Imports
    `AVFAudio` but no UI framework. Every seam ships both halves
    (`docs/PRINCIPLES.ios.md` #3); the fakes live in `Fakes.swift`, in the app
    target rather than the test bundle so `#Preview` can reach them.
  - `DemoMemos/Onboarding/`, `DemoMemos/Demos/`, `DemoMemos/Take/` — one folder
    per screen, each holding the screen and its own stub-state type
    (`DemoListItem`, `TakeScreenState`, `TakePresentation`). Feature folders,
    per `docs/PRINCIPLES.md` #1; see `DECISIONS.md` for why `Components/` did
    not get split up with them.
  - `DemoMemos/Components/` — the shared UI layer the three screens compose.
    Assembling a screen means using these; adding to them is a different ticket.
  - `DemoMemos/RecordingScreen.swift` — the unstyled wired screen, beside the
    composition root in `DemoMemosApp.swift`. Scaffolding that `TakeScreen`
    replaces once the audio wiring lands.
  - `Core/` — local SPM package, scheme `Core`, Swift 6 language mode. This is
    the UI-free core (`docs/PRINCIPLES.md` #3). Today: `SampleBuffer`, the
    `AudioProcessor` seam, the warmth chain (`WarmthParameters`,
    `WarmthProcessor`, `WarmthRenderCore`), and the transport reducer under
    `Capture/` (`CaptureMachine` plus the vocabulary it decides over —
    `CaptureMode`, `CaptureNotice`, `StopReason`, `MicrophonePermission`), plus
    an offline WAV harness and fixtures under `Tests/`. Domain models and
    persistence will land here too.
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
- `docs/DECISIONS.md` — why the audio, screen and repo-setup calls were made the
  way they were. Append when a choice would otherwise be re-litigated; don't
  rewrite past entries.

## Commands

- **Verify** (lint + build + unit tests, all stacks): `.claude/verify.sh`
  Runs swift-format lint over every tracked `.swift`, `swift test` on `Core`,
  then `xcodebuild -only-testing:DemoMemosTests` against a booted iPhone
  simulator if there is one, else the first available. Exits non-zero if
  *nothing* was verifiable, so a green tick always means something ran.
- **Single app test**: `xcodebuild test -project apps/ios/DemoMemos.xcodeproj -scheme DemoMemos -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DemoMemosTests/SuiteName/testName`
- **Single Core test**: `swift test --package-path apps/ios/Core --filter testName`
- **Format one file**: `.claude/format.sh <path>` (runs automatically after every
  write). Formatting rules live in that script, not here. It no-ops when the
  formatter (`swift-format`, local `prettier`, `shfmt`) is absent — it never
  installs anything. A repo-wide lint failure prints its own fix; `verify.sh`
  carries the command.

## Signing & on-device builds

For device builds, copy `apps/ios/Config/Local.xcconfig.example` to
`apps/ios/Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`. It is gitignored —
a Team ID isn't a secret but it is personal identity, and this repo is public.
Simulator builds need no signing, so fresh clones and CI work with the file
absent.

Xcode's Signing & Capabilities UI re-stamps `DEVELOPMENT_TEAM` into
`project.pbxproj`. The pre-commit hook rejects that now, so this is a fact to
recognise rather than a rule to remember. Credentials go in neither file; see
`docs/SECURITY.md`.

Opening the project in Xcode also reorders whole `project.pbxproj` sections
(`XCLocalSwiftPackageReference` moves to the end) with nothing changed. That
diff is noise — `git checkout` the file rather than committing it.

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

Merges are squash-only — the PR title and body become the commit, so they carry
the commit convention in `docs/PRINCIPLES.md`.
