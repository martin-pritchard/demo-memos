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

### Resume is wired, not just drawn

The issue's non-goals name "resume-onto-a-take (3a)", but its agreed behaviour
says "Stop/Record/Resume right", and 1d — cited as normative for the four
states — shows Resume as the stopped state's right button. A visible,
enabled-looking button that does nothing is worse than either, and the
mechanism is free: `AVAudioRecorder.pause()` / `record()` continue the same
file, so `AudioRecorder` brackets a take with `pause`/`record` and only
finalises on `finish()`. Turn 3a itself — which control shape to use — was
already resolved by the design.

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
