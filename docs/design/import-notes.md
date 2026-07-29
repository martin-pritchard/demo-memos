# Import notes

How this folder got here, and the one thing in it that is not a byte-for-byte
copy of what the designer exported. `README.md` is the designer's handoff doc,
imported verbatim — these notes are kept separate so it stays pristine.

## Source

Claude Design project **Demo Memo App Design**
(`50eeb9e6-61b6-45ac-ad1e-53f0e01d36de`), the `design_handoff_demo_memos/`
bundle. Imported 2026-07-28 via the `claude_design` MCP.

### Re-import 2026-07-29 (second pass) — turn 16 reversed, and a source change

**Read this before trusting `README.md` as verbatim.**

Turn 16 was rewritten the same day and marked **FINAL**, reversing the design
imported in the first pass below: the notice **row** and **content block** forms
are gone, and *one reserved slot above the transport carries every notice*,
shared with the coaching line and resolved by precedence (mic state → playback
failure → capacity → coaching). Turn 17 (sharing a rendered file) also landed.

**Source changed this pass.** The `design_handoff_demo_memos/` bundle had not
been re-exported — it still carried the superseded three-form turn 16 and no
turn 17 at all. So `demo-memo.dc.html` and `demo-scene.jsx` were taken from the
project **root** (`Demo Memo.dc.html`, `demo-scene.jsx`), which is the live doc
and the one marked FINAL. `support.js` and `ios-frame.jsx` were diffed against
root and are byte-identical, so they still match both sources.

**`README.md` is no longer purely verbatim.** It exists *only* in the stale
handoff folder — there is no root copy to re-import — so three sections were
reconciled by hand against the FINAL doc rather than replaced:

- the message-channel block, rewritten from "two channels, never one" to the
  one reserved line plus the precedence rule
- the disabled-Record paragraph, which pointed at the deleted content-block form
- a new paragraph under **Share sheet** carrying turn 17, which the handoff
  README predates entirely

Everything else is still the designer's own text. The fix is a re-export of
`design_handoff_demo_memos/`, after which `README.md` can be replaced wholesale
and this caveat deleted.

### Re-import 2026-07-29 (first pass) — turns 15 & 16

The designer added two turns answering the states #53 was blocked on:
**`#15` microphone permission** (the four unavailable states, their copy, the
shared disabled-Record treatment and the mid-take alerts) and **`#16` where a
notice lives** (three notice forms, the routing rule for which notice uses
which, and the one-rule answer on dimmed-vs-inert transport buttons).

Three files changed and were re-imported; the other two were checked and left
alone:

| File | This round |
|---|---|
| `demo-memo.dc.html` | Replaced. 38 KB → 97 KB — turns 15, 16 and the state register `#14`, plus the component inventory `#13`. |
| `demo-scene.jsx` | Replaced. +120 lines, additive: a `micOff` glyph, `perm` / `notice` / `noticeAt` / `alert` props on `TakeScreen`, the three notice forms, the blocked-Record button, and a new `SystemAlert` component. Six lines changed, all to thread a `dim` flag through `labeled()` and to wrap the Enhance dial in the disabled treatment. |
| `README.md` | **Not replaced — edited in place.** Every change was additive and localised, so the new "Two message channels", "One transport rule" and "Microphone permission & input availability" sections were inserted verbatim after **Naming**, and the anchors line gained `#15a`–`#15g` and `#16a`–`#16f`. The rest of the file is untouched, so this stays the designer's text. |
| `ios-frame.jsx` | Unchanged. Verified head and tail against the remote — identical, and it is prototype scaffolding the handoff says to ignore. |
| `support.js` | Unchanged. Generated prototype runtime; not re-fetched. |

`screen-states.md` was updated to match — it is this repo's analysis, not the
designer's, so it tracks the bundle rather than being replaced by it.

## Contents

| File | Notes |
|---|---|
| `README.md` | The handoff doc — tokens, screens, states, motion. Verbatim. |
| `demo-memo.dc.html` | The design doc. **Renamed** from `Demo Memo.dc.html` (the original has a space); nothing references it by name, and the paths it references are unchanged. Open it in a browser. |
| `demo-scene.jsx` | Every screen component + all tokens. Verbatim. |
| `ios-frame.jsx` | Device bezel scaffolding. Prototype only — the handoff says ignore it. Verbatim. |
| `support.js` | Prototype runtime. Ignore. Verbatim. |
| `app-icon/*.png` | The three 1024×1024 masters — see below. |
| `app-icon/icon-export.html` | The CSS source the masters are generated from. Not part of the original bundle; pulled in from the project root as provenance for the re-render below. |
| `screen-states.md` | Not part of the original bundle. Every distinct state each screen can be in, read out of the files above, plus the states the app needs that the designs don't cover and the places the bundle contradicts itself. Written here so a re-import of the bundle doesn't take the analysis with it. |

The `.dc.html` opens and resolves: its `./support.js`, `./ios-frame.jsx`,
`./demo-scene.jsx` and `app-icon/*.png` references all point at files present
here.

## The app icons — two are re-renders

`AppIcon-Tinted-1024.png` transferred intact. **`AppIcon-Default-1024.png` and
`AppIcon-Dark-1024.png` did not** — both are ~1 MB and the design MCP's
`get_file` caps a single read at 256 KiB, so both arrived truncated to exactly
196 608 bytes with no `IEND` chunk.

They were regenerated locally from `icon-export.html` — the same CSS source the
originals were exported from — rendered at 1024×1024 with headless Chrome.

That re-render is trustworthy because the *tinted* master could be checked
against the genuine article that did transfer. Rendering it the same way and
diffing all 1 048 576 pixels:

- every pixel in a solid region is **exactly** equal
- 5 565 pixels (0.53%) differ, and **all** of them lie within 2px of the ring
  or disc boundary — antialiasing on the curved edges, nothing else
- the genuine tinted master is RGBA but fully opaque (every alpha byte is 255),
  consistent with the handoff's "no alpha" requirement

So the geometry, colour and gradients reproduce exactly; only edge antialiasing
differs, and only against a master that iOS is going to downscale anyway.

If you would rather ship the designer's own bytes, export the two masters from
the Claude Design project by hand and overwrite them — the CSS is identical, so
they will look the same.

## Not done

The masters are **not** wired into the asset catalog. The three appearance
slots in `apps/ios/DemoMemos/Assets.xcassets/AppIcon.appiconset/` (Any / Dark /
Tinted) are declared but empty; dropping these files in is a separate change.
