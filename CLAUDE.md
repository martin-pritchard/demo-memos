# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

# Demo Memos

Voice Memos for song ideas: one-tap capture, a single **Enhance** dial, and a
list of takes. SwiftUI, iPhone only. See `README.md` for the product framing.

**The app is currently a bare Xcode template.** `feat(ios)!: rebuild the Xcode
project from scratch` (#14) reset it to `DemoMemosApp.swift` + `ContentView.swift`
and added an empty `Core` package. The features described in the README are the
target, not the current state — there is no capture flow, no store, no audio code
in the tree. Build them; don't assume they exist.

## Layout

- `apps/ios` — the app.
  - `DemoMemos.xcodeproj`, scheme `DemoMemos`. Targets: `DemoMemos`,
    `DemoMemosTests` (Swift Testing), `DemoMemosUITests` (XCTest).
    iOS 26.5 deployment target, Swift 5 language mode.
  - `Core/` — local SPM package, scheme `Core`, Swift 6 language mode. This is
    the UI-free core (`docs/PRINCIPLES.md` #3): domain models, persistence,
    audio engine code. **It must not import SwiftUI or UIKit** — that boundary
    is what keeps it testable with `swift test`, no simulator.
  - `Config/` — `Shared.xcconfig` is the target's `baseConfigurationReference`
    and holds no identity; it `#include?`s the gitignored `Local.xcconfig`.
- `apps/web` — placeholder. No stack chosen, no manifest, `apps/web/CLAUDE.md`
  still empty. `.claude/verify.sh` skips it loudly rather than pretending.
- `docs/PRINCIPLES.md` — placement rules. Read it before creating or moving
  files. Plugin-managed and overwritten wholesale on update, so never hand-edit
  it; project-specific adaptations go here.
- `docs/SECURITY.md` — secret-handling rules. Read before adding any credential,
  key, or `.env`; the "a key in an iOS binary is not secret" section is a real
  architectural constraint, not boilerplate.

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
files.

Seam and definition-of-done rules live in the `sdlc:build-rules` skill.

Merges are squash-only — the PR title and body become the commit, so they follow
Conventional Commits like everything else.
