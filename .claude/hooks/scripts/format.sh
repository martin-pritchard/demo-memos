#!/usr/bin/env bash
# Deterministic formatting. Runs after every write or edit.
#
# Fill in the formatter for whichever stacks this repo uses and delete the
# rest. Nothing about formatting or naming should ever appear in CLAUDE.md -
# this script is the enforcement mechanism.
set -euo pipefail

# Web
# npx prettier --write . >/dev/null 2>&1 || true
# npx eslint --fix . >/dev/null 2>&1 || true

# iOS
# swiftformat . >/dev/null 2>&1 || true

# Android
# ./gradlew ktlintFormat >/dev/null 2>&1 || true

exit 0
