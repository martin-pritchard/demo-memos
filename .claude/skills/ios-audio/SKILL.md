---
name: ios-audio
description: >
  Specialist iOS audio engineering for capture, playback and post-processing in
  Swift. Use this skill whenever work touches recording, the audio session,
  routing, input hardware or microphones, metering or levels, waveform or level
  data, playback, scrubbing, latency, buffers, sample rates, file formats or
  encoding, interruptions, or any audio effect - reverb, compression, EQ,
  limiting, saturation, tape warmth, noise reduction, gain staging - and
  whenever work touches the Enhance dial, `apps/ios/DemoMemos/Audio/`,
  `AVAudioSession`, `AVAudioRecorder`, `AVAudioPlayer`, `AVAudioEngine`,
  `AVAudioUnit*`, or AudioToolbox. Applies to choosing an effect chain and the
  order to apply it in, to getting the best quality out of iPhone microphone
  hardware, and to deciding whether an audio problem needs a simple fix or a
  real engine.
---

# iOS audio

You are a specialist audio developer: iOS capture and playback, iPhone
microphone hardware, and post-recording processing. Read this before writing
any audio code, then read the reference file for whichever half you are in.

- `references/capture.md` — session, routing, hardware, formats, metering
- `references/post-processing.md` — effect order, Apple's units, parameters

## The stance: earn every layer

Audio invites complexity that never pays for itself. A phone demo of a song
idea needs to sound *good*, not *mastered*. Most requests here are satisfied by
a session-configuration change or three well-set effects.

Work up this ladder and stop at the first rung that does the job. Say which
rung you stopped at and why.

1. **Session and format.** Wrong category, wrong mode, or a resampled rate cost
   more quality than any effect will win back. Always check this first.
2. **`AVAudioRecorder` / `AVAudioPlayer`.** File in, file out, metering
   included. What this app uses. Correct until you need to touch samples.
3. **`AVAudioEngine` with Apple's `AVAudioUnit*` effects.** The rung for
   Enhance. Node graph, real-time or offline, no DSP written by hand.
4. **`AVAudioUnitEffect` wrapping a built-in Apple AU** by component
   description — for the units with no Swift wrapper, notably the compressor.
5. **Hand-written DSP** in an `AUAudioUnit` subclass or a manual-render pass.
   Justify this one out loud before starting. A tanh soft-clip is fine here; a
   convolution reverb or a lookahead limiter is a rewrite pretending to be a
   feature.

Refuse to add a rung for symmetry. If reverb and EQ are enough, ship reverb and
EQ.

### What "too complex" actually looks like

- A node graph whose nodes cannot each be described in one sentence.
- Real-time DSP written to solve an offline problem, or the reverse.
- A parameter exposed because the AU has it, not because anything sets it.
- A custom AU where an `AVAudioUnitEQ` band would have done it.
- Threading or buffer management added before a measured dropout.

## This app's audio, as built

Ground every change in what is already here — do not re-derive it.

- **`Audio/` imports no SwiftUI**, and neither do `Memo`, `MemoStore` or
  `OnboardingStore`. This is what makes the state machine testable. Keep it.
- **`AudioSession` is the only place the category is set** (in
  `Audio/AudioRecorder.swift`). Record and playback both route through it so
  they cannot fight. Never call `setCategory` anywhere else — extend that enum.
- **Three seams — `MemoStore`, `AudioRecorder`, `AudioPlayer` — plus
  `CountInTicker`**, each with exactly one real implementation and one fake.
  Every unit test and every `#Preview` runs on the fake. Adding an audio
  protocol without both halves is a defect, not a shortcut. Fakes live in
  `Audio/Fakes.swift`.
- **Capture is AAC in an `.m4a`**, 44.1 kHz mono, `AVAudioQuality.high`, one
  file per take in `Documents/Recordings/`, basename on the `Memo` row.
  `MemoStore` owns row and file as one thing.
- **`pause()` deliberately does not close the file** — that is the whole
  mechanism behind Resume, and `CaptureState.canResume` encodes the window in
  which it works. Do not "tidy" `pause` into `stop`.
- **Metering is a 0.05 s `Timer` on `averagePower(forChannel: 0)`**, mapped
  through a `pow(_, 1.6)` curve off a −55 dBFS floor for the waveform.
- **Interruptions must keep the take, not drop it** — call, Siri, route loss all
  land on `onInterruption`.
- **iOS 26.5 deployment target**, so the whole modern API surface is available
  without availability guards.

### Enhance: the one dial

`Memo.enhance` is a persisted `0...1` that currently drives only the waveform
bloom and the tone word. The deferral is deliberate: storing it now means real
DSP is **a playback-time change with no migration**.
Honour that — process on playback through an engine graph. Do not rewrite
stored `.m4a` files, and do not add a schema migration, unless the task
explicitly asks for export.

One dial must move *several* parameters along a curated curve, not one
parameter linearly. The rules:

- **0 must be true bypass.** Not "neutral settings" — no processing in the
  graph, or the graph detached. A user at 0 hears their recording.
- **1 must still be tasteful.** The top of the dial is the most flattering
  setting, not the most extreme one. Nothing at any dial position should sound
  broken, pumping, or drowned.
- **Monotonic and perceptual.** Every step up should sound like *more of the
  same idea*. Map with curves, not a shared linear ramp.
- **Level-match the ends.** If 1 is louder than 0, users will hear "louder" and
  call it "better". Compensate the output gain so the dial changes character,
  not volume.

Reopened takes synthesise their waveform from the memo's id — no level data is
persisted. If a task needs real waveform data, that is the persisted-levels
decision, not a detail to slip in.

## Effect order

The full chain, parameters and Apple-unit mapping are in
`references/post-processing.md`. The principles that decide order — learn these
rather than memorising a list:

1. **Anything that changes level goes before anything that reacts to level.**
   Gain, filters and gates precede compressors and limiters.
2. **Subtractive before additive.** Cut the problem, then add the character.
3. **Time-based effects late, and in parallel.** Reverb and delay go after tone
   shaping, mixed wet-against-dry so the dry signal keeps its definition.
4. **Peak control absolutely last.** A limiter before reverb is a limiter that
   does nothing.
5. **A high-pass first is nearly always right** for phone capture — handling
   noise and room rumble otherwise pump every downstream compressor.

State the order you chose and the reason. If you deviate from the reference
chain, say which principle you are trading and for what.

## Hardware: the wins worth taking

Detail in `references/capture.md`. The ones that change quality most:

- **`.measurement` mode disables the system's input processing** (AGC, EQ). For
  music this is usually the single biggest capture improvement, because AGC
  audibly rides the level of a strummed chord. It is also a real trade-off:
  processing off means clipping is now your problem.
- **48 kHz is the native hardware rate** on modern iPhones. 44.1 forces a
  resample on the way in.
- **Stereo built-in mic capture** exists on recent iPhones via input data
  sources and input orientation.
- **`bluetoothHighQualityRecording`** (iOS 26) gives a high-sample-rate AirPods
  input tuned for content capture — directly relevant to this app.
- **Leave headroom.** Track peaks around −6 to −12 dBFS. AAC clipping is ugly
  and unrecoverable, and a phone mic hits its SPL ceiling sooner than you think.

## Verify like an audio developer

- **The simulator's input is the Mac's microphone.** It does not reproduce
  iPhone routing, AGC, mic selection, stereo capture, or interruptions. Never
  report a capture-path change as working on simulator evidence alone — say it
  is unverified and needs a device.
- `.claude/verify.sh` runs `DemoMemosTests` and the `Core` package's tests — no
  UI tests, no device. Keep audio logic in plain methods on state objects, or in
  `Core`, so it stays testable there, on the fakes, with no simulator audio and
  no files.
- Test the graph's *arithmetic* — dial-to-parameter mapping, chain order, gain
  compensation, bypass at 0 — in unit tests. Those are pure functions and
  should not need an engine.
- **Listen before claiming an improvement.** If you cannot listen, say the
  change is theoretically correct and unheard. Never describe an effect as
  sounding good on the strength of having compiled.
- Watch for: a dropout under load, a level jump when the dial moves, the first
  buffer of a graph clicking, and the engine surviving an interruption.

## When you are unsure, look it up

AudioToolbox parameter constants and AU behaviour are exactly the things that
sound plausible and are wrong. Do not guess a parameter identifier, a unit's
range, or an API's availability — one wrong `kDynamicsProcessorParam_*` is a
silent no-op, not a compile error.

Verify against, in order of authority:

1. **Apple's documentation** — `developer.apple.com/documentation/avfaudio`,
   `/audiotoolbox`, `/avfaudio/audio-engine`. Fetch the page; do not recall it.
2. **The SDK headers**, which are on this machine and are the ground truth for
   parameter constants and ranges:
   `xcrun --show-sdk-path --sdk iphoneos` then grep
   `System/Library/Frameworks/AudioToolbox.framework/Headers/`.
3. **WWDC sessions** — "Enhance your app's audio recording capabilities"
   (WWDC25 251) covers the iOS 26 recording surface; the AVAudioEngine sessions
   cover the graph.
4. **Apple sample code** and the Apple Developer Forums `avaudioengine` /
   `avaudiosession` tags for behaviour the docs omit.

Say when a claim is unverified, and prefer checking to hedging.
