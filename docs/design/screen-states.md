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

- **Mic permission.** The handoff assumes "mic permission prompt on first
  record" and stops there. Undesigned: the pre-prompt moment, **denied**,
  **restricted**, and permission revoked in Settings between launches. There is
  no disabled-Record treatment and no route to Settings — on the first tap of
  the app's primary action.
- **Mic already in use** by another app or an active call. Record should be
  unavailable; no state exists for it.

### Audio session and lifecycle

- **Interruptions** — call, Siri, alarm, another app taking the session, during
  record or playback. No paused-by-interruption state, no resume-or-discard
  decision, no indicator.
- **Route change** — headphones unplugged mid-record or mid-playback. iOS
  convention is to pause; nothing is drawn.
- **Backgrounding while recording** — continue or stop? Undecided.

### Failure and recovery

- **Recording failures** — disk full, write error, session activation failure,
  encoder failure mid-take. The design has no error surface anywhere: no alert,
  no inline error, no failed-take row.
- **Crash recovery.** `RecordingRepair` already exists for takes a jetsam kill
  left unfinalised, so recovered takes are real. Undesigned: how a recovered
  row reads, what an unknown duration shows, whether anything prompts on the
  next launch.
- **Playback file errors** — file missing, moved, or corrupt (the row exists,
  the audio doesn't). No broken-row or failed-playback state.
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
