# sdlc

A risk-triaged development process. Ideas in one end, verified work out the
other, with the amount of ceremony matched to what breaks if you get it wrong.

The process itself is documented in `SDLC.md` (for humans) and
`SDLC-github.md` (board wiring). Everything below is the machinery.

## Components

| Component | Type | Invoked |
|---|---|---|
| `build-rules` | skill | by Claude, whenever implementing |
| `/triage` | skill | by you |
| `/build <n>` | skill | by you |
| `/new-app` | skill | by you |
| `/audit` | skill | by you |
| `blind-test-writer` | agent | spawned |
| `scoped-reviewer` | agent | spawned |
| formatter | hook | automatically on write |

`build-rules` is the only skill Claude invokes on its own. The other four
carry `disable-model-invocation: true`, so they cost nothing until you type
them.

## Install

Fastest path, no marketplace:

```
cp -r sdlc ~/.claude/skills/sdlc
```

It loads next session as `sdlc@skills-dir`. Verify with `/plugin` or
`claude plugin list`.

To test without installing:

```
claude --plugin-dir ./sdlc
```

To distribute across repos, push to a git repo and:

```
/plugin marketplace add <owner>/<repo>
/plugin install sdlc@<marketplace>
```

## Setup

Two things this plugin cannot do for you.

**Fill in `hooks/scripts/format.sh`** with the formatter for your stack. It is
a stub. Until you do, formatting is unenforced and will start leaking into
CLAUDE.md, which is what the hook exists to prevent.

**Create the board.** In your GitHub Project:

- Status: `Backlog`, `In Refinement`, `Ready For Development`,
  `In Development`, `In Review`, `Done`
- Lane: `Just Ship`, `Think A Little`, `Think Hard`
- Auto-add workflow filtered to `is:issue is:open`
- An issue template applying the `backlog` label

Details in `SDLC-github.md`.

## Notes

- Edits to a `SKILL.md` take effect immediately. Changes to `hooks/` or
  `agents/` need `/reload-plugins` or a restart.
- Run `claude plugin validate .claude-plugin/plugin.json` after changes.
- `argument-hint` and `disable-model-invocation` are Claude Code skill
  frontmatter fields. If validation rejects either, drop it - the skills still
  work, they just become model-invocable.
- Keep every file here short. A bloated process plugin is the thing this
  process exists to avoid.
