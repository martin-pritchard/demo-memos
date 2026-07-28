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
