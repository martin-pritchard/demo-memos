# Decisions

Choices made — or deliberately deferred — during implementation, where the
issue and the architecture principles did not already settle them.

## Deferred

### Waveform data for a reopened memo (#1)

`Memo` stores no level data — the issue's model is id, name, createdAt,
duration, enhance, filename. So a take reopened from the Demos list has nothing
real to draw, and `CaptureState` synthesises a stable stand-in seeded from the
memo's id. It scrubs and looks right, but it is not that recording's shape.

Deferred, not chosen: persisting a downsampled level array alongside the memo,
or decoding the `.m4a` with `AVAssetReader` on open. Both are schema or
performance decisions that belong with the DSP follow-up, which will already be
touching how audio is read at playback time.

### The DSP behind Enhance (#1)

Carried over from the issue: Enhance is persisted per memo and drives the
waveform bloom only. Nothing processes audio yet.

## Decided

### `NSMicrophoneUsageDescription` lives in build settings, not an Info.plist

The issue's plan lists `apps/ios/DemoMemos/Info.plist`. This target has
`GENERATE_INFOPLIST_FILE = YES` and already carries its keys as
`INFOPLIST_KEY_*` build settings, so the usage description was added the same
way. Introducing a hand-written plist would have meant turning generation off
and re-declaring every key that already works.

### Resume works until the take is previewed, then dims

The issue's non-goals name "resume-onto-a-take (3a)", but its agreed behaviour
says "Stop/Record/Resume right", and 1d — cited as normative for the four
states — shows Resume as the stopped state's right button. So it is wired,
because the mechanism is free: `AVAudioRecorder.pause()` / `record()` continue
the same file, and `AudioRecorder` only finalises on `finish()`.

It is free *only* while the file is still open. A part-written `.m4a` is not
readable, so previewing a stopped take has to close it — and appending to a
closed file means stitching segments together with `AVMutableComposition`,
which is real machinery and squarely 3a's job. So Resume is offered until the
take is previewed (or a save fails), and dims after, using the same dimming the
design already uses for Play before a take exists. In `playback` — which never
captures — it is always dimmed.

Deferred to 3a: segment stitching, which would make Resume unconditional.

### Playback's header carries Share only

The design is internally inconsistent: `TakeScreen`'s code renders Share *and*
Done in the playback header, while the 1d state table shows Share alone. 1d
wins, because the issue cites it as the normative description of the four
states, and because playback has nothing to commit — rename commits on
dismiss, and Enhance persists as it changes. Likewise `stopped` shows Done
alone, per 1d.

### Default take names are date-stamped, not "New Demo N"

The design shows "New Demo 1"; the issue says an empty rename "falls back to
the default date-stamped name". Behaviour follows the issue's prose, layout
follows the design, so takes are named like Voice Memos does it. This reads
redundantly against the date line directly beneath it — worth a design pass,
raised on the issue rather than fixed here.
