# Capture: session, hardware, format, metering

Read with `SKILL.md`. This is the detail behind "check the session and format
first". Verify exact symbol names and availability against Apple's docs or the
SDK headers before writing them — see the lookup section in `SKILL.md`.

## The session decides more than any effect

`AVAudioSession` category + mode set what the OS does to your signal before you
ever see a sample. Get this wrong and no amount of post-processing recovers it.

### Category

- `.playAndRecord` — what this app uses. Needed for record, and for playing back
  without tearing the session down. Pair with `.defaultToSpeaker` so playback
  does not come out of the earpiece.
- `.record` — capture only. Slightly less contention, but means reconfiguring to
  play back, which is exactly what `AudioSession` exists to avoid here.
- `.playback` — playback only, and the app's playback path.

### Mode — the big lever for music

`mode` selects the system's signal-processing profile:

- **`.measurement`** — disables system input processing: automatic gain control,
  input EQ, and other tuning. **For music capture this is usually the single
  biggest quality win.** AGC exists to keep speech level and it audibly rides
  the dynamics of a strummed chord or a sung phrase — precisely the thing a song
  demo needs to preserve.
  The trade-off is real and must be stated when recommending it: with AGC off,
  a loud source can clip and nothing will save it. Quiet input also stays quiet.
- **`.default`** — some system processing. Fine for voice, compromises music.
- **`.voiceChat` / `.videoChat`** — enable voice processing: echo cancellation,
  aggressive AGC, noise suppression. Actively wrong for music. Never select
  these for a take.

`.measurement` also tends to reduce input latency. Set mode in the same
`setCategory(_:mode:options:)` call, not afterwards.

### Options worth knowing

- `.defaultToSpeaker` — already used here.
- `.allowBluetoothHQ` / `bluetoothHighQualityRecording` (iOS 26) — enables a
  high-quality, high-sample-rate Bluetooth input path with media tuning aimed at
  content creators, with a more reliable link for AirPods. Directly relevant:
  someone recording a song idea on AirPods is a real case for this app. Confirm
  the exact option spelling in the current SDK before use.
- `.allowBluetooth` legacy paths fall back to a narrowband voice profile — that
  is the behaviour `bluetoothHighQualityRecording` supersedes.
- `.mixWithOthers` / `.duckOthers` — only if the product wants to coexist with
  other audio. It does not today.

Also consider `setPrefersNoInterruptionsFromSystemAlerts(true)` so a
notification does not end a take.

## Rate, channels, format

- **48 kHz is the native hardware rate** on modern iPhones. Requesting 44.1
  forces a resample in the capture path. For a new music-facing decision prefer
  48 kHz; changing the existing app's 44.1 is a format decision worth a ticket,
  not a drive-by edit (existing files stay readable either way — the field is
  per-file).
- Ask for the rate on the session (`setPreferredSampleRate`) *and* in the
  recorder settings, then read back what you actually got. Preferred is a
  request, not a guarantee.
- **Mono is right for one voice or one instrument** and halves the file. Stereo
  earns its size only with a genuine stereo source.
- **AAC in `.m4a`** uses the hardware encoder: small files, low power. Correct
  for demos.
- **Linear PCM / `.wav` or `.caf`** only when samples must survive round-trips
  intact — repeated re-encoding, or offline processing that will be re-encoded
  after. Costs roughly 10× the size. For a demo app, AAC at high quality is the
  right call and generational loss on one pass is inaudible.
- If a processed export is ever added, render to PCM, apply effects, then encode
  once at the end. Never encode twice.

## Getting the most from the microphones

Modern iPhones have multiple mics and expose real control over them.

- **Choose the input** — `AVAudioSession.availableInputs`, then
  `setPreferredInput(_:)`.
- **Choose the polar pattern** — a built-in mic port exposes
  `dataSources`, each with `supportedPolarPatterns`
  (`.cardioid`, `.subcardioid`, `.omnidirectional`, `.stereo`). Select with
  `setPreferredDataSource(_:)` and `setPreferredPolarPattern(_:)`.
  Cardioid rejects off-axis room noise; omni captures the space.
- **Stereo built-in capture** — set `preferredInputNumberOfChannels = 2` and
  `setPreferredInputOrientation(_:)` with an `AVAudioSession.StereoOrientation`
  so the stereo field follows how the phone is held. Requires supporting
  hardware; check `maximumInputNumberOfChannels`.
- **Input picker (iOS 26)** — `AVInputPickerInteraction` (AVKit) presents the
  system input list in-app, so users can switch source without going to
  Settings. The native-by-default answer to "let me pick my mic".
- **Buffer duration** — `setPreferredIOBufferDuration(_:)`. Smaller means lower
  latency and higher dropout risk. Only touch this for live monitoring or
  real-time processing; plain recording should take the default.

Read back every "preferred" value after activating the session and log or
handle the mismatch. The OS grants what the route allows.

## Levels and metering

- `isMeteringEnabled = true`, then `updateMeters()` before each read.
- **`averagePower(forChannel:)`** is RMS-ish — smooth, good for a waveform, which
  is what this app draws.
- **`peakPower(forChannel:)`** catches transients. Use it for anything that warns
  about clipping; average power will happily read −8 dB while peaks clip.
- Both are **dBFS**, roughly −160 (silence) to 0 (full scale). Usable input sits
  around −55…0, which is where this app's floor comes from.
- Converting to a bar or waveform height needs a curve, not a linear map — a
  linear dBFS map leaves quiet material invisible. This app uses
  `pow((dB - floor) / -floor, 1.6)`.
- **Target peaks at −6 to −12 dBFS.** Headroom is free; clipping is permanent.
- For sample-accurate levels (or to persist real waveform data), tap the engine:
  `installTap(onBus:bufferSize:format:)` and reduce each
  `AVAudioPCMBuffer`. Note that persisting levels is a schema decision, not a
  free change.

## Interruptions and route changes

A take in progress must survive contact with the OS. Handle both:

- `AVAudioSession.interruptionNotification` — call, Siri, alarm. On `.began`,
  capture has already stopped; keep the file and tell the user. On `.ended`,
  check `shouldResume`.
- `AVAudioSession.routeChangeNotification` — `.oldDeviceUnavailable` means
  headphones or an interface were unplugged mid-take.

This app routes both onto `AudioRecorder.onInterruption` and its contract is
explicit: **the take must be kept, not dropped.** Preserve that.

After any interruption, re-activate the session before recording again, and
expect the granted format to have changed if the route did.

## Permission

`AVAudioApplication.shared.recordPermission` and
`AVAudioApplication.requestRecordPermission()` (iOS 17+) are the current API —
already used here. The usage string is `NSMicrophoneUsageDescription` in
`apps/ios/DemoMemos/Info.plist`. The target sets both `INFOPLIST_FILE` and
`GENERATE_INFOPLIST_FILE = YES`, so hand-written keys go in that plist and
Xcode-generated ones stay `INFOPLIST_KEY_*` build settings. The plist already
carries the microphone string and the `audio` background mode.

## Spatial and ambisonic capture (iOS 26)

Available, and almost certainly out of scope for a mono song sketch — but know
it exists before dismissing it: `AVCaptureDevice.multichannelAudioMode =
.firstOrderAmbisonics` with `AVAssetWriter` records a First Order Ambisonics
scene, and the Cinematic framework's Audio Mix
(`CNAssetSpatialAudioInfo.audioMix(effectIntensity:renderingStyle:)`) rebalances
foreground against background at playback. That is a video-and-scene feature
set; if it ever fits here it is its own ticket.
