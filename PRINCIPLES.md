# Architecture Principles

Stack-agnostic conventions for how code in this project is organised. These
are the *rules*; the *mechanisms* that implement them differ per stack and
live in the per-stack appendix (e.g. `PRINCIPLES.ios.md`, `PRINCIPLES.web.md`)
and in this project's `CLAUDE.md`.

**For agents:** follow these when creating, moving, or naming files. When a
principle and a mechanism seem to conflict, the mechanism in the stack
appendix wins for *how*; this file governs *why* and *where*. If a change
would violate a principle, stop and flag it rather than working around it.

---

## Core principles

### 1. Group by feature, not by type
Code that changes together lives together. Organise the tree around what the
app *does* (a feature), not what each file *is* (a view, a model, a service).

- A feature owns its screen(s), its state, and the small pieces used only by
  it.
- The `Views/` + `Models/` + `Services/` split is banned as a top-level
  layout. It looks tidy at ten files and becomes an undifferentiated dumping
  ground at eighty.
- **Smell:** to understand one feature you have to open four sibling folders.

### 2. Colocate; promote only on second use
Put a thing next to the one place that uses it. Move it to a shared location
only when a *second* consumer actually appears — not in anticipation of one.

- A component used by exactly one feature lives inside that feature.
- A component used by two or more features moves to the shared UI layer.
- **Smell:** a shared/common folder full of things imported from exactly one
  place.

### 3. Keep a UI-free core
Domain models, business logic, networking, persistence, and any engine code
must not import the UI framework. This layer is pure, portable, and testable
without spinning up UI.

- The UI layer is a thin projection over this core, not a home for logic.
- Business logic must never live inside a view/component body.
- **Smell:** you can't unit-test a rule without rendering something.

### 4. One primary type per file; file named after the type
`Thing` lives in `Thing.<ext>`. This makes search, grep, and "jump to
definition" deterministic — for humans and agents alike.

- Small tightly-coupled helpers may share the file, but there is one obvious
  primary type per file.
- **Smell:** finding a type requires opening files whose names don't mention
  it.

### 5. Make boundaries explicit and machine-readable
What is public API vs internal implementation should be declared, not implied.
Prefer real modules/packages with a manifest that spells out the dependency
graph.

- A manifest (package/workspace file) is a dependency graph an agent can read
  directly — lean on it.
- Use the language's access control to keep a module's internals internal.
- **Smell:** any file can reach into any other file's internals.

### 6. One obvious composition root
There is exactly one place where the app starts, where routing is wired, and
where dependencies are constructed and injected. It is easy to find and named
predictably.

- Dependencies are passed in (via initialisers/props/DI), not reached out for.
- **Smell:** an agent has to hunt to answer "where does this get instantiated?"

### 7. Be relentlessly consistent across features
Every feature has the same internal shape and the same naming. Predictability
beats cleverness: if all features look alike, the location of any file can be
*predicted* without searching.

- Pick one UI-state pattern and one feature-folder layout, then never deviate.
- **Smell:** three features, three different architectures.

### 8. Match structure to scale — climb the ladder, don't skip to the top
Add structure in response to real pressure (build times, parallel work,
boundaries you actually need to enforce), not pre-emptively.

- **Prototype:** single target, feature folders, minimal ceremony, no modules.
- **Small–medium (the common sweet spot):** feature folders + a small number
  of shared packages (typically a core + a design/shared layer); abstractions
  only where a real test seam or swap exists.
- **Large / many actors in parallel:** module-per-feature, enforced
  boundaries, explicit DI root, a documented unidirectional data-flow pattern.
- **Smell of over-engineering:** a protocol/interface with one implementation
  and no test; a module that reduces neither build time nor coupling; a DI
  framework replaceable by an initialiser; a heavyweight state pattern on a
  five-screen app.

---

## Anti-patterns (reject these)

- **Group-by-type at scale** — the `Views/` junk pile (see #1).
- **Junk drawers** — `Utils`, `Helpers`, `Common`, `Managers`, `Misc`.
  Unbounded folders that hide real domain concepts. A `Manager`/`Helper`
  suffix on everything is a naming smell; name the concept instead.
- **God objects** — a massive view or a massive state object doing everything.
- **Logic in the UI** — networking/persistence/rules inside view bodies (see
  #3).
- **Ambient singletons / global mutable state** — `.shared` everywhere; hard
  to test, hard to trace.
- **Circular dependencies** — A depends on B depends on A. Modules prevent
  this structurally; folders don't.
- **Inconsistency** — features that each invent their own structure (see #7).
- **Premature abstraction** — indirection with a single caller and no seam.

---

## Where does new code go? (decision procedure)

1. **Is it UI?**
   - No → it belongs in the UI-free core, in the sub-area that matches its
     concern (domain / networking / persistence / engine). Do not add a UI
     import.
   - Yes → continue.
2. **Is it a whole screen or a feature's own state?** → inside that feature's
   folder.
3. **Is it a component used by only one feature?** → inside that feature
   (colocate). Do **not** put it in the shared layer yet.
4. **Is it a component now used by two or more features?** → promote it to the
   shared UI/design layer.
5. **Is it app startup, routing, or dependency wiring?** → the composition
   root.
6. **Tempted to create `Utils`/`Helpers`/`Common`?** → stop. Name the actual
   concept and place it by concern instead.

When unsure, prefer the more local location and promote later (see #2).

---

## Using this file

- `/setup` copies it into each repo; the repo's copy is the live one — adapt
  it, and add stack appendices as the project grows.
- Reference it from the repo's `CLAUDE.md` with a plain mention ("Placement
  rules live in PRINCIPLES.md — read it before creating or moving files"),
  not an `@` import — build sessions load it on demand; other sessions
  shouldn't carry it on every turn.
- Keep `CLAUDE.md` for the project-specific parts: the actual folder tree,
  build/test commands, and any exceptions to these principles.
- Keep stack-specific *mechanisms* (module system, UI-state API, boundary
  enforcement, file-naming specifics) in the stack appendix, not here.
