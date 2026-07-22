# SDLC

One page. If it grows past one page, it's wrong.

**Guiding lights:** quality, speed, simplicity, repeatability.

---

## The one rule

**Triage before you flesh out.**

The most common waste is writing a spec for something that needed a
15-minute change. An idea enters as a one-line description. It gets triaged.
*Then* it gets shaped — if its lane calls for it.

---

## Intake

An idea is captured as a single sentence: who it's for, what changes for them.
Nothing more. No spec, no design, no estimate.

Then triage. Takes 30 seconds.

## Triage

Ask in order. Stop at the first yes.

| | Question | Lane |
|---|---|---|
| 1 | If we get this wrong, is it expensive or impossible to undo? (user data, money, auth, public contracts, anything migrations touch) | **Think Hard** |
| 2 | Does it cross a seam? (new persistence, new external dependency, new shared state, or changes an existing contract) | **Think A Little** |
| 3 | Otherwise | **Just Ship** |

**Unsure? Use blast radius, not effort.** If the worst outcome is a screen
looks wrong, it's Just Ship. If the worst outcome is data is wrong, it's Think Hard.

**Importance is not size.** A one-line change to a pricing calculation is
Think Hard. A 2,000-line UI build against existing components is Just Ship. Size tells
you how long it takes; reversibility tells you how much thinking it deserves.

---

## The five stations

Every lane runs the same stations. The lane decides which you skip.

| Station | Just Ship | Think A Little | Think Hard |
|---|:-:|:-:|:-:|
| **1. Shape** — turn the idea into something implementable | – | ● | ● |
| **2. Agree** — align before planning | – | – | ● |
| **3. Decompose** — split into independent units | – | – | ● |
| **4. Build** — fresh session per unit | ● | ● | ● |
| **5. Verify & Land** — closable check, capped review, merge | ● | ● | ● |

### 1. Shape

- **User-facing** → Claude Design. Link the repo first. Name components as
  you want them in code. Ask for empty, loading, error and populated states
  before exporting. Output: handoff bundle.
- **Not user-facing** → Claude Code. Output: `SPEC.md`, under a page.

### 2. Agree (Think Hard only)

Before plan mode, make Claude interview you — one question at a time, with
its recommended answer for each, digging into what you haven't considered.
Continue until you both hold the same model. The output is shared
understanding; `SPEC.md` is just its residue.

Plan mode without this produces a confident plan for the wrong problem.

### 3. Decompose (Think Hard only)

Split into units that can each be built, verified and landed alone. If a unit
can't be verified independently, it isn't a unit.

### 4. Build

Fresh session per unit. Boundaries stated as negatives (no persistence, no
network, no new dependencies, no new shared state). Data shapes declared as
explicit contracts backed by named sample scenarios. Views take state in and
emit events out.

Decisions outside the boundary go to `DECISIONS.md` and re-enter at Intake.
They are not made in passing.

### 5. Verify & Land

Something must return pass/fail without you: build, tests, static checks, and
for UI a capture compared against the design.

Review in a fresh session — never the one that wrote the code — scoped to
correctness and stated requirements only. No style preferences, no suggested
abstractions.

---

## Definition of done

Mechanically checkable. All must hold.

- [ ] Build and static checks pass
- [ ] Every state in the design reachable in a preview or harness without real data
- [ ] No view acquires its own data
- [ ] No dependency added that wasn't agreed
- [ ] Domain terms match the shared vocabulary
- [ ] Nothing added "for flexibility later"
- [ ] Deferred decisions recorded in `DECISIONS.md`, not decided silently

---

## What keeps the codebase readable

By agents and people, for the same reasons.

1. **Unremarkable for its platform.** Follow the platform's own conventions.
   Every deviation costs you forever, in restating it and in surprising
   whoever reads it next.
2. **One term per concept, across every platform.**
3. **The view boundary held.** State in, events out.
4. **No speculative abstraction.** Build the two tables you have, not the
   generic table you might need.
5. **Deletion preferred to addition** in every review.

---

## Speed rules

- The `Just Ship` lane has no ceremony. That is the point of it.
- Plan in cheap context; execute in a fresh session.
- Fork heavy work (research, test generation, audits) to subagents.
- Lightest capable model for mechanical work.
- Two failed corrections → clear and restate, don't push on.
- More than ~5 screens in one build → split it, even though it feels slower.
