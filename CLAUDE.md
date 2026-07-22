# demo-memos

Two deliverables for one product: the iOS app, and a marketing site that describes it.
They share no code — only a product surface. This repo exists so that surface stays in sync.

## Layout

| Path | What | Stack |
|---|---|---|
| `apps/ios/` | The app itself | SwiftUI |
| `apps/web/` | Marketing site outlining features | undecided |

## Routing

Working on the app → read `apps/ios/CLAUDE.md`.
Working on the site → read `apps/web/CLAUDE.md`.
Build commands and conventions live in those files, not here.

## Architecture

See [PRINCIPLES.md](PRINCIPLES.md)

## Secrets — this repo is public

**It contains no secrets, and must not.** No keys, tokens, certs, or `.env` files —
not in source, config, or tests. Public means public the moment it's pushed.

Never "just for now" a credential into a file. If a task seems to need one, stop and
raise it: the answer is architectural, not a `.gitignore` entry. Note especially that
a key shipped in an iOS binary is extractable by anyone, so gitignoring an `.xcconfig`
does **not** make it secret.

If a secret ever does get committed: **rotate it first**, before touching git history.
See `docs/security.md` for why, and for the pre-commit hook setup.

## Conventions

- No JS monorepo tooling. Each app builds with its own toolchain. Don't add a root `package.json`.
- `apps/` is namespaced for growth: `packages/` and `apps/api/` are reserved but unused.
- CI is path-filtered per app — a change under `apps/ios/` must not trigger the web build.
