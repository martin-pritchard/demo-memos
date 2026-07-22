---
name: audit
description: Audit this repository's agent setup and conventions for anything not earning its cost. Run when the user asks to audit, review or optimise their Claude Code setup, CLAUDE.md, or project conventions.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git:*)
---

# Agent setup audit

Read-only. Change nothing. Prefer running this in a subagent.

Read the codebase, CLAUDE.md and its imports, linter and formatter configs,
hooks, skills, and CI config. Judge everything against one question: is this
earning its cost?

## 1. Instructions that do not earn their place

For every rule in CLAUDE.md and its imports, decide which applies:

- **Restates a default** - would be done correctly without being told. Delete.
- **Enforceable deterministically** - a formatter, linter or hook could
  guarantee it. Move it there; instructions get skipped under load, hooks do
  not.
- **Earns its place** - non-obvious, project-specific, absence causes mistakes.

Flag anything long enough to dilute the rules around it.

## 2. Idiomatic versus invented

List every convention deviating from the platform's canonical style. For each,
state what the deviation buys and whether it is worth the permanent cost of
restating it. Default position: being unremarkable for the platform is correct.

## 3. The presentation boundary

Find every place a view acquires its own data - fetches, reads storage, or
reaches into a global container directly. List them.

## 4. Verification

- Is there a check an agent can run that returns pass/fail unaided?
- Can every UI state be reached in a preview or harness without real data?
  List the ones that cannot.
- Does anything gate on it, or is it advisory?

## 5. Process weight

Identify spec, ticket or planning scaffolding applied to every change
regardless of risk.

## 6. Vocabulary

List the domain terms this repo uses for its core concepts. Names only.

## Output

A single ranked table, nothing else:

| Finding | Cost today | Cheapest fix | Effort |

Rank by cost, highest first. For the fix, always consider whether deleting the
instruction beats changing the code.

Report only what is actually costing something. Say "no change needed" for
sections with nothing worth reporting. No style preferences, no suggested
abstractions, no speculative future-proofing. Prefer deletion to addition. If
unsure whether something is a problem, leave it out.
