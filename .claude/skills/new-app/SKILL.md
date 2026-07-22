---
name: new-app
description: Bootstrap a new application repository - interview, scaffold, verify. Run when the user is starting a new app or project from scratch.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# New app bootstrap

Build nothing but scaffolding. The goal is a working loop, not a feature.

Full checklist including the manual steps: `references/day-zero.md`.

## Step 1 - interview

Ask one question at a time. Give a recommended answer to each so the user can
reply "yes". Do not ask anything answerable by looking. Do not ask about
anything cheap to change later.

Cover only:

1. What the app is, in one sentence
2. Which platforms
3. The core domain nouns - the five to ten words this app is about
4. Token names for colour, spacing and type scale
5. Test framework and preview or harness mechanism, per platform
6. Anything irreversible not yet mentioned

Summarise and wait for approval before building.

## Step 2 - scaffold

Use the idiomatic project structure for each platform. Do not invent
conventions; if a standard layout exists, use it exactly.

1. **Tokens** - one source of truth per platform, same names and values across
   all platforms. Nothing else hardcodes a colour, spacing value or type size.
2. **Seam** - a location for data contracts and a location for named fixture
   scenarios, plus one worked example with empty, loading, error and populated
   fixtures.
3. **Verification** - build, static checks and tests each runnable with one
   command. A preview or harness that displays any UI state without real data.
   Document the commands in CLAUDE.md.
4. **Hooks** - formatter and linter run automatically on write. Put nothing
   about formatting or naming in CLAUDE.md; the tools enforce it.
5. **CLAUDE.md** - under 40 lines. Only the one-line description, the domain
   vocabulary, the commands, and anything genuinely non-obvious.
6. **DECISIONS.md** - empty, with a one-line header saying what belongs in it.

Add no persistence, no networking, no state library, and no dependency not
required by the above.

## Step 3 - verify

Run every check and show the output. Then list in `DECISIONS.md` everything
deliberately deferred.

Then tell the user which manual steps remain, from `references/day-zero.md`:
the GitHub Project fields and automations, the Claude Design project, and the
walking-skeleton first ticket.
