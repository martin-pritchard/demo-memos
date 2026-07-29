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

### The waveform's clipping bar comes from the prototype, not the handoff (#47)

A bar at or above `0.9` gets a red top segment and a red glow while recording.
`docs/design/README.md` documents only the token (`clip / hot warning`
`#FF453A`); the behaviour exists solely in `demo-scene.jsx`, and
`screen-states.md` flags the gap. #47 resolves it in the prototype's favour and
to its numbers: the top `36%` of the bar goes red (the JSX's
`linear-gradient(to top, base 64%, #ff453a 64%)`) with a soft red glow, and it
appears in `.live` only — a take being reviewed has nothing left to warn about.

Recorded because the alternative reading is defensible: the handoff naming only
the token could mean the segment was cut and the colour kept for the "a little
hot — ease back" coaching line, which uses the same red. If that is what was
meant, the change is deleting one branch in `Waveform.drawDistributed` and
`WaveformGeometry.clips` with it; the coaching line is unaffected either way.

### The live meter fixes the bar count, the scrub strip fixes the bar width (#47)

`docs/design/README.md` gives one bar geometry — `5pt` wide, `3pt` gap, `8pt`
step — and one live-meter count: 48 bars. Both cannot hold on a phone: 48 bars
at an 8pt step need `381pt`, and the Take screen's content width is `354pt`
(402 less two 24pt margins). The sentence naming the geometry sits inside the
handoff's *centre-locked playhead* paragraph, and the prototype draws the live
meter with `flex: 1` bars under a fixed `3pt` gap, so the two are describing
different things.

So: `.scrub` uses the fixed `5/3/8` geometry and draws only the bars the box can
show, and `.resting`/`.live` spread exactly 48 bars across whatever width they
are given (`WaveformGeometry.liveBarWidth`, ~4.4pt a bar at 354). The count is
what the eye reads on a meter — it is what makes the roll legible as a rate —
so the width is what gives.

Two consequences worth knowing before changing it. The bar width is now a
function of the container, so a narrower host (a future compact layout, a
landscape story that does not yet exist) thins the bars rather than dropping
them. And the resting line drawn for an empty take uses the distributed geometry
in every mode, including `.scrub`: an empty take has no playhead to centre, so
there is nothing for the fixed geometry to be fixed against.

### The bloom is a layer behind the `Canvas`, not inside it (#47)

`Canvas` **clips to its frame** — verified on the simulator by filling rects
outside the bounds and seeing nothing render. That is exactly what the scrub
strip wants ("hard edges — the take runs full width, no mask"): `visibleRange`
deliberately resolves a bar of slack past each edge, and the clip is what turns
that slack into a clean edge rather than a bar drawn into the screen margin.

It is the opposite of what the bloom wants. An aura specified at `124%` width
and `208%` height of the box has over half its area outside the box, and drawn
in-canvas it came out as a rectangle with hard top and bottom edges — a
visible difference from `#6b`, which is the escalation the ticket named in
advance ("start with the in-canvas gradient and only add a layer if it visibly
differs"). So the bloom is an `Ellipse` in a `ZStack` behind the `Canvas`.

Two details are load-bearing. It is filled with a radial gradient fading to
transparent at `72%` and *then* blurred — the prototype's own two steps; a solid
fill blurred by the same radius reads several times heavier and swamps the bars.
And the handoff's blur radius is now used literally, where the in-canvas version
had to spend it on a gradient stop standing in for a filter `Canvas` does not
have.

The handoff's "one drawing surface, not N views" is intact: every bar and the
marker are still one `Canvas`. Two views, not fifty.

### `WaveformCanvas` is `Animatable`, because a `Canvas` does not tween (#47)

`Canvas` re-runs its closure when its inputs change; it does not interpolate
between two drawings. Without something to interpolate, the handoff's `.2s`
bloom ease and `40ms` playhead tick would have been dead letters — and honouring
Reduce Motion, which #44 assigns to this component for the whole epic, would
have been vacuous: freezing an animation that never ran.

The private `WaveformCanvas` therefore conforms to `Animatable` with an
`AnimatablePair<progress, enhance>`, so SwiftUI drives those two continuous
values frame by frame and the `Canvas` redraws against interpolated numbers. The
bar *levels* are deliberately not animatable: a rolling meter's bars arrive as
data, one every ~95ms, rather than travelling between two known states, and an
`[Float]` has no meaningful interpolation when its length changes.

**Which view holds the conformance is the whole point.** It is on the inner
drawing view, and `Waveform` applies `.animation(_:value:)` to it from its own
body. Put on `Waveform` itself, `animatableData` would only ever interpolate when
a *caller's* transaction carried an animation — so the component would animate
only by accident, and its `reduceMotion` check would have no say over a caller
who wrapped a change in `withAnimation`. As built, the animation originates
inside the component, which is what lets it own Reduce Motion for the epic the
way #44 assigns: under it both animations resolve to `nil` and every value lands
rather than travels.
