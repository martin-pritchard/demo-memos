---
name: triage
description: Triage untriaged backlog issues into lanes and set their board status. Run when the user asks to triage the backlog.
disable-model-invocation: true
allowed-tools: Bash(gh:*), Read
---

# Triage

Batch operation. Run in its own session; the user clears context afterwards.

## Step 1 - propose

List untriaged issues:

```
gh issue list --label backlog --json number,title,body
```

For each issue, ask in order and stop at the first yes:

| | Question | Lane |
|---|---|---|
| 0 | Would we notice if this never got built? If no, propose closing it | - |
| 1 | If we get this wrong, is it expensive or impossible to undo? (user data, money, auth, public contracts, migrations) | Think Hard |
| 2 | Does it cross a seam? (new persistence, new external dependency, new shared state, or changes an existing contract) | Think A Little |
| 3 | Otherwise | Just Ship |

When unsure, use blast radius, not effort. Worst outcome is a screen looks
wrong, use Just Ship. Worst outcome is data is wrong, use Think Hard.

Importance is not size. A one-line change to a pricing calculation is Think
Hard. A large UI build against existing components is Just Ship.

Output a single table: number, title, proposed lane, one-line reason. Include
any issue proposed for closing. Set nothing yet. Do not elaborate.

Then stop and wait.

## Step 2 - apply

Only after the user confirms or corrects the table. For each issue:

- Set the `Lane` field
- `Just Ship` goes to Status "Ready For Development"
- `Think A Little` and `Think Hard` go to Status "In Refinement"
- Replace the `backlog` label with the lane label
- Append acceptance criteria to the body: three bullets maximum, observable
  outcomes only
- Close any issue the user agreed to close

## Constraints

- Never set a lane the user has not seen
- Never expand an issue body beyond three acceptance criteria
- Use explicit `--json` fields on every `gh` call; never list without a filter
