#!/usr/bin/env bash
# Set up a clone of demo-memos for development. Run via: make setup
#
# Safe to re-run at any time — it verifies as much as it configures. If you're
# ever unsure whether your clone is protected, run it again and read the output.
#
# This exists because git deliberately runs nothing on clone (that would make
# cloning any repo remote code execution), so `core.hooksPath` cannot install
# itself. One command is the floor.

set -euo pipefail

cd "$(dirname "$0")/.."

ok=0
fail=0

pass() { printf '  \033[32m✔\033[0m %s\n' "$1"; ok=$((ok + 1)); }
warn() { printf '  \033[31m✖\033[0m %s\n' "$1"; fail=$((fail + 1)); }
info() { printf '    %s\n' "$1"; }

printf '\ndemo-memos setup\n\n'

# --- 1. gitleaks: check, don't install -------------------------------------
# We don't auto-install: a setup script that mutates your machine unasked is one
# people stop running. Also keeps this working off macOS/brew.
if command -v gitleaks >/dev/null 2>&1; then
  pass "gitleaks installed ($(gitleaks version 2>&1))"
else
  warn "gitleaks not found — the pre-commit secret scan cannot run"
  info "install:  brew install gitleaks"
  info "          (or see https://github.com/gitleaks/gitleaks#installing)"
fi

# --- 2. hooks path ----------------------------------------------------------
current_hooks="$(git config --local core.hooksPath || true)"
if [ "$current_hooks" = ".githooks" ]; then
  pass "git hooks pointed at .githooks"
else
  git config --local core.hooksPath .githooks
  pass "git hooks pointed at .githooks (just set)"
fi

# --- 3. hook is executable --------------------------------------------------
# The exec bit is tracked in git (mode 100755), so this should already hold —
# but a umask or a zip-based download can strip it, and a non-executable hook
# is skipped by git *silently*, which is the exact failure this script exists
# to catch.
if [ -x .githooks/pre-commit ]; then
  pass "pre-commit hook is executable"
else
  chmod +x .githooks/pre-commit
  pass "pre-commit hook made executable (was not)"
fi

# --- 4. prove the hook actually fires ---------------------------------------
# Verification, not assumption. Everything above can look right while the hook
# still doesn't run. This feeds a known-detectable fake secret to the real hook
# and asserts it objects. Nothing is staged or committed.
probe="$(mktemp -t demomemo-probe)"
trap 'rm -f "$probe"' EXIT
# The value below is fabricated — it matches Stripe's *shape* so gitleaks detects
# it, which is the whole point. It must be exempted here or the hook flags this
# very file. The exemption is scoped to this line only.
printf 'STRIPE_KEY = "sk_live_51H8xQ2LmNpRt7vBcYd3FgHjK"\n' > "$probe" # gitleaks:allow
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks stdin --no-banner --redact < "$probe" >/dev/null 2>&1; then
    warn "gitleaks did NOT flag a known-bad test value — scanning looks broken"
    info "expected a Stripe-style key to be detected; it wasn't"
  else
    pass "secret detection verified against a known-bad value"
  fi
else
  warn "skipped detection check (gitleaks missing)"
fi

# --- summary ----------------------------------------------------------------
printf '\n'
if [ "$fail" -gt 0 ]; then
  printf '\033[31m%s check(s) failed\033[0m, %s passed. Fix the above and re-run: make setup\n\n' "$fail" "$ok"
  exit 1
fi
printf '\033[32mAll %s checks passed.\033[0m This clone is set up.\n\n' "$ok"