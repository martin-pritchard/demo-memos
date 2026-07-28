# Post-processing: the chain, the order, the units

Read with `SKILL.md`. Verify parameter identifiers and ranges in the SDK headers
before writing them — a wrong AudioToolbox constant is a silent no-op, not a
compile error.

## The chain, in order

Full order for a recorded acoustic or vocal demo. **You will not need all of
it.** Pick the boxes that solve the actual complaint and keep them in this
relative order.

| # | Stage | Purpose | Skip when |
|---|-------|---------|-----------|
| 1 | High-pass filter | Remove handling noise, rumble, proximity mud | Almost never skip |
| 2 | Gate / noise reduction | Lower the room floor | Floor is already low, or artefacts show |
| 3 | Corrective EQ (cuts) | Remove mud, boxiness, harshness | Nothing specific is wrong |
| 4 | Compression | Even out the performance | Performance is already even |
| 5 | Saturation / tape warmth | Harmonic richness, glue, perceived loudness | Source is already coloured |
| 6 | Musical EQ (boosts) | Add presence and air | Tone is right |
| 7 | Reverb — **parallel** | Space, depth | Recording already has usable room |
| 8 | Limiter + output gain | Catch peaks, set final level | Never skip if anything above adds gain |

### Why this order

- **1 before 4** — a compressor with rumble in its detector pumps on footsteps
  and hand movement. Filter first and the compressor hears only the music.
- **2 before 4** — compression raises the noise floor along with everything else.
  Reduce noise while it is still quiet.
- **3 before 4** — a resonant peak triggers the compressor early, so the
  compressor duckes the whole signal every time that one frequency sounds. Cut
  it first and gain reduction tracks the performance instead.
- **4 before 5** — saturation is level-dependent by nature, so it wants a
  consistent input to behave predictably.
- **6 after 5** — saturation generates its own harmonics, so shape the tone once
  the harmonics exist. Boosting before saturation just distorts the boost.
- **7 after 6, in parallel** — reverb of an already-shaped signal sounds
  intentional; reverb of a raw signal that you then EQ smears the whole thing.
  Parallel keeps the dry signal fully present underneath.
- **8 last** — a limiter's job is guaranteeing the ceiling. Anything after it can
  break that guarantee, and reverb definitely adds peaks.

### The one deviation worth knowing

**Saturation before compression** is a legitimate choice, not a mistake: gentle
soft-clipping rounds the sharpest transients so the compressor works less hard.
Use it when the source has spiky peaks (fingerpicking, plosives, a slapped
string). Say you are doing it and why. Everything else in the order stays put.

## What Apple gives you

`AVAudioEngine` plus `AVAudioUnit*` covers most of the chain with no DSP written
by hand. Attach nodes, connect them in order, done.

| Stage | Use |
|---|---|
| High-pass, EQ, shelves | `AVAudioUnitEQ(numberOfBands:)` — each band has `filterType`, `frequency`, `bandwidth`, `gain`, `bypass` |
| Reverb | `AVAudioUnitReverb` — `loadFactoryPreset(_:)` + `wetDryMix` (0–100) |
| Delay | `AVAudioUnitDelay` |
| Distortion | `AVAudioUnitDistortion` — presets are mostly extreme; see warmth below |
| Time / pitch | `AVAudioUnitTimePitch`, `AVAudioUnitVarispeed` |
| **Compression** | **No Swift wrapper — see below** |
| **Limiting** | **No Swift wrapper — see below** |

### EQ

One `AVAudioUnitEQ` holds many bands, so the whole of stages 1, 3 and 6 can be a
single node — though keeping corrective and musical EQ as separate nodes reads
more clearly when both are active. `AVAudioUnitEQFilterType` includes
`.highPass`, `.lowPass`, `.bandPass`, `.bandStop`, `.parametric`, `.lowShelf`,
`.highShelf`, and resonant variants. `.parametric` is the one that uses
`bandwidth`; shelves and pass filters mostly ignore it.

### Compression and limiting: the gap

**There is no `AVAudioUnitCompressor`.** Apple ships the audio units but not
Swift wrappers. Reach them through `AVAudioUnitEffect` with an
`AudioComponentDescription`:

- `kAudioUnitSubType_DynamicsProcessor` — compressor/expander/gate. Parameters
  are `kDynamicsProcessorParam_*` (threshold, headroom, expansion ratio, attack
  time, release time, master gain). **Grep the AudioToolbox headers for the
  exact identifiers and ranges — do not guess them.** Note its parameter model
  is not the textbook threshold/ratio pair, which is the usual source of "the
  compressor does nothing" bugs.
- `kAudioUnitSubType_PeakLimiter` — the stage-8 limiter.

Preferred instantiation is `AVAudioUnit.instantiate(with:options:completionHandler:)`,
which returns the right `AVAudioUnit` subclass for the component. Set parameters
via the returned unit's `auAudioUnit.parameterTree` (or the older `AudioUnit`
parameter API); the wrapper exposes no typed properties.

### Tape warmth

No Apple unit does this well. `AVAudioUnitDistortion`'s presets are voiced for
effect, not for subtlety, though a low `wetDryMix` on a gentle preset is worth
auditioning before building anything.

Warmth is really three things, and you rarely need all three:

1. **Soft saturation** — odd/even harmonics from a gentle non-linearity. A
   `tanh(drive * x) / tanh(drive)` waveshaper is a handful of lines and sounds
   convincingly analogue. This is the one case where hand-written DSP is the
   *simple* answer, in an `AUAudioUnit` subclass or a manual-render pass.
2. **A gentle high-shelf cut** above ~10 kHz, plus a small low-shelf lift around
   100–200 Hz. Pure `AVAudioUnitEQ`, no DSP at all.
3. **Wow and flutter** — slow pitch modulation. Atmospheric, usually
   unwelcome on a song sketch you will transcribe later. Skip unless asked.

Doing 2 alone gets most of the perceived warmth for zero risk. Try that first
and only add 1 if it is genuinely not enough.

## Starting parameters

Sane defaults for phone-captured voice or acoustic guitar. Starting points to
tune by ear, not settings to ship blind.

**High-pass** — 70–80 Hz for voice, 60–70 Hz for acoustic guitar (its low E is
~82 Hz, so do not cut into it), 24 dB/oct.

**Gate / expander** — threshold just above the room floor, gentle ratio. Prefer
a downward expander to a hard gate: it lowers the floor instead of chopping it,
which avoids breathing on reverb tails and word ends.

**Corrective EQ** — the usual phone-recording culprits: 200–400 Hz boxiness
(cut 2–4 dB, wide), 400–800 Hz mud, 2–5 kHz harshness (narrow, only if it is
actually there). Cuts are wide and small; only fixes are narrow.

**Compression** — ratio 2:1 to 3:1, attack 10–30 ms (fast enough to control,
slow enough to let transients through so it does not sound limp), release
100–200 ms or roughly to the tempo, 3–6 dB of gain reduction on peaks. More
than 6 dB on a demo is a level problem to fix at capture instead.

**Saturation** — the point where it is audible only on bypass. If you can hear
it as distortion, it is too much.

**Musical EQ** — high-shelf +1 to +3 dB above 6–8 kHz for air; a narrow
presence lift around 3 kHz if the vocal needs to sit forward.

**Reverb** — `.smallRoom` or `.mediumRoom` for intimacy, `.plate` for vocals,
`.mediumHall` when the take should feel spacious. `wetDryMix` 10–25 for a demo;
above ~35 the words start to blur. Cathedral is a special effect, not a default.

**Limiter** — ceiling −1.0 to −0.3 dBFS (leave room for encoder overshoot,
which is exactly why 0.0 is wrong), just catching the peaks rather than
squashing.

## Wiring it into an engine

### Real-time (playback) — what Enhance should use

Enhance is a playback-time change with no migration, so this is the shape:

`AVAudioPlayerNode` → effects in chain order → `mainMixerNode` → output.

Parallel reverb means a second connection: dry from the last pre-reverb node to
the mixer, and a branch through the reverb node also into the mixer, balanced by
mixer input volumes — or, more simply, `AVAudioUnitReverb`'s own `wetDryMix`,
which is internally parallel already and is the right answer here. Use the
built-in mix unless the design needs independent wet EQ.

Parameters are safe to change while running, which is what makes a live dial
possible. Rebuilding the graph on every dial movement is not — attach once,
then set parameters. For true bypass at 0, use each unit's `bypass` flag rather
than detaching nodes mid-playback.

### Offline (export) — only if a task asks for a processed file

`enableManualRenderingMode(.offline, format:maximumFrameCount:)`, pull buffers
with `renderOffline(_:to:)`, write with `AVAudioFile`. Runs far faster than
real time. Read the source with `AVAudioFile` or `AVAssetReader`, process to
PCM, and encode once at the end.

Do not add this to satisfy Enhance. Enhance is a playback change.

### Engine hygiene

- `prepare()` before `start()`; both can throw.
- The engine's node graph must be connected before start, and formats must
  agree — a nil-format connection inherits, which is usually what you want.
- An interruption stops the engine. Restart it and re-activate the session; do
  not assume nodes survived.
- One engine, owned in one place, matching how `AudioSession` owns the category.
- Keep it all behind the existing seams — the engine belongs inside an
  `AudioPlayer` implementation (or a new protocol *with* its fake), not exposed
  to a view. `Audio/` imports no SwiftUI.

## Mapping one dial onto the chain

`Memo.enhance` is a single `0...1`. Curate a path through the parameter space
rather than ramping everything linearly:

- Some stages **arrive late** — reverb might stay at zero until ~0.3, so low
  settings are pure tone-shaping.
- Some stages **arrive early and saturate** — the high-pass can reach full value
  by ~0.2 and stay there, since it is corrective and not a matter of taste.
- Some move **monotonically but non-linearly** — compression ratio and wet mix
  want an ease-out curve so the top of the dial does not run away.
- **Output gain compensates** so 0 and 1 are level-matched. Otherwise the dial
  is a loudness control wearing a costume, and every user will prefer 1.

Keep this mapping a **pure function** of the dial value — one testable place
that turns `0...1` into a parameter set. Unit-test its shape: bypass at 0,
monotonic, matched level at the ends, nothing out of an AU's legal range. That
test needs no engine and no audio, which is exactly why the mapping should not
live inside the graph code.
