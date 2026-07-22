---
name: build-rules
description: >
  Boundaries, seam and definition of done for all implementation work in this
  project. Use this skill whenever writing or changing application code,
  building UI from a design or handoff bundle, adding a screen or component,
  wiring up state, fixing a bug, or opening a pull request - even when the user
  says nothing about rules, standards, boundaries or process, and even for
  changes that look small or obvious. If code is being written or changed in
  this repository, this skill applies.
metadata:
  version: "0.1.0"
---

# Build rules

Apply these to all implementation work in this project.

## Boundaries

These exist so that decisions which are expensive to reverse get made
deliberately, with a ticket, rather than in passing during unrelated work. A
persistence choice made silently inside a UI task is the single most costly
thing that can happen here.

Unless the issue being implemented explicitly asks for one, do not add:

- Networking or remote data access
- Persistence of any kind: disk, database, key-value store, cache
- Dependency injection wiring for real data sources
- Any new global or shared state container
- Any dependency not already in this project

## The seam

Declare the data each screen needs as explicit types, using whatever mechanism
this codebase already uses for data models.

Back those types with sample data covering every state in the design, as named
scenarios: empty, loading, error, populated, plus any others shown.

Views take state in and emit events out. No view acquires its own data. This
is what keeps the deferred decisions genuinely deferrable - once a component
fetches its own data, extracting that later is real work rather than a
contained change.

## Conventions

Follow this codebase's existing conventions for file layout, naming, component
structure and styling. Where an existing component fits, use it. Where
something new is needed, build it in the style of its nearest existing
neighbour and say which one was followed. Where there is no precedent, say so
rather than inventing silently.

Never add abstraction for flexibility that was not asked for. Build the two
tables in the design, not a generic table component.

## Deferred decisions

When a decision falls outside these boundaries, stop and append it to
`DECISIONS.md` rather than choosing. Do not make architectural choices in
passing.

## Definition of done

All of these must hold before reporting completion:

- Build and static checks pass
- Every state in the design reachable in a preview or harness without real data
- No view acquires its own data
- No dependency added that was not agreed
- Domain terms match the vocabulary in CLAUDE.md
- Nothing added "for flexibility later"
- Deferred decisions recorded in `DECISIONS.md`
