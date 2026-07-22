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

.PHONY: help setup scan test test-ios test-web

help: ## Show available targets
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Set up this clone (secret-scanning hook). Safe to re-run.
	@./scripts/setup.sh

scan: ## Scan the full history for secrets
	@gitleaks git --redact --no-banner .

test: test-ios test-web ## Run all tests

test-ios: ## Run iOS tests
	@xcodebuild test \
		-project $(IOS_PROJECT) \
		-scheme $(IOS_SCHEME) \
		-destination '$(IOS_DESTINATION)' \
		-quiet

test-web: ## Run web tests
	@echo "No web stack chosen yet — see apps/web/CLAUDE.md."