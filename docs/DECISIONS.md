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
