#!/usr/bin/env bash
# Format and lint a single file. Invoked by the Claude Code PostToolUse hook
# (see .claude/settings.json), which pipes its JSON payload in on stdin.
#
# This exists so formatting is never something anyone — human or agent — has to
# remember. There is deliberately no style guidance in any CLAUDE.md: the tools
# below are the only definition of house style, and they run on every write.
#
# Exit codes are the hook contract, not a shell convention:
#   0  file formatted (or not ours to touch) — stay quiet
#   2  lint failed — stderr is fed back to the agent to fix
set -euo pipefail

cd "$(dirname "$0")/.."

# The payload is a full tool-use record; file_path is absent for tools that
# don't touch files, so an empty result is a normal no-op, not an error.
file="$(jq -r '.tool_input.file_path // empty')"
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0

case "$file" in
  *.swift)
    xcrun swift-format format --in-place "$file"
    # --strict promotes warnings to errors: a lint rule nobody enforces is a
    # lint rule that decays. Formatting above fixes what is auto-fixable, so
    # anything surfacing here is a genuine judgement call for the author.
    if ! out="$(xcrun swift-format lint --strict "$file" 2>&1)"; then
      printf 'swift-format lint failed:\n%s\n' "$out" >&2
      exit 2
    fi
    ;;

  */apps/web/*.astro | */apps/web/*.ts | */apps/web/*.js | */apps/web/*.mjs \
  | */apps/web/*.json | */apps/web/*.css | */apps/web/*.md)
    # Skip silently rather than fail: a fresh clone has no node_modules, and a
    # hook that errors on every write until you run `npm ci` gets disabled.
    [ -d apps/web/node_modules ] || exit 0
    # Must run *from* apps/web: prettier resolves plugins relative to its cwd,
    # so --prefix alone finds the binary but not prettier-plugin-astro.
    if ! out="$(cd apps/web && ./node_modules/.bin/prettier --write "$file" 2>&1)"; then
      printf 'prettier failed:\n%s\n' "$out" >&2
      exit 2
    fi
    ;;
esac
