# SDLC on GitHub Projects

Companion to `SDLC.md`. The board is a **record**, not a gate.

---

## Three rules

1. **You never move a card.** Automation moves them. If you find yourself
   dragging things, the wiring is wrong.
2. **The agent never queries the board mid-build.** Board state doesn't belong
   in a coding context. One issue read at the start, one PR at the end.
3. **Triage happens in batches, not per item.** You approve a table of
   decisions once, rather than making a decision per idea.

---

## Board setup

**Status** (single select — these are your columns):

`Backlog` → `In Refinement` → `Ready For Development` → `In Development` → `In Review` → `Done`

**Lane** (single select): `Just Ship` · `Think A Little` · `Think Hard`

`Just Ship` items skip `In Refinement` entirely. That's the only structural
difference between lanes — everything else is the same pipeline.

### Automations to enable

Projects has built-in workflows that set Status on events, and two are on by
default: closed issues and merged PRs both go to Done. Turn on the rest:

| Transition | Trigger | Who |
|---|---|---|
| → `Backlog` | Auto-add: new issues in the repo | built-in |
| `Backlog` → `Ready For Development` / `In Refinement` | Triage batch sets Lane + Status | agent |
| `In Refinement` → `Ready For Development` | Design bundle or `SPEC.md` linked on the issue | **you** |
| `Ready For Development` → `In Development` | Draft PR opened with `Closes #n` | built-in |
| `In Development` → `In Review` | PR marked ready for review | built-in |
| `In Review` → `Done` | PR merged | built-in (default) |

**Your total manual involvement: one transition, on `Think A Little` and `Think Hard` items
only.** `Just Ship` work never touches you between triage and merge.

---

## Speed concessions

These exist so the board never becomes the bottleneck.

- **`Just Ship` items can be opened and closed in the same session.** No
  approval step. The card appears and lands within the hour.
- **Trivial `Just Ship` work skips the issue entirely** — open a PR, let it
  auto-add. The PR is the record.
- **Nothing waits for a ceremony.** There is no standup, no grooming, no
  sprint.

---

## Batched triage

Run this on the `Backlog` column when it has a handful of items. Own session,
`/clear` afterwards.

```
List open issues in Backlog with: gh issue list --label backlog --json number,title,body

For each, apply the triage rubric from SDLC.md:
  1. Expensive or impossible to undo?  → Think Hard
  2. Crosses a seam?                   → Think A Little
  3. Otherwise                         → Just Ship

Output one table: number, title, lane, one-line reason.
Do not set anything yet. Do not elaborate.
```

You scan the table, correct any lane you disagree with, then:

```
Apply those lanes. For each issue:
- set the Lane field
- Just Ship → Status "Ready For Development". Think A Little / Think Hard → Status "In Refinement".
- append acceptance criteria to the body: 3 bullets max, observable outcomes only
```

One review, N items. That's the input reduction.

---

## Token rules

The board is where token burn creeps in. Guard it.

- **No GitHub MCP server inside build sessions.** It returns large JSON for
  simple questions. Use `gh` with explicit fields.
- `gh issue view 42 --json title,body` — tens of tokens. Never `gh issue
  list` with no filter inside a build session.
- **Never say "check the board."** It pulls everything. Name the issue.
- Everything the build session needs lives in the issue body. If the agent
  has to go looking, triage under-specified it.
- Board operations and code operations are different sessions.

---

## The build session

Start it with the issue number and nothing else:

```
Implement #42. Read it with: gh issue view 42 --json title,body
Boundaries and definition of done: see SDLC.md.
Open a draft PR with "Closes #42" before you start.
```

The draft PR moves the card to `In Development` for free. Marking it ready moves it
to `In Review`. Merging closes the issue and moves it to `Done`. You touched
nothing.

---

## If it starts feeling slow

Check these in order — it's almost always the first one.

1. Items sitting in `In Refinement` → you're refining things that should be `Just Ship`.
2. You're moving cards by hand → an automation isn't enabled.
3. Sessions are expensive → the agent is querying the board mid-build.
4. Triage is taking real time → you're triaging one at a time instead of batching.
