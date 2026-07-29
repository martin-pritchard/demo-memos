# Screen states

Every distinct state each screen can be in — the ones the designs draw, and the
ones the app will need that they don't.

Derived from the handoff bundle in this folder (`README.md`, `demo-memo.dc.html`,
`demo-scene.jsx`); **not part of the original import** — see `import-notes.md`.
The bundle stays the source of truth for how a state *looks*; this file is the
checklist of *which states exist*, so an undesigned one gets a decision rather
than an improvisation at build time.

## How to read this

- ✅ drawn — a render exists in the bundle.
- ⚠️ named — mentioned in prose or tokens, never drawn.
- ❌ undesigned — listed under [Open questions](#open-questions--undesigned-states).
- `#1a`-style anchors are turns in `demo-memo.dc.html`.
- The handoff calls the Take screen's first state `ready`; `demo-scene.jsx`
  calls it `monitor`. They are the same state — monitoring is parked
  (post-MVP), so it is `ready` with no pill. This file uses `ready`.

---

## 1. App / root

| State | | Notes |
|---|---|---|
| First launch, `hasOnboarded == false` → Onboarding | ✅ `#5a` | Persisted flag |
| Normal launch → Demos list | ✅ `#1a` | |
| Light / Dark appearance | ✅ `#t1` / `#t2` | Follows the system setting. Every screen has a dark twin except Onboarding |
| Reduce Motion on | ⚠️ | "Freeze the waveform animation and count-in scaling" — stated, not drawn |

## 2. Onboarding — `OnboardFeatures`

One page, no pagination, no skip, no back.

1. **Presented** — title, three feature rows, Continue. ✅ `#5a`
2. **Dismissed for good** — flag written on Continue; never shown again.

There is no dark-mode render (the doc's own "try next" note asks for one).

## 3. Demos list — `DemosListScreen`

| # | State | | Notes |
|---|---|---|---|
| 3.1 | **Populated** | ✅ `#1a`, dark `#2a` | Card of rows, "Swipe a demo to share" caption, floating New Demo capsule |
| 3.2 | **Empty** | ✅ `#4a` | "Capture your first demo" + body, centred −20pt, no illustration. The capsule stays in place |
| 3.3 | **Row swiped open** | ✅ | −152pt; Share (`#0A84FF`) + Delete (`#FF3B30`), 76pt each |
| 3.4 | **Row mid-drag** | ✅ | Clamped 0…−152; snaps open past −64pt, otherwise closes |
| 3.5 | **Delete confirmation** | ✅ | "Delete “{name}”? This can't be undone." / Delete Recording / Cancel, over a scrim |
| 3.6 | **Share sheet over list** | ✅ | |
| 3.7 | **Scrolled** | ✅ | Content passes under the capsule behind the bottom fade |

`demo-scene.jsx` also carries two *unused* empty-state variants (`illustrated`,
`rows`). `symbol` is the shipped one; the others are rejected options, not
states to build.

## 4. Take screen — `TakeScreen`

The handoff's matrix lists four states. The prototype has **five** — `countin`
is a real mode with its own header, timer and button rendering, and it is
missing from that table.

| # | Mode | Header left | Header right | Left button | Right button | Timer | Waveform |
|---|---|---|---|---|---|---|---|
| 4.1 | `ready` | Cancel | — | Play, `opacity .35`, disabled | ◉ Record (disc @ 78%) | `00:00`, greyed to `text4` | Flat resting line (bars at 0.05); **does not react to input** |
| 4.2 | `countin` | Cancel | — | Play disabled | Numeral in the ring, 28/560 accent, `scale(1.25)→1` per beat. **Tapping it aborts → `ready`** | still greyed `00:00` | still flat |
| 4.3 | `recording` | Cancel | — | Play disabled | ▪ Stop (rounded square, 40%, r9) | counts up, full contrast | Live rolling meter, newest bar at the right, ~95 ms/bar |
| 4.4 | `stopped` | Cancel | Share ⃒ Done | ▶ Play | ◉ Resume (disc @ 40%) | reads playhead | Centre-locked scrub, playhead parked at the end (`p = 1`) |
| 4.5 | `playback` | ‹ Demos | Share ⃒ Done | ▶ Play / ⏸ Pause | ◉ Resume | reads playhead | Centre-locked scrub, entered at a position |

All five are ✅ (`#1b`, `#8a`, `#3a`, `#1c`; dark twins `#2b` / `#2c`).

### Sub-states layered on the five

| State | | Notes |
|---|---|---|
| **Play ↔ Pause** | ✅ | Glyph *and* label both flip while playing (4.4, 4.5) |
| **Resume disabled while playing** | ✅ | Dimmed to `.35` in the prototype; the handoff's table omits it |
| **Playhead at the end** | ✅ | Playback auto-stops at `p = 1`; the next Play restarts from 0 |
| **Scrubbing** | ✅ `#12a` | Drag the waveform (not the marker), 1:1 with bar geometry; the time label tracks the centre marker |
| **Title editing** | ✅ `#1c` | Playback only — an inline field. Static text in `ready` / `recording` / `stopped` |
| **Enhance: five tone bands** | ✅ | Dry / Room / Warm / Studio / Hall. Label, bar ramp and bloom update continuously. Default 0.5 |
| **Input coaching — clear** | ✅ | The 24pt slot is reserved and empty (`opacity 0`) |
| **Input coaching — low** | ✅ | "Move a little closer", secondary text. Recording only |
| **Input coaching — hot** | ✅ | "A little hot — ease back", `#FF453A` + warning glyph, held 900 ms past the peak. Recording only |
| **Clipping bars** | ⚠️ | While recording, a bar ≥ 0.9 gets a red `#FF453A` top segment and a red glow. Only the token is documented; the behaviour appears in `demo-scene.jsx` alone |
| **Share sheet** | ✅ | Over 4.4 or 4.5 |

### The reserved line — one slot, one resolver

Settled by `#16`, **FINAL**. One reserved slot above the transport carries
**every** in-place message: centred line, optional second line, optional tinted
capsule. No cards, no empty states, no second channel — the row and full-block
forms explored earlier are **gone**. The slot is the only form that already
exists in the layout, and using it keeps the screen identical in every state:
nothing above it moves, nothing below it jumps.

It is shared with the transient coaching line, so it resolves by **precedence,
not a second channel**:

> **mic state → playback failure → capacity → coaching** — highest one wins.

They barely compete in practice: coaching only speaks while capture is running,
and every mic notice means capture can't run. Two behavioural differences hold,
and they are the whole distinction between the two kinds of message:

- A **notice** appears instantly and **persists**; **coaching** cross-fades.
- Only a **notice** may carry an **action**.

| Message | Channel | Form | |
|---|---|---|---|
| Mic denied / restricted / unavailable | Notice | Reserved line + Open Settings capsule | ✅ `#16a`, dark `#16e` |
| Playback failure — file missing or damaged | Notice | Reserved line + **Try Again** | ✅ `#16d` |
| Low space, non-default input | Notice | Reserved line, no capsule | ⚠️ S20 / S21 |
| Input too quiet / clipping | Coaching | Reserved line, three-case enum, cross-fades | ✅ |
| Recording failure — write error, storage full, revoked mid-take | Alert | System alert | ✅ `#15e` |
| Interruption — call, Siri, another app | Neither | State change only: header **Paused**, right button Resume | ⚠️ S22, no mock |
| Playback reached the end | Neither | Marker parks, button returns to Play | ✅ |

**In build:** one slot, one resolver — the screen picks the highest-precedence
message and renders it. `#16` names `InlineNotice` (`#13a`) as *being* that
slot rather than a new component, so this grows the existing coaching line
rather than adding a sibling to it.

**One transport rule** (`#16f`): a transport button is dim whenever it *cannot
act* — `opacity .35` for Play/Resume, `.45` for the blocked Record disc. "No
take yet" and "no microphone" get the same treatment. Never enabled-and-inert.
This retires the open question of whether `.resume` should be dimmed or
enabled-and-inert: **dimmed**.

### Microphone unavailable — the four states

Settled by `#15`. **Only the record flow is affected** — the list and playback
stay fully usable, so nothing already captured is held hostage to a permission.
A permission notice is **never red**: it is a state, not an error.

| # | Case | `perm` | Line | Route out | | |
|---|---|---|---|---|---|---|
| 4.6 | **Denied** (S13) | `denied` | "Microphone access is off" | Open Settings capsule | ✅ `#15a` | In place, no alert |
| 4.7 | **Restricted** (S41) | `restricted` | "Microphone access is restricted" / "Managed in Screen Time" | none — the switch won't move | ✅ `#15b` | In place, no alert |
| 4.8 | **No input device** (S14) | `nodevice` | "No microphone available" / "Connect a microphone to record" | none — Settings can't fix hardware | ✅ `#15c` | Never phrased as permission |
| 4.9 | **Revoked between launches** | `revoked` | as denied, plus an alert on entry | Not Now / Open Settings | ✅ `#15d` | It worked last time, so it earns the interrupt |

**Disabled-Record treatment**, shared by all four: the ring holds its place at
`4pt recBorder`, the accent disc becomes a `text3` grey disc at the same 78%
size, the whole button sits at `opacity 0.45` (`.2s`), and the "Record" label
drops to `text4`. The Enhance dial dims to `opacity 0.4` and stops accepting
input. The reason itself goes in the reserved line, never in a block or a card.
Dark twin: `#15f`.

**Mid-take alerts** — both land on `stopped` with the partial take, and both
lead with what *survived*, by name and length, before mentioning Settings:
revoked mid-take (S28) and storage full (S27), the same component with two
words changed.

## 5. Share sheet

Presented / dismissed, over the list or the Take screen. The bundle draws the
intended *payload* (header row, app row, Copy Link / Save to Files / Export
Audio…) but the handoff is explicit: use `ShareLink` / `UIActivityViewController`
and don't build it. Its states are the system's.

## 6. Parked — live monitoring (post-MVP)

Documented in `#t7` / `#t9` and **explicitly out of MVP scope**: the
`Monitoring` (wired) pill, the dimmed `Monitoring off` + ⓘ pill, the hint-line
swap, and the medium-detent explainer sheet. Recorded here so the header's
right-hand slot isn't accidentally reused by something else.

---

## Conflicts inside the bundle

Resolve these before building the state they touch; the bundle disagrees with
itself.

- **Count-in length.** The handoff says a "3-beat count-in"; `#8a` and
  `demo-scene.jsx` both count **4·3·2·1**.
- **"Warm" tone threshold.** `< 0.60` in the handoff table, `< 0.62` in
  `toneName()`.
- **Playback transport.** The `TakeScreen` doc-comment says playback has "a
  single Play button"; every render and the `#1d` matrix show Play + Resume.
- **An unrendered `enhanced` flag.** The list's seed data carries
  `enhanced: Bool` per demo that nothing draws. Either a badge was cut or it was
  never designed — decide which before the field reaches the domain model.

---

## Open questions — undesigned states

States the app will need that the designs don't cover. Each one needs a
decision; none should be improvised silently at build time.

### Permissions and availability

- ~~**Mic permission.**~~ **Closed by `#15`** — denied, restricted, no input
  device and revoked-between-launches all have renders, copy, a shared
  disabled-Record treatment and a routing rule. See [4.6–4.9](#microphone-unavailable--the-four-states).
- **The pre-prompt moment.** Still undesigned: what the screen shows between
  tapping Record for the first time and the system prompt being answered.
  `#15` covers every *outcome*, not the wait.
- **Mic already in use** by another app or an active call. Record should be
  unavailable; no state exists for it. `#15c`'s `nodevice` treatment is the
  obvious fit, but the line ("No microphone available") is wrong for it and the
  case is not named in `#15g`.

### Audio session and lifecycle

- **Interruptions** — call, Siri, alarm, another app taking the session, during
  record or playback. **Partly closed by `#16f`**: the *channel* is decided —
  neither notice nor alert, a state change only, with the header reading
  **Paused** and the right transport button becoming Resume, on the reasoning
  that "a notice explaining the thing you just lived through is noise, and the
  take is intact". Still open: no mock exists (S22), and the design assumes a
  working Resume, which is #4. Until then the state is reachable with its
  intended affordance dim.
- **Route change** — headphones unplugged mid-record or mid-playback. iOS
  convention is to pause; nothing is drawn.
- **Backgrounding while recording** — continue or stop? Undecided.

### Failure and recovery

- **Recording failures** — disk full, write error, session activation failure,
  encoder failure mid-take. **Partly closed by `#15e` / `#16f`**: there is now
  an error surface — a system alert, used only when capture stopped or never
  started *against the user's expectation*, leading with what was saved. Storage
  full (S27) and revoked mid-take (S28) have final copy. Still open: write
  error, session-activation failure and encoder failure are not named, and
  there is no failed-take row.
- **Crash recovery.** `RecordingRepair` already exists for takes a jetsam kill
  left unfinalised, so recovered takes are real. Undesigned: how a recovered
  row reads, what an unknown duration shows, whether anything prompts on the
  next launch.
- **Playback file errors** — file missing, moved, or corrupt (the row exists,
  the audio doesn't). **Closed on the Take screen by `#16d`**: the reserved
  line, not an alert and not an empty state — "This demo couldn't be opened" /
  "The audio file is missing or damaged. The rest of your demos are fine." with
  a **Try Again** action. The take's drawing survives (peaks are stored
  locally), so the screen stays recognisable. Still open: the *list* side — no
  broken-row treatment exists, and `#16f` says only that the failure is local
  to one demo.
- **Export / share processing.** "Export Audio…" implies rendering Enhance
  offline into a shareable file, which takes real time on a long take. No
  progress, cancel, or failure state — the sheet simply appears.

### Data and persistence

- **List loading.** The first frame before persisted takes load. Empty and
  populated are drawn; "not yet known" is not — pick wrong and the empty state
  flashes on every cold launch.
- **`New Demo {n}` after deletions.** The prototype uses a naive incrementing
  counter. Delete "New Demo 3", record again — collision, or a gap? Unspecified.
- **Row dates beyond a week.** Samples cover Today / Yesterday / Monday. Nothing
  for older.

### Editing and save semantics

- **Cancel from `stopped` destroys a captured take with no confirmation**, while
  deleting from the list gets a full destructive action sheet. Inconsistent, and
  the confirm sheet for Cancel isn't drawn.
- **Save on exit from playback.** Playback has a Done button, an editable title
  *and* a live Enhance dial. If ‹ Demos is tapped instead of Done, are the
  rename and the new Enhance value kept or dropped? Two exits, undefined
  difference.
- **Rename edge cases** — empty or whitespace-only name committed, a very long
  name (row truncation and 24pt title wrap are both undrawn), the keyboard
  covering the field, whether there's a cancel, and whether the rename commits
  per keystroke or on Done.

### Playback and scrub behaviour

- **Resume from a scrubbed position.** `stopped` lets you scrub *and* Resume.
  Does Resume append to the end or overwrite from the playhead? This changes
  both the audio engine and what the waveform should do.
- **Scrub while playing.** Does dragging pause, or scrub live? The prototype's
  playhead animation and drag handler fight each other; no intent is stated.

### Boundaries

- **Zero-length take** — Record then Stop immediately: a 0:00 take with no bars.
- **Very long take** — `MM:SS` has no hour form, so anything past 59:59 renders
  wrong. No maximum-duration policy either.

### Accessibility and display

- **Dynamic Type at accessibility sizes** — the 66pt row, the 56pt timer and the
  fixed 300pt Enhance track all break.
- **VoiceOver** — labels and adjustable actions for the waveform and the tick
  dial. Both are drag-only controls with no accessible alternative.
- **Reduce Transparency** against the glass capsule and the sheets.
- **Increase Contrast** against `text3` / `text4`, and the amber marker over
  amber bars.
- **Orientation.** iPhone-only is stated; portrait-only is not. The 402 × 874
  layout has no landscape story.

### System integration

- **Lock screen / Control Center / Now Playing.** No `MPNowPlayingInfo`
  presence is designed — users will expect it for playback.
