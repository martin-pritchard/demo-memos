# Decisions

One entry per decision that a reader of the code could not infer from the code:
what was chosen, what it was chosen over, and why. Append; don't rewrite history
— supersede an entry with a later one instead.

---

## Deferred at scaffold time (2026-07-22)

These are not oversights. Each was considered and left out because nothing
currently needs it, and adding it would have been a guess about a requirement
that does not exist yet. Listed so the next person knows the omission was
deliberate and knows what to weigh when it stops being.

### Product

- **All app features.** The iOS app is one "Hello World" scene; the site is the
  stock Astro index page. The scaffold deliberately ends where the product
  begins.
- **Persistence.** No SwiftData, Core Data, or file storage. This is the first
  real architectural decision the app will face and it should be made against a
  concrete feature, not in advance.
- **Networking, and therefore any backend.** No client, no API. Note that this
  is also what keeps the "no secrets in a public repo" rule cheap to hold — the
  moment the app talks to an authenticated service, re-read `docs/security.md`
  before writing any code.
- **A state-management library.** SwiftUI's built-in property wrappers are
  sufficient at this size and `PRINCIPLES.md` §8 explicitly warns against a
  heavyweight state pattern on a small app.
- **Feature folders under `apps/ios/DemoMemos/`.** `PRINCIPLES.md` §1 mandates
  grouping by feature; with zero features there is nothing to group. Create the
  first folder with the first feature, not before.

### Tooling

- **A `.swift-format` config file.** swift-format runs on its defaults, so
  house style is the tool's default and nobody has to agree to anything. Note
  the default indent is 2 spaces, which reformatted Apple's 4-space templates
  on first run. Add a config only to resolve a real dispute.
- **A Prettier config beyond the Astro plugin.** Same reasoning: defaults are a
  convention nobody had to invent.
- **ESLint.** `astro check` type-checks `.astro` templates, which ESLint can't;
  a second linter would add a dependency and a second set of rules to reconcile
  for no coverage gain.
- **A web test runner** (Vitest, Playwright). `make test-web` asserts the site
  builds, which is the only failure a static content site currently has.
- **CI.** Root `CLAUDE.md` specifies path-filtered per-app workflows; no
  workflow files exist yet. `make lint` and `make test` are the intended
  entry points when they do.
- **A CLAUDE Code hook on `Bash`/`git commit`.** Formatting is enforced on
  write and secrets on commit; a third enforcement point would be redundant.
- **Astro telemetry.** Left at its default (on). It is a machine-global setting,
  not a repo one, so the repo can't turn it off for you — `astro telemetry
  disable` if you want it off.

### Repo

- **`README.md` is empty.** Left as-is; not in scope for the scaffold.
- **`packages/` and `apps/api/`.** Reserved by root `CLAUDE.md`, still unused.
- **A per-app `.gitignore` for `apps/web/`.** Astro ships one; it was dropped
  because the root `.gitignore` already covers `node_modules/`, `dist/`,
  `.astro/`, and `.env*`. One ignore file, one place to look.
- **`.vscode/` and `AGENTS.md` from the Astro template.** Dropped: this repo's
  agent convention is `CLAUDE.md`, and editor settings are personal. Watch for
  this on `astro` upgrades — the template ships `CLAUDE.md` as a *symlink* to
  `AGENTS.md`, which will silently replace the real file if you re-scaffold.
