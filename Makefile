# demo-memos — task runner.
#
# make is the entry point because this is a polyglot repo: the iOS app and the
# site build with entirely different toolchains and share no code. make is the
# one language-agnostic runner already present on every dev machine, so it gives
# us `make test` without a root package.json pretending the app is a JS package.
#
# Targets delegate to each app's own toolchain — they don't reimplement it.

.DEFAULT_GOAL := help

IOS_PROJECT := apps/ios/DemoMemos.xcodeproj
IOS_SCHEME  := DemoMemos
# Simulator model is a local choice, not a project one — override per machine:
#   make test-ios IOS_DESTINATION='platform=iOS Simulator,name=iPhone 16'
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17

SWIFT_SRC := apps/ios/DemoMemos apps/ios/DemoMemosTests apps/ios/DemoMemosUITests

.PHONY: help setup scan fmt fmt-ios fmt-web lint lint-ios lint-web test test-ios test-web

help: ## Show available targets
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Set up this clone (secret-scanning hook). Safe to re-run.
	@./scripts/setup.sh

scan: ## Scan the full history for secrets
	@gitleaks git --redact --no-banner .

# fmt/lint exist for CI and for a whole-repo sweep. Day to day you should never
# need them: scripts/format-file.sh runs the same tools on every file write.
fmt: fmt-ios fmt-web ## Format everything

fmt-ios:
	@xcrun swift-format format --in-place --recursive $(SWIFT_SRC)

fmt-web:
	@npm --prefix apps/web run format

lint: lint-ios lint-web ## Lint everything (no writes)

lint-ios:
	@xcrun swift-format lint --strict --recursive $(SWIFT_SRC)

lint-web:
	@npm --prefix apps/web run lint

test: test-ios test-web ## Run all tests

test-ios: ## Run iOS tests
	@xcodebuild test \
		-project $(IOS_PROJECT) \
		-scheme $(IOS_SCHEME) \
		-destination '$(IOS_DESTINATION)' \
		-quiet

# The site has no test runner and no unit tests — adding one would be a
# dependency nothing currently needs. A failed build is the only failure a
# static content site can currently have, so that is what we assert.
test-web: ## Run web tests (build must succeed)
	@npm --prefix apps/web run build