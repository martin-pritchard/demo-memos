#!/usr/bin/env bash
# Format one file. Called by the SDLC plugin's PostToolUse hook with the
# changed file's path as $1. Formatting rules live here, not in CLAUDE.md.
set -uo pipefail

file="${1:-}"
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

case "$file" in
  *.swift)
    # Ships with Xcode — no extra install needed.
    if xcrun --find swift-format >/dev/null 2>&1; then
      xcrun swift-format --in-place "$file" 2>/dev/null || true
    fi
    ;;
  *.js|*.jsx|*.ts|*.tsx|*.json|*.css|*.html|*.md)
    # Only if the repo already provides prettier — never reach for the network.
    if [ -x "node_modules/.bin/prettier" ]; then
      ./node_modules/.bin/prettier --write "$file" >/dev/null 2>&1 || true
    elif [ -x "apps/web/node_modules/.bin/prettier" ]; then
      ./apps/web/node_modules/.bin/prettier --write "$file" >/dev/null 2>&1 || true
    fi
    ;;
  *.sh)
    if command -v shfmt >/dev/null 2>&1; then
      shfmt -w -i 2 "$file" >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
