#!/usr/bin/env bash
# Build + static checks + unit tests. Fast, and it is the whole suite — there is
# no CI and no UI test target.
# Run by the SDLC plugin's Stop hook. Non-zero exit = the work is not done.
#
# A thin shim: it calls the project's canonical commands (swift-format, swift
# test, xcodebuild) and never restates their configuration.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0
checked=0

fail() {
  echo "FAIL: $1" >&2
  status=1
}

# ------------------------------------------------- static: Swift formatting
# The same swift-format that .claude/format.sh applies on every write, in lint
# mode. Fix with:  git ls-files '*.swift' | xargs -n1 .claude/format.sh
if git rev-parse --git-dir >/dev/null 2>&1 && xcrun --find swift-format >/dev/null 2>&1; then
  swift_files="$(git ls-files '*.swift')"
  if [ -n "$swift_files" ]; then
    checked=$((checked + 1))
    echo "==> swift-format: lint"
    # shellcheck disable=SC2086
    if ! xcrun swift-format lint --strict $swift_files; then
      fail "swift-format lint"
    fi
  fi
fi

# ------------------------------------------------------------ Core package
# Runs on macOS — fast, no simulator. Core is UI-free by design (docs/PRINCIPLES.md #3),
# so this is the right host. Its iOS compilation is covered by the app build below.
if [ -f "apps/ios/Core/Package.swift" ]; then
  checked=$((checked + 1))
  echo "==> Core: build + unit tests (swift test)"
  if ! swift test --package-path apps/ios/Core; then
    fail "Core build or unit tests"
  fi
fi

# ---------------------------------------------------------------- iOS app
if [ -d "apps/ios/DemoMemos.xcodeproj" ]; then
  checked=$((checked + 1))
  echo "==> iOS: build + unit tests (DemoMemosTests)"

  # Prefer a booted simulator; otherwise take the first available iPhone.
  SIM="$(xcrun simctl list devices available \
    | grep -E "iPhone .*\(Booted\)" \
    | head -1 \
    | sed -E 's/^ *(.*) \([0-9A-F-]{36}\).*/\1/')"
  if [ -z "$SIM" ]; then
    SIM="$(xcrun simctl list devices available \
      | grep -E "^ *iPhone " \
      | head -1 \
      | sed -E 's/^ *(.*) \([0-9A-F-]{36}\).*/\1/')"
  fi
  if [ -z "$SIM" ]; then
    fail "no iOS Simulator available to test against"
  else
    echo "    simulator: $SIM"
    if ! xcodebuild test \
      -project apps/ios/DemoMemos.xcodeproj \
      -scheme DemoMemos \
      -destination "platform=iOS Simulator,name=$SIM" \
      -only-testing:DemoMemosTests \
      -quiet; then
      fail "iOS build or unit tests"
    fi
  fi
fi

# ---------------------------------------------------------------- web
if [ -f "apps/web/package.json" ]; then
  checked=$((checked + 1))
  echo "==> web: lint + unit tests"
  (
    cd apps/web || exit 1
    npm run --silent lint || exit 1
    npm run --silent test || exit 1
  ) || fail "web lint or unit tests"
elif [ -d "apps/web" ]; then
  echo "==> web: SKIPPED — apps/web has no package.json yet."
  echo "    Nothing here is verified. Add the manifest, then extend this script."
fi

# ---------------------------------------------------------------- verdict
echo
if [ "$checked" -eq 0 ]; then
  echo "!! NOTHING WAS VERIFIED — no buildable stack found."
  echo "!! A green tick here means nothing. Fix this script before trusting it."
  exit 1
fi

if [ "$status" -eq 0 ]; then
  echo "verify: PASS ($checked check(s) run)"
else
  echo "verify: FAIL"
fi
exit "$status"
