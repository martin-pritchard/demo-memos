# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Demo Memos

## Layout

- `apps/ios` — SwiftUI app. Xcode project `DemoMemos.xcodeproj`, scheme `DemoMemos`.
  Targets: `DemoMemos`, `DemoMemosTests` (unit, Swift Testing), `DemoMemosUITests` (XCTest).
  iOS 26.5 deployment target, Swift 5 language mode.
- `apps/web` — placeholder, no stack chosen yet.
- `design` — design source and export helpers, not shipped code.
- `docs/security.md` — secret-handling rules. Read before adding any credential,
  key, or `.env`; the "keys in an app binary are extractable" section is a real
  architectural constraint, not boilerplate.

The app is currently a stub (`DemoMemosApp.swift` renders `Text("Hello World")`).
There are no features yet, so the first feature sets the shape every later one
copies.

`apps/ios/CLAUDE.md` and `apps/web/CLAUDE.md` exist but are empty. Stack-specific
*mechanisms* (module system, UI-state pattern, file-naming specifics) belong
there as they're decided, not in this file.

## Commands

- Verify (build + unit tests, all stacks): `.claude/verify.sh`
  Picks a booted iPhone simulator if there is one, else the first available.
  Runs `-only-testing:DemoMemosTests` — UI tests are CI's job. Exits non-zero if
  *nothing* was verifiable, so a green tick always means something ran.
- Single test: `xcodebuild test -project apps/ios/DemoMemos.xcodeproj -scheme DemoMemos -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:DemoMemosTests/SuiteName/testName`
- Format one file: `.claude/format.sh <path>` (runs automatically after every write).
  Formatting rules live in that script, not here. It no-ops when the formatter
  (`swift-format`, local `prettier`, `shfmt`) is absent — it never installs anything.

## Signing & on-device builds

`apps/ios/Signing.xcconfig` is committed and holds no identity; it optionally
`#include?`s `Local.xcconfig`, which is gitignored. For device builds create
`apps/ios/Local.xcconfig` with `DEVELOPMENT_TEAM = YOURTEAMID`. Simulator builds
need no signing, so fresh clones and CI work with the file absent.

Never let a `DEVELOPMENT_TEAM` land in `project.pbxproj` — Xcode's Signing &
Capabilities UI re-stamps it, and the pre-commit hook blocks the commit.
Put credentials in neither file; see `docs/security.md`.

## Repo setup (once per clone)

```
brew install gitleaks
git config core.hooksPath .githooks
```

The pre-commit hook fails closed: no gitleaks, no commit. This repo is public.

## Conventions

Placement rules live in `docs/PRINCIPLES.md` — read it before creating or moving
files. Seam and definition-of-done rules live in the `sdlc:build-rules` skill.
