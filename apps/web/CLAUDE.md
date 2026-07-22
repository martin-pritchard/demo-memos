# apps/web — the marketing site

Astro, static output. Describes what the app does; it is not the app. Currently
a scaffold: the stock Astro index page, no content. See @../../PRINCIPLES.md for
where new code goes.

## Vocabulary

- **memo** — the one thing the product is about. Not "note", "entry", or "item".
  The app says "memo" too; the two must not drift.
- **app** / **site** — `apps/ios` and `apps/web`. They share no code, only this
  vocabulary. A feature described here must exist there.

## Commands

From the repo root, or `npm run <script>` inside `apps/web`:

| Command         | What                                                    |
| --------------- | ------------------------------------------------------- |
| `make test-web` | Build the site; a failed build is the only failure mode |
| `make lint-web` | Prettier check + `astro check`                          |
| `make fmt-web`  | Format everything                                       |

`npm run dev` for the dev server. Format and lint also run on every file write.

## Non-obvious

- **`npm install` here, never at the root.** There is no JS monorepo tooling and
  no root `package.json` — the iOS app is not a JS package. This is a standalone
  npm project that happens to live in this repo.

- **No test runner, no unit tests.** `make test-web` builds. Adding a test
  framework is a decision — record it in @../../DECISIONS.md.

- **Static output only.** No SSR adapter, so there is nowhere to put a secret
  even if you wanted one.

- **`astro check` is the linter, not ESLint.** It type-checks `.astro`
  templates, which ESLint cannot.
