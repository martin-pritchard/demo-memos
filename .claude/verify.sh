#!/usr/bin/env bash
# Build + static checks + unit tests. Fast — the full suite (UI tests) belongs in CI.
# Run by the SDLC plugin's Stop hook. Non-zero exit = the work is not done.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

status=0
checked=0

fail() {
  echo "FAIL: $1" >&2
  status=1
}

# ---------------------------------------------------------------- iOS
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
    # -only-testing keeps this to unit tests. UI tests are CI's job.
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
    npm run --silent lint  || exit 1
    npm run --silent test  || exit 1
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
  echo "verify: PASS ($checked stack(s) checked)"
else
  echo "verify: FAIL"
fi
exit "$status"
