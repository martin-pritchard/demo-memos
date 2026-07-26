# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Demo Memos

Voice Memos for song ideas: one-tap capture, a single **Enhance** dial, and a
list of takes. SwiftUI, iPhone only. See `README.md` for the product framing.

## Layout

- `apps/ios` — the app. Xcode project `DemoMemos.xcodeproj`, scheme `DemoMemos`.
  Targets: `DemoMemos`, `DemoMemosTests` (unit, Swift Testing), `DemoMemosUITests` (XCTest).
  iOS 26.5 deployment target, Swift 5 language mode.
  **`apps/ios/CLAUDE.md` holds the iOS mechanisms — folder shape, UI-state
  pattern, seams, native-by-default rules. Read it before touching Swift.**
- `apps/web` — placeholder. No stack chosen, no manifest, `apps/web/CLAUDE.md`
  still empty. `.claude/verify.sh` skips it loudly rather than pretending.
- `design` — design source and export helpers (a generated `dc-runtime` bundle
  plus JSX scenes). Not shipped code, not built by anything here.
- `docs/SECURITY.md` — secret-handling rules. Read before adding any credential,
  key, or `.env`; the "a key in an iOS binary is not secret" section is a real
  architectural constraint, not boilerplate.
- `docs/DECISIONS.md` — what was decided or deliberately deferred, and why.
  Check it before "fixing" something that looks unfinished; several things are
  deferred on purpose (see below).

## Architecture

Three features, all shipped through the same shape. Nothing here is a stub any
more, so match the existing pattern rather than inventing one.

**One composition root.** `DemoMemos/DemoMemosApp.swift` holds `@main`, the
`Services` struct (the only place real services are constructed) and `RootView`
(the only place routing lives). `Services.live()` also runs
`store.removeOrphanedFiles()` at startup. Everything downstream takes its
dependencies as initialiser arguments; nothing reaches for a singleton.

**Record and playback are one screen.** `CaptureView` + `CaptureState` with a
four-case `Status` — `ready → recording → stopped`, plus `playback` for a memo
reopened from the list. Playback is the *same* state object entered through a
different initialiser, and that initialiser never captures. `RootView` presents
the record flow as a `fullScreenCover` (its own `NavigationStack`, so
Cancel/Done get a real nav bar) and playback as a push (so it inherits the
native "Demos" back button). All state transitions are plain methods on
`CaptureState`, testable with no simulator audio and no files.

**`MemoStore` owns the index and the audio as one thing.** The SwiftData `Memo`
row carries a `filename` basename; the `.m4a` lives in
`Documents/Recordings/`. Nothing outside the store touches that directory, so a
row can't outlive its file or a file its row. Commit/delete/discard/rename all
go through the protocol.

**Three seams, each with exactly one real implementation and one fake:**
`MemoStore`, `AudioRecorder`, `AudioPlayer`. They exist because every unit test
and every `#Preview` runs on the fake — not for anticipated flexibility. Fakes
and named sample data live in `Audio/Fakes.swift` (`PreviewScenario`) and
`Capture/CapturePreview.swift`. Don't add a protocol without both halves.

**`Audio/`, `Memo`, `MemoStore` and `OnboardingStore` import no SwiftUI.** Keep
that boundary; it's what makes the state machine testable.

### Deferred on purpose (don't be surprised)

- **Enhance does no DSP.** It is persisted per memo and drives the waveform
  bloom and the tone word only. Storing it now means the DSP follow-up is a
  playback-time change with no migration.
- **A reopened memo's waveform is synthesised**, seeded from the memo's id — no
  level data is persisted. It scrubs correctly but is not that take's shape.
- **Resume works only until the take is previewed.** Previewing has to close the
  part-written `.m4a`, and appending to a closed file needs
  `AVMutableComposition`. `CaptureState.canResume` encodes exactly that window.

## Commands

- Verify (build + unit tests, all stacks): `.claude/verify.sh`
  Picks a booted iPhone simulator if there is one, else the first available.
  Runs `-only-testing:DemoMemosTests` — UI tests are CI's job. Exits non-zero if
  *nothing* was verifiable, so a green tick always means something ran.
- Single test: `xcodebuild test -project apps/ios/DemoMemos.xcodeproj -scheme DemoMemos -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DemoMemosTests/CaptureStateTests/testName`
  (suites: `CaptureStateTests`, `MemoStoreTests`, `OnboardingStoreTests`.)
- Format one file: `.claude/format.sh <path>` (runs automatically after every write).
  Formatting rules live in that script, not here. It no-ops when the formatter
  (`swift-format`, local `prettier`, `shfmt`) is absent — it never installs anything.

## Signing & on-device builds

`apps/ios/Signing.xcconfig` is committed, is the target's
`baseConfigurationReference`, and holds no identity; it optionally `#include?`s
`Local.xcconfig`, which is gitignored. For device builds create
`apps/ios/Local.xcconfig` with `DEVELOPMENT_TEAM = YOURTEAMID`. Simulator builds
need no signing, so fresh clones and CI work with the file absent.

Never let a `DEVELOPMENT_TEAM` land in `project.pbxproj` — Xcode's Signing &
Capabilities UI re-stamps it, so check it before committing. Put credentials in
neither file; see `docs/SECURITY.md`.

## Repo setup (once per clone)

```
brew install gitleaks
git config core.hooksPath .githooks
```

The pre-commit hook fails closed: no gitleaks, no commit. This repo is public.
(`docs/SECURITY.md` says `make setup` — there is no Makefile in this repo, so
use the two commands above.)

## Conventions

Placement rules live in `docs/PRINCIPLES.md` — read it before creating or moving
files. It is plugin-managed and overwritten wholesale on update, so never
hand-edit it; project-specific adaptations go here or in `apps/ios/CLAUDE.md`.

Seam and definition-of-done rules live in the `sdlc:build-rules` skill.

Merges are squash-only — the PR title and body become the commit, so they follow
Conventional Commits like everything else.
