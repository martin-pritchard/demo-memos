# Decisions

A log of choices whose *why* isn't obvious from the code — kept so a later
change doesn't quietly undo the reasoning behind an earlier one.

## Decided

### The WAV harness scales 24-bit PCM symmetrically, ±(2²³ − 1) (#19)

The pure-Swift codec in the `Core` test harness encodes and decodes 24-bit PCM
against `8_388_607` (2²³ − 1), not the more common `8_388_608` (2²³). Symmetric
scaling makes `+1.0` a representable code (the top one) so a full-scale sample
round-trips to *exactly* `1.0` — `x / x == 1.0` in IEEE 754. The `impulse`
fixture asserts `samples[0] == 1.0` after a real file round-trip, which a ±2²³
mapping (where `+1.0` is unrepresentable and reads back a hair low) would fail.

The cost is one code of asymmetry at the extreme negative (`−8_388_608` is
clamped to `−8_388_607` on encode); at 24-bit that is ~−140 dBFS, far below any
tolerance the harness asserts, and it never affects a real recording, whose
samples never sit on the rail. Any future encoder or DSP that shares buffers
with this codec must use the same convention.

### The harness codec reads only 24-bit linear PCM (#19)

`WAVFile` accepts `WAVE_FORMAT_PCM` and `WAVE_FORMAT_EXTENSIBLE`, 24-bit only,
and throws `WAVError.unsupportedFormat` for anything else (8-bit, 16-bit,
compressed). That covers every committed fixture and this project's capture
format (48 kHz mono 24-bit, #18); 16-bit support would be untested code added
"for later", so it is deliberately absent.

### The Enhance voicing targets intimate analog/tape warmth (#21)

Enhance is tuned toward a specific production aesthetic, anchored to reference
records: Bill Withers *Live at Carnegie Hall* ("Grandma's Hands"), Neil Young
*Live at Massey Hall 1971*, Elliott Smith *Roman Candle* ("Condor Ave"), Nick
Drake *Pink Moon*, and Dave Rawlings "The Bells of Harlem". Their common thread
— woody low-mid body, gentle tape/harmonic saturation, softened highs, dry and
close, preserved dynamics — is the design target, not a generic "make it
better".

This is written down because the DSP shape is downstream of it, and each
consequence is a thing a later change could quietly get wrong:

- **The chain is head bump + tanh saturation + high-frequency softening.** The
  third stage exists *because* these records have a rolled-off top; it is not
  incidental. Dropping it to "just saturation + EQ" would miss the target.
- **Dry, not spacious.** None of the references are reverby, so reverb is
  deferred (#22) and, when it lands, stays a restrained touch — never a default
  wash.
- **Character, not volume.** The references are quiet and dynamic. This is the
  *reason* the ±1 dB loudness guardrail exists: the dial must not get louder as
  it gets warmer, or "louder" gets mistaken for "better".
- **No modulation of any kind.** Wow/flutter is specifically unwanted, which is
  why the processor is two static stages plus static EQ — deterministic, and
  guardrail-testable because of it.
- **"Characterful at 1" means these records at their grittiest** (the *Roman
  Candle* cassette end), not a heavier modern tape-emulation. The top of the
  dial is the most flattering setting, not the most extreme. Final voicing is
  found by ear on device (#24); the numbers only start the search.

### The leveler's make-up is pinned to a pivot, not to full scale (#32)

The Enhance leveler derives its make-up gain from threshold and ratio rather
than exposing it as a voiced parameter:

    levelerMakeupGainDB = (levelerPivotDBFS - levelerThresholdDB) * (1 - 1 / levelerRatio)

with the pivot at −12 dBFS, roughly where a well-tracked take sits. A signal at
the pivot therefore passes through the leveler unchanged: louder passages come
down, quieter detail comes up, and the level the user tracked at does not move.

The obvious alternative — auto make-up referenced to full scale, which is what
most compressors ship — would lift a −12 dBFS take by about 6 dB. That is the
"character, not volume" failure #21 warns about, arriving disguised as a
feature: every user prefers the louder setting and calls it better. Deriving the
make-up instead of voicing it means no by-ear tuning pass can reintroduce that,
the same way the bounded `ceiling` makes no-clipping structural rather than
something the curve must avoid. Any future change that makes make-up an
independent parameter gives that guarantee up.

### A level-dependent gain rescales a pre-existing DC offset (#32)

`WarmthProcessorTests.noDCIntroduced` used to assert `dc(out) ≈ dc(in)` for both
the sine and the noise fixture. That comparison was only ever valid because
every stage in the chain had unity gain at DC. The leveler does not: it applies
a gain that depends on level, and a DC offset is a low-level component, so it
rides the (larger) gain the leveler gives quiet content — measured ~1.22× at
full warmth, bounded above by the chain's small-signal gain.

Nothing is introducing DC. The noise fixture carries ~−0.0012 of its own from
PRNG sampling noise at that length, and the sine fixture — which is DC-free —
still comes out DC-free at every dial position, which is the case that would
catch a real defect. So the noise assertion now bounds the output offset by the
input's own offset times the chain's small-signal gain, and the sine assertion
stays exact.

The rejected alternative was making `Fixtures.whiteNoise` exactly zero-mean.
That would make the tight assertion valid again for every stage, but it changes
a fixture shared by other suites and forces the committed `noise-20` WAV to be
regenerated — a wider blast radius than this issue justifies. It remains the
better fix if the DC guardrail ever needs to be tightened again.

### The leveler detects peaks instantly and puts the ballistics on the gain (#32)

`Leveler` smooths the *gain*, not the envelope: the detector jumps straight to
`abs(x)` on a rise and only the release time slows its fall, while the attack and
release times shape the gain that is derived from it.

The obvious arrangement — one asymmetric one-pole on the envelope, gain read
straight off it — was tried first and quietly breaks the pivot guarantee above. A
one-pole envelope with a 20 ms attack cannot track a waveform's peak: on a sine it
settles about 1 dB below it, and by an amount that depends on the material's crest
factor. Since the make-up is derived in the *level* domain, that gap lands
straight in the output — measured +0.5 dB at full warmth, scaling with
`(1 − 1/ratio)`, so worst exactly where the ±1 dB loudness guardrail is tightest.
It consumed 93% of that budget while every test stayed green, because the test
covering the derivation restated the formula instead of measuring a signal.

Detecting the peak exactly and smoothing the gain is also the textbook
feed-forward topology, and it does not cost the transient behaviour: it is the
*gain* that takes the attack time to come down, so strums still pass through
un-squashed. `LevelerPivotTests.pivotToneIsUnchangedByTheLeveler` now measures a
pivot-level tone through the kernel and asserts the level change is *identical*
across dial positions — the ratio varies from ~1.4 to 2.0 there, so a derivation
that drifts with ratio fails it. It cannot assert the change is zero: the bounded
`ceiling` is still in the chain and costs a constant ~0.14 dB.

### The take timer has no hour form, and rounds rather than truncates (#45)

`TimerParts` formats an elapsed time as `MM:SS` plus hundredths, and minutes never
roll into hours: an hour reads `60:00`. `screen-states.md` lists a maximum-take
policy as an open question; this settles only the *display*, not the policy. A
demo is a song idea, and a field wide enough for `1:00:00` would be sized for a
case that means something has already gone wrong. Past `99:59` the field does
widen to three digits — accepted, because by then the readout is evidence of a
runaway recording rather than a layout to protect.

The centiseconds are **rounded** to the nearest, where the prototype's
`demo-scene.jsx` truncates with `Math.floor`. Truncation is the more common
stopwatch behaviour, but an elapsed time arrives as a binary `TimeInterval`, and
truncating turns ordinary floating-point error into a visibly wrong final digit —
`0.9999997` renders as `00:00.99`. The cost is that the readout can show up to
5 ms that has not elapsed, so the last frame of a take can read one centisecond
above the file's true length. That only matters once a duration formatter for the
Demos list exists and the two have to agree; whichever lands second should match
this one rather than re-deciding.

### The Enhance dial travels one track width, not one scale width (#46)

`DialGesture` resolves a drag as `-translation / trackWidth` — the *visible*
300pt track — so a 150pt drag from the default 0.5 covers the rest of the range.
`docs/design/README.md` § Enhance dial writes the same formula over `stripWidth`,
and the prototype's `EnhanceSlider` divides by `STRIP` (`40 × 14pt = 560`),
which would make the dial ~1.9× less sensitive: a full sweep of the track would
move the value about 0.54 rather than 1.0.

#46 is the later document and pins the trackWidth reading with worked numbers in
its acceptance criteria, so it wins — the same way #44 settled the tone
thresholds against `demo-scene.jsx`. Recorded because the two are one argument
apart and the difference is invisible in a screenshot: it is a *feel* decision,
and the next person to drag the dial on a device is better placed to judge it
than either document. Changing it means passing `Self.stripWidth` at the one
call site in `EnhanceDial.track`; the pure function and its tests do not move.

The related choice is what happens past an end. The scale stops dead — no
rubber-band, per the issue — but a drag that overshoots and comes back moves the
instant the finger reverses, rather than paying the overshoot back first. That is
scroll-view behaviour, and it is the view's, not the reducer's: `DialGesture`
stays pure and the view re-anchors on the clamped value for the rest of the
gesture.
