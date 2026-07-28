# Import notes

How this folder got here, and the one thing in it that is not a byte-for-byte
copy of what the designer exported. `README.md` is the designer's handoff doc,
imported verbatim — these notes are kept separate so it stays pristine.

## Source

Claude Design project **Demo Memo App Design**
(`50eeb9e6-61b6-45ac-ad1e-53f0e01d36de`), the `design_handoff_demo_memos/`
bundle. Imported 2026-07-28 via the `claude_design` MCP.

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
