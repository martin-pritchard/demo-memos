# New App: Day Zero

Everything here happens before the first feature. Should take under an hour.

The goal is not to build anything. It's to make the loop work, so that every
feature afterwards flows through it without you thinking about it.

---

## Step 1 — The bootstrap prompt

Paste into Claude Code in an empty repo.

```
We're starting a new app. Don't write anything yet — interview me first.

Ask one question at a time. Give your recommended answer to each, so I can
just say "yes". Don't ask anything you could answer by looking. Don't ask
about anything that's cheap to change later.

Cover only these:
  1. What the app is, in one sentence
  2. Which platforms
  3. The core domain nouns — the 5-10 words this app is about
  4. Token names for colour, spacing and type scale
  5. Test framework and preview/harness mechanism, per platform
  6. Anything irreversible you think I've missed

Then summarise and wait for my approval before building.
```

Answering "yes, defaults" to everything is a legitimate route through this.
The interview exists to catch the one decision you'd have regretted, not to
extract a specification.

## Step 2 — The scaffold prompt

After you approve the summary:

```
Now scaffold. Build only what's listed. No features.

Use the idiomatic project structure for each platform. Don't invent
conventions — if there's a standard layout, use it exactly.

1. TOKENS — one source of truth per platform. Same names and same values
   across all platforms. Nothing anywhere else hardcodes a colour, a spacing
   value or a type size.

2. SEAM — a location for data contracts, and a location for named fixture
   scenarios. Include one worked example: a contract with empty, loading,
   error and populated fixtures.

3. VERIFICATION — build, static checks and tests each runnable with one
   command. A preview or harness that can display any UI state without real
   data. Document the commands in CLAUDE.md.

4. HOOKS — formatter and linter run automatically on write. Nothing about
   formatting or naming goes into CLAUDE.md; the tools enforce it.

5. CLAUDE.md — under 40 lines. Only: the one-line description, the domain
   vocabulary, the commands, and anything genuinely non-obvious. Nothing
   you'd get right without being told.

6. DECISIONS.md — empty, with a one-line header saying what belongs in it.

No persistence. No networking. No state library. No dependency that isn't
required by the above.

When done: run every check and show me the output. Then list in DECISIONS.md
everything you deliberately deferred.
```

---

## Step 3 — By hand (15 minutes)

Claude can't do these. They're one-offs.

**GitHub Project**
- Status field: `Backlog` `In Refinement` `Ready For Development` `In Development` `In Review` `Done`
- Lane field: `Just Ship` `Think A Little` `Think Hard`
- Enable auto-add for new issues in the repo
- Confirm the two default workflows are on (issue closed → Done, PR merged → Done)

**Claude Design**
- Create a project, run `/design-sync` against the repo so it picks up the
  tokens you just made
- Don't design anything yet

**Repo**
- Add `SDLC.md` and `SDLC-github.md`
- Create `design/` for committed handoff bundles

---

## Step 4 — Walking skeleton

**Do not build a real feature yet.** Take one worthless change all the way
through the pipeline first:

> Open an issue for something trivial and visible — change a heading, add a
> placeholder screen. Triage it as Just Ship. Build it. Open a PR with `Closes #1`.
> Merge it.

Watch the card move on its own: `Ready For Development` → `In Development` → `In Review` → `Done`.

If it doesn't move, an automation is wrong, and you've found that out in
twenty minutes on something you don't care about. If it does move, the loop
works and every feature from here is just repetition.

---

## Definition of ready to start

- [ ] One command each for build, checks and tests — all passing
- [ ] Any UI state viewable without real data
- [ ] Formatter and linter enforced by hooks, not by documentation
- [ ] Tokens shared across platforms, nothing hardcoded
- [ ] CLAUDE.md under 40 lines
- [ ] A card moved from `Ready For Development` to `Done` without you dragging it

---

## What you deliberately don't have yet

Persistence. Networking. Auth. State management. Any of the third-party
services you know you'll need.

They're all in `DECISIONS.md`, and each becomes an idea at Intake when a
feature actually requires it. Deciding them now means deciding them with
less information than you'll ever have again.
