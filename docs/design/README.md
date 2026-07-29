# Handoff: Demo Memos (iOS)

## Overview
**Demo Memos** is a single-purpose iOS audio recorder for musicians: "Voice Memos, but for demos." Capture a musical idea in one tap, shape it with a single **Enhance** dial, share it anywhere.

The MVP is three screens plus onboarding:

1. **Demos** — home list of takes (swipe row → Share / Delete)
2. **Take** — one view that covers record *and* playback, driven by a `mode` state
3. **Onboarding** — one-time first-launch intro

Live input monitoring (hearing yourself through headphones) is **explicitly out of MVP scope** — see [Future / parked](#future--parked).

## About the design files
The files in this bundle are **design references created in HTML/React** — prototypes that show intended look, layout and behaviour. They are **not production code to port**.

The task is to **recreate these designs in the target codebase's environment**. This design is drawn as a native iOS app at iPhone logical-point scale, so the natural target is **SwiftUI (iOS 18+)** using system components (`NavigationStack`, `.sheet` with detents, `ShareLink`/`UIActivityViewController`, swipe actions, SF Symbols, `Color.primary`/`.secondary` semantic colours). If the receiving project already has an established environment (React Native, Flutter, etc.), follow its patterns instead.

Where the prototype hand-rolls something iOS gives you for free — share sheet, action sheet, swipe actions, grabber sheets, list rows, large-title header — **use the system component**. The prototype only re-implements them because HTML has no equivalent. Match the design's *spacing, type and colour*, not its DOM.

## Fidelity
**High-fidelity.** Colours, type sizes, weights, spacing, radii and interaction behaviour are all final and intentional. Recreate pixel-accurately, but prefer native/system equivalents for standard iOS chrome.

Canvas: **402 × 874 pt** (iPhone 16 Pro logical size). All px values in this doc = iOS points 1:1.

---

## Design tokens

### Accent (the only colour in the app)
| Token | Value | Use |
|---|---|---|
| `ACCENT` | `#FF9F0A` | Primary accent: record disc, Enhance marker, buttons, links. Used as-is in dark mode. |
| `ACCENT_DEEP` | `#FF7A00` | Light-mode text/glyph variant of the accent (contrast on light backgrounds). |
| `accent @ α` | `rgba(255,159,10,α)` | Fills/glows: `0.14` play-button bg (light), `0.20` (dark), `0.16` sheet thumb, `0.34`–`0.40` shadows, `0.90` New Demo capsule. |

### Semantic colours
| Token | Light | Dark |
|---|---|---|
| `pageBg` | `linear-gradient(180deg,#FBFBFD,#F2F2F6)` | `linear-gradient(180deg,#1C1C1E,#000)` |
| `text` | `#1C1C1E` | `#FFFFFF` |
| `text2` (secondary) | `rgba(60,60,67,0.5)` | `rgba(235,235,245,0.6)` |
| `text3` (tertiary) | `rgba(60,60,67,0.4)` | `rgba(235,235,245,0.4)` |
| `text4` (quaternary) | `rgba(60,60,67,0.3)` | `rgba(235,235,245,0.3)` |
| `card` | `#FFFFFF` | `#2C2C2E` (lists) / `rgba(118,118,128,0.16)` (glass) |
| `divider` | `rgba(60,60,67,0.1)` | `rgba(255,255,255,0.1)` |
| `barOff` (unplayed waveform) | `rgba(120,120,128,0.28)` | `rgba(235,235,245,0.22)` |
| `recBorder` (transport ring) | `rgba(0,0,0,0.14)` | `rgba(255,255,255,0.24)` |
| `tickMaj` / `tickMin` (Enhance scale) | `rgba(60,60,67,0.32)` / `rgba(60,60,67,0.15)` | `rgba(235,235,245,0.4)` / `rgba(235,235,245,0.18)` |
| destructive | `#FF3B30` | same |
| share-action blue | `#0A84FF` | same |
| clip / hot warning | `#FF453A` | same |

These map almost 1:1 onto iOS semantic colours (`.label`, `.secondaryLabel`, `.systemGroupedBackground`, `.systemRed`) — **prefer the semantic system colours**; they give you dark mode and accessibility contrast for free.

### Warm waveform colour ramp
Played/enhanced bars are generated from a single `warmth` value 0…1 (= the Enhance value), in OKLCH so hue stays in the amber family:

```
warmColor(w, α) = oklch(L C H / α)
  L = 0.74 − w × 0.07
  C = 0.008 + w × 0.16
  H = 72 − w × 10
```

So `w=0` is a near-neutral warm grey and `w=1` is a saturated amber. Played bars use `warmColor(0.35 + warmth × 0.65)`; unplayed bars use `barOff`.

### Typography
System font (`SF Pro` / `-apple-system`) throughout. No custom fonts.

| Role | Size | Weight | Tracking |
|---|---|---|---|
| List large title ("Demos") | 34 | 700 | +0.3 |
| Onboarding title | 32 | 720 | −0.6, line-height 1.12 |
| Take title (name) | 24 | 680 | −0.4, line-height 1.25 |
| Empty-state title | 22 | 700 | −0.4 |
| Timer | 56 | 300 | −1, **tabular numerals** |
| Nav / sheet buttons ("Cancel", "Done", "OK") | 17 | 500–640 | — |
| List row name | 17 | 590 | −0.3 |
| Sheet row label | 17 | 400 | — |
| Body / feature body | 14.5 | 400 | line-height 1.42–1.5 |
| Row meta, hints | 14 | 400 | — |
| Enhance label | 14 | 640 | +0.2 |
| Transport labels | 13 | 500 | — |
| Duration | 15 | 400 | tabular numerals |

Weights like `590`/`640`/`680`/`720` are SF's variable-weight steps — in SwiftUI use `.semibold`, `.bold`, and `.fontWeight(...)` with `.fontDesign(.default)`; approximate rather than chase exact numerals.

### Spacing, radii, shadows
- **Radii:** list card `22`, sheet card `16`, share-sheet shell `40` (inset 8pt from edges), action-sheet card `14`, app tiles `15`, feature icon tile `12`, buttons `14`–`15`, pills/discs `999`.
- **Row heights:** list row min `66`, sheet action row min `52`.
- **Screen padding:** list `64 / 20 / 12` (top/side/bottom) for header, `16` side for content; take screen header `56 / 20 / 0`; content `90 / 24 / 0`; transport tray bottom `42`.
- **Shadows:** list card `0 1px 3px rgba(0,0,0,0.04)` (light only, none in dark); primary button `0 6px 18px rgba(255,159,10,0.34)`; New Demo capsule `0 8px 24px rgba(255,159,10,0.35), inset 0 1px 0 rgba(255,255,255,0.35)`.
- **Glass:** `backdrop-filter: blur(34px) saturate(180%)` on sheets, `blur(24px) saturate(1.6)` on the New Demo capsule → in SwiftUI use `.ultraThinMaterial` / `.regularMaterial` and a `Capsule().fill(.accent.opacity(0.9))` over material.

---

## Screens

### 1. Demos (home) — `DemosListScreen`
**Purpose:** see every take, open one, share or delete one, start a new one.

**Layout (top → bottom)**
- Large title **"Demos"** — 34/700, padding `64 20 12`.
- Scrolling list, side padding `16`, bottom padding `120` (so content clears the floating capsule).
- One rounded card (radius `22`, `card` bg) containing all rows; rows separated by a `0.5pt` divider inset `16pt` from the left, full-bleed right.
- **Row:** min-height `66`, padding `0 16`. Left column = name (17/590/−0.3) over meta (14, `text2`, 2pt gap). Right = duration (15, `text3`, tabular).
- Caption under the card: "Swipe a demo to share" — 12.5, `text3`, centred, `14pt` vertical padding.
- **Floating "New Demo" capsule**, bottom-centred, `16pt` above a `40pt` safe-area inset. Padding `13 24`, radius `999`, accent-at-90% over blur, `0.5pt rgba(255,255,255,0.4)` hairline border, mic glyph `18pt` + label 16/640/−0.2 white, `9pt` gap. Content scrolls beneath it behind a bottom fade (`linear-gradient(to top, rgba(242,242,247,0.55) 30%, transparent)`; dark: `rgba(0,0,0,0.35)`).

**Sample content** (use as seed/preview data):
`New Demo 3 · Today 3:14 PM · 0:37` / `Chorus — fast · Today 11:02 AM · 0:21` / `Bridge hum · Yesterday · 1:12` / `Verse idea 2 · Monday · 0:48` / `Riff in D · Sunday · 0:15`

**Interactions**
- Tap row → Take screen in `playback` mode.
- **Swipe left** → two 76pt actions: **Share** (`#0A84FF`, share glyph + label) then **Delete** (`#FF3B30`, trash + label). Max reveal `152pt`; release past `−64pt` snaps open, otherwise closes; `transform .2s`. → In SwiftUI: `.swipeActions(edge: .trailing)`.
- Delete → destructive **action sheet**: "Delete “{name}”? This can't be undone." / **Delete Recording** (`#FF3B30`, 19/590) / **Cancel** (accent, 19/680, separate card, 8pt gap). Sheet slides `translateY(115%) → 0` over `.32s cubic-bezier(.32,.72,0,1)`; scrim fades to `rgba(0,0,0,0.28)` light / `0.5` dark over `.24s`.
- Share → native share sheet (below).
- Tap **New Demo** → Take screen in `ready` mode (modal, from bottom).

**Empty state** (first launch, no takes): list area centres a 252pt-wide block, offset `−20pt` vertically — title "Capture your first demo" (22/700/−0.4) + body "Hit 'New Demo' to record an idea, shape it with Enhance, and share it anywhere." (15/1.5, `text2`, `text-wrap: balance`). The New Demo capsule stays in place. No illustration.

### 2. Take (record + playback) — `TakeScreen`
**Purpose:** the one view where a take is captured, reviewed, renamed, adjusted and shared.

**This is deliberately a single view with four states.** Everything below the header is constant; only the **header** and the **right-hand transport button** change, so nothing jumps as state changes.

**Shared layout (top → bottom)**
1. **Header** — padding `56 20 0`, row height `26`, left item / right item.
2. **Content block**, top-anchored, padding `90 24 0`, centred:
   - **Title** — 24/680/−0.4. In `playback` it's an inline editable text field (tap to rename, centred, transparent, no border).
   - **Meta** — "Today · 3:14 PM", 14, `text2`, 2pt below.
   - **Waveform** — height `120`, full width, 30pt below the meta.
   - **Timer** — 56/300/−1, tabular, 30pt below the waveform. Format `MM:SS` in `text`, `.CS` hundredths in `text3`. Greyed to `text4` before capture starts.
   - **Coaching line** — reserved 24pt slot, 14pt below the timer, record flow only; fades in/out `.25s`.
3. **Transport tray** — bottom padding `42`, column, `20pt` gap (26 in playback):
   - **Enhance dial** (see below)
   - **Two transport buttons**, `66pt` each, `44pt` gap, with a 13/500 label `8pt` under each. **Play is always on the left** (dimmed to `opacity .35` and disabled until a take exists); only the right button changes.

**States**

| State | Header left | Header right | Left button | Right button |
|---|---|---|---|---|
| `ready` | Cancel | — | Play (disabled) | ◉ **Record** — ring `4pt recBorder`, accent disc at 78% |
| `recording` | Cancel | — | Play (disabled) | ▪ **Stop** — same ring, accent rounded square (40% size, radius 9) |
| `stopped` | Cancel | Share ⃒ Done | ▶ **Play** | ◉ **Resume** — ring, accent disc at 40% |
| `playback` | ‹ Demos | Share ⃒ Done | ▶ **Play** / ⏸ Pause | ◉ Resume |

Play button: `66pt` circle, bg `accent @ 0.14` (light) / `0.20` (dark), glyph accent at ~42% of the button. Header right in `stopped`/`playback` is a share glyph (22pt) + "Done" (17/590), `18pt` gap.

**Waveform**
- **While capturing:** live rolling meter — 48 symmetric bars, newest arriving at the right edge, scrolling left at ~`95ms` per bar.
- **Before capture (`ready`):** flat resting line (all bars at 0.05). It does **not** react to input in the MVP — nothing is being captured yet.
- **Review / playback:** **centre-locked playhead** (final design). The take scrolls horizontally under a **fixed orange marker** at the horizontal centre: `4pt` wide line, accent, no dot, just clearing the tops of the bars. Bar geometry `5pt` wide, `3pt` gap (`8pt` step). Played side (left) is warm amber; unplayed (right) is `barOff`. The amber **fades over the last 6 bars** before the marker down to `0.45` alpha so the marker separates cleanly. Hard edges — the take runs full width, no mask.
- **Scrubbing:** drag the waveform (not the marker) 1:1 with bar geometry — drag left advances. Time label tracks the marker.
- **Enhance reaction:** bars warm along the OKLCH ramp and gain a soft warm bloom — a radial `rgba(255,159,10,0.09→0.24)` aura, `58%→124%` width and `118%→208%` height of the waveform box, `blur(6→15px)`, growing with the value. Deliberately *not* a literal reverb tail.
- On device this should be **one drawing surface** (SwiftUI `Canvas`/Metal), not N views.

**Enhance dial** (the single audio control, shared by record and playback)
- Photos-style: a **tick scale scrolls under a fixed centre marker**. Track `300 × 40pt`, `41` ticks at `14pt` pitch (0…1 in 40 steps); every 5th tick is major (`2 × 20pt`, `tickMaj`), others minor (`2 × 11pt`, `tickMin`). Track masked at both ends: `linear-gradient(90deg, transparent, #000 16%, #000 84%, transparent)`.
- Marker: accent line `3 × 30pt` at centre with `0 0 6px rgba(255,159,10,0.55)` glow, plus an `11pt` accent dot on top.
- Label above (7pt gap): wand glyph 18pt + **"Enhance · {tone}"** (14/640, `ACCENT_DEEP` light / `ACCENT` dark), 12pt above the track.
- **Tone names by value:** `<0.06` Dry · `<0.32` Room · `<0.60` Warm · `<0.85` Studio · else Hall.
- Gesture: horizontal drag, `dv = (startX − x) / stripWidth` — drag left raises the value. Clamp 0…1. Default value `0.5`.

**Count-in** — tapping Record starts a **3-beat count-in with soft ticks, rendered inside the record button**: the accent disc is replaced by the numeral (28/560, accent, tabular), animating `scale(1.25) → 1` with a fade over `1s` per beat. The timer starts at `00:00` on the first captured beat. Tapping the button (or Cancel) during the count-in aborts back to `ready`. This is the iOS screen-recording pattern — the user's eye is already on the thing they just tapped.

**Cancel** clears the take and returns to the start (list). **Done** saves. **Resume** continues recording onto the existing take (Play dims, right button becomes Stop).

**Naming** — takes default to `New Demo {n}` with an auto-incrementing counter. Rename by tapping the title on playback.

**One reserved line, for every notice.** A single reserved slot above the transport carries every in-place message — centred line, optional second line, optional tinted capsule. No cards, no empty states, no second channel. It keeps the screen identical in every state: nothing above it moves, nothing below it jumps.

The slot is shared with the transient coaching line, so it resolves by **precedence, not a second channel** — **mic state → playback failure → capacity → coaching**, highest one wins. In practice they barely compete: coaching only speaks while capture is running, and every mic notice means capture can't run. Two behavioural differences hold:

- A **notice** appears instantly and persists; **coaching** cross-fades (`.25s`).
- Only a **notice** may carry an action.

| Message | Channel | Form |
|---|---|---|
| Mic denied / restricted / unavailable | Notice | Reserved line + Open Settings capsule (`#16a`) |
| Playback failure — file missing or damaged | Notice | Reserved line + **Try Again** (`#16d`) |
| Low space, non-default input | Notice | Reserved line, no capsule |
| Input too quiet / clipping | Coaching | Reserved line, three-case enum, cross-fades |
| Recording failure — write error, storage full, revoked mid-take | Alert | System alert (`#15e`) |
| Interruption — call, Siri, another app | Neither | State change only: header reads **Paused**, right button becomes Resume |
| Playback reached the end | Neither | Marker parks, button returns to Play |

In build: **one slot, one resolver** — the screen picks the highest-precedence message and renders it. `InlineNotice` (`#13a`) *is* that slot, not a new component.

**One transport rule:** a transport button is dim (`opacity .35` for Play/Resume, `.45` for the blocked Record disc) whenever it cannot act — "no take yet" and "no microphone" get the same treatment. Never enabled-and-inert.

#### Microphone permission & input availability
The record flow has four unavailable states. **Only the record flow is affected** — the list and playback stay fully usable; nothing already captured is gated behind a permission.

**Disabled-Record treatment** (shared by all four): the transport keeps both buttons and both labels — the ring stays at `4pt recBorder`, the accent disc is replaced by a `text3` grey disc at the same 78% size, the whole button sits at `opacity 0.45` (`.2s` transition), and the "Record" label drops to `text4`. The Enhance dial dims to `opacity 0.4` and stops accepting input. The reason is delivered in the **reserved line** described above — one line, then **Open Settings** as a tinted capsule where a route out exists — and never red: this is a state, not an error.

| Case | `perm` | Line | Route out |
|---|---|---|---|
| Denied | `denied` | **Microphone access is off** | Open Settings → `UIApplication.openSettingsURLString` |
| Restricted (Screen Time / MDM) | `restricted` | **Microphone access is restricted** / "Managed in Screen Time" | none — the switch won't move for this user |
| No input device | `nodevice` | **No microphone available** / "Connect a microphone to record" | none — Settings can't fix hardware |
| Revoked between launches | `revoked` + alert | same as denied, with an alert on entry | Not Now / Open Settings |

**Alerts** (`SystemAlert` in the prototype → SwiftUI `.alert()`; 270pt, radius 14, material, title 17/640, message 13/1.38, two side-by-side buttons split by a 0.5pt hairline, accent text, no destructive styling). Only used when capture **stopped or never started against the user's expectation**:
- *Revoked between launches* — "Microphone Access Is Off" / "Demo Memos can't record without the microphone. You can turn access back on in Settings." · Not Now / **Open Settings**
- *Revoked mid-take* — "Recording Stopped" / names the length saved and the demo it went into, then Settings. Lands on `stopped` with the partial take.
- *Storage full mid-take* — "Storage Full" / same sentence shape. · OK / **Manage Storage**

Anything the user themselves just switched off resolves in place, with no alert.

### 3. Share sheet (native)
Use `ShareLink` / `UIActivityViewController` — do not build this. The prototype's version shows the intended payload: a **header row** (46pt accent-tinted rounded square with wand glyph, name 16/600, "Audio · 0:37" 13 `text2`, close button), the standard app row (AirDrop, Messages, Mail, Notes, Copy), and three actions: **Copy Link**, **Save to Files**, **Export Audio…**. Sharing is a first-class feature: reachable from the list (swipe) and from the take screen header.

**Sharing needs a render** (`#17`, FINAL). Enhance is a live setting, so a shareable file has to be rendered before it can leave the app. The sheet opens on the tap and the file is **promised, not waited for** — raise it immediately and hand over a `UIActivityItemProvider`, so choosing a destination and rendering happen in parallel. Progress sits on the sheet's header row (subtitle counts, 3px bar beneath it); nothing dims, nothing is disabled, and there is no second modal. An already-rendered demo opens the sheet instantly with no progress at all, and a render under ~500ms shows nothing unless that deadline passes. See `#17e` for the rule per situation.

### 4. Onboarding — `OnboardFeatures`
**Shown once**, gated on a persisted `hasOnboarded` flag; never shown again. iOS "What's New" pattern.

- Vertically centred, padding `56 34 28`.
- Title: "Welcome to" / **"Demo Memos"** on the second line in accent — 32/720/−0.6, line-height 1.12, centred, `44pt` below.
- Three rows, `30pt` gap. Each: `34pt` fixed icon column (accent glyph, 24–26pt) + `18pt` gap + title (16.5/640/−0.2) over body (14.5/1.42, `text2`, `text-wrap: pretty`).
  1. **Voice Memos, but for demos** — "Open it and go — the same one-tap simplicity you know, made for catching musical ideas."
  2. **One Enhance dial** — "A single slider warms and widens your whole sound. No menus, no mixing."
  3. **Share anywhere** — "Send takes straight to Messages, Mail or Files with the native share sheet."
- Footer button **Continue** — full width, padding `16 0`, radius `15`, accent bg, white 17/640, shadow `0 6px 18px rgba(255,159,10,0.34)`. Bottom padding `44`.

---

## Interactions & motion summary
| Thing | Spec |
|---|---|
| Sheet present (share / info) | `translateY(115%) → 0`, `.34s cubic-bezier(.32,.72,0,1)`; scrim `.26s` to `rgba(0,0,0,0.28)` / `0.5` dark |
| Action sheet | same curve, `.32s` |
| Swipe row | `transform .2s`; open at `−152pt`, threshold `−64pt` |
| Count-in beat | `1s` per beat, `scale(1.25)→1` + fade |
| Live waveform scroll | one bar per `~95ms` |
| Playhead advance | `40ms` tick |
| Button enable/disable | `opacity .2s` |
| Enhance bloom | `all .2s ease` |
| Bar colour | `background .1s, box-shadow .12s` |
| Reduced motion | Honour it — freeze the waveform animation and count-in scaling (`prefers-reduced-motion` in the prototype → `UIAccessibility.isReduceMotionEnabled`) |

## State model
```
App:      hasOnboarded: Bool (persisted)
          demos: [Demo]                  // Demo { id, name, createdAt, duration, enhance }
Take:     mode: .ready | .recording | .stopped | .playback
          enhance: Double = 0.5          // persisted per take
          elapsed: TimeInterval
          progress: Double 0…1           // playhead
          isPlaying: Bool
          name: String                   // default "New Demo {n}"
          countIn: Int?                  // 3…1 during count-in
Sheets:   shareTarget: Demo?  ·  deleteTarget: Demo?
```
Transitions: `ready →(record, after count-in)→ recording →(stop)→ stopped →(resume)→ recording`. `cancel` from any record-flow state → discard, dismiss. `playback` is a separate entry point from the list and never captures.

Audio concerns the design assumes: mic permission prompt on first record, `AVAudioSession` record category, Enhance applied as a live effect *and* re-applied non-destructively on playback (the same value rides along, so a take's Enhance can be changed after the fact), export/share of the processed file.

## Assets
- `app-icon/AppIcon-Default-1024.png` — required "Any Appearance" master (warm off-white body, charcoal ring, orange disc)
- `app-icon/AppIcon-Dark-1024.png` — Dark appearance (charcoal body, white ring, glowing disc)
- `app-icon/AppIcon-Tinted-1024.png` — greyscale/luminance master; iOS applies the user's home-screen tint

All three are flat **1024×1024 PNG, no alpha, square corners** — iOS 18+ applies the squircle mask and generates every smaller size. Drop them into the asset catalog's Any / Dark / Tinted slots. Verified legible down to 40pt.

All other iconography in the prototype is hand-drawn SVG standing in for **SF Symbols** — use the real symbols: `mic.fill`, `waveform`, `play.fill`, `pause.fill`, `stop.fill`, `square.and.arrow.up`, `trash`, `wand.and.stars` (Enhance), `headphones`, `cable.connector`, `chevron.left`, `info.circle`.

## Future / parked
**Live monitoring** — hearing yourself through headphones while recording — is out of MVP scope. The MVP goes straight from New Demo → set Enhance → record: no monitor state, no monitoring indicator, no "dial in the sound first" step. Two explorations exist in the design doc if it ships later:
- **Wired-only state**: the header pill dims to "Monitoring off" and the hint line reads "Plug in wired headphones to hear yourself". Nothing blocked, nothing added — both revert when wired headphones connect. (Bluetooth latency makes monitoring unusable.)
- **Info sheet**: the dimmed pill becomes tappable (gains an ⓘ) and raises a medium-detent explainer — grabber, headphones symbol, one line of what monitoring does, a wired-only callout, one filled **OK**.

## Files in this bundle
| File | What it is |
|---|---|
| `Demo Memo.dc.html` | The full design doc — all screens, states and rationale, grouped A–D. Open in a browser. This is the primary reference. |
| `demo-scene.jsx` | Every screen component: `TakeScreen`, `DemosListScreen`, `OnboardFeatures`, `WaveformStudy`, plus `EnhanceSlider`, `ScrubWaveform`, `ShareSheet`, `ConfirmSheet`, `SwipeRow`. All tokens live at the top (`ACCENT`, `TH()`, `warmColor()`). |
| `ios-frame.jsx` | The 402×874 device bezel/status bar wrapper. Prototype scaffolding only — ignore for implementation. |
| `support.js` | Prototype runtime. Ignore. |
| `app-icon/*.png` | Ship these. |

To read a specific screen in the doc, the anchors are: `#1a` Demos · `#1b` Record · `#1c` Playback · `#1d` state matrix · `#2a–2c` dark mode · `#3a` resume transport · `#12a` final scrub · `#8a` count-in · `#6a/6b` waveform study · `#5a` onboarding · `#4a` empty state · `#10c` app icon · `#15a`–`#15g` microphone permission states · `#16a`–`#16f` the reserved notice line & precedence · `#17b`–`#17e` sharing a rendered file · `#13a` component inventory · `#14` the full state register.
