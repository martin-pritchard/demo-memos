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

### The count-in is four beats, not three (#3)

The issue's acceptance criteria say "three beats"; the design bundle's own
intro to turn 8 says the same. But the chosen option 8a is labelled "counting
4·3·2·1 inside the ring", its runnable prototype counts 4·3·2·1 at one beat a
second, and turn 8's "try next" offers to "make the count length a setting (off
/ 3 / 4 beats)" — which only reads as an offer if 4 is what was built. The
runnable artifact is the more specific authority, and the issue itself repeats
"4·3·2·1", so the count is four. Raised on the issue rather than silently
reconciled.

### The tick is a system sound, and obeys the silent switch

`SystemSoundCountInTicker` plays `SystemSoundID` 1103 (`Tink`) —
native-by-default, and it means no audio asset ships in the binary for four
clicks. The consequence is that `AudioServicesPlaySystemSound` respects the
ring/silent switch, so a count-in on a silenced phone is visible but not
audible.

Deferred, not chosen: routing the tick through an `AVAudioPlayer` on the
recording session so it plays regardless of the switch, which would need a
bundled tick sample and would put the ticker in the business of configuring the
audio session — currently `AudioSession`'s job alone. Whether a musician's
count-in should override silent is a product question, not one to settle inside
a UI ticket.

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
