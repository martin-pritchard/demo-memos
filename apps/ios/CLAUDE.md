# apps/ios

Stack-specific *mechanisms*. The rules they implement live in `docs/PRINCIPLES.md`
— read that first for where a file goes and why.

## Native by default

Reach for the Apple default first; this app should feel first-party. Semantic
fonts + Dynamic Type (`.headline`, `.subheadline`, …) over fixed
`.system(size:)`; semantic colours (`.primary`, `.secondary`, `.tertiary`, the
asset-catalog `AccentColor`) over hardcoded hex; real navigation
(`.navigationTitle`, `.toolbar` with `.cancellationAction` /
`.confirmationAction`, the automatic back button) over hand-rolled header bars;
`ShareLink` over a `UIActivityViewController` bridge; `ContentUnavailableView`
for empty states; standard `.swipeActions`, `.sheet`, list styles, SF Symbols.

Go bespoke **only** where the design deliberately does — the waveform, the
Enhance dial, the transport buttons, the floating New Demo pill, the orange
warm-ramp. Those use `Palette` for their fills; everything standard inherits
`AccentColor`. The hero timer is a fixed-size display element (as Clock / Voice
Memos do), not Dynamic Type. If a design choice and a native default genuinely
conflict, flag it — don't silently pick one.

## Folder shape

```
DemoMemos/
  DemoMemosApp.swift      composition root: @main, Services, RootView (routing)
  Memos/                  feature — the Demos list
  Capture/                feature — the take screen (record + playback)
  Onboarding/             feature — the one-time first-launch intro
  Audio/                  UI-free core: capture/playback seams, fakes
  DesignSystem/           shared UI: Palette (+ its format extensions)
```

Sharing is native `ShareLink` in both features — there is no ShareSheet bridge.

One feature per folder, holding its screen, its state object and any component
only it uses (`WaveformView` and `EnhanceSlider` live in `Capture/` for exactly
that reason). Promote to `DesignSystem/` only when a second feature actually
uses it.

`Audio/` and the model/store files import no SwiftUI. Keep it that way.

## UI-state pattern

One `@MainActor @Observable final class` per screen, named `<Feature>State`,
holding `private(set)` state and exposing intent methods. Views take the state
in via `@Bindable` and emit events out as closures — no view constructs a
service, fetches, or writes to disk. The state object takes its dependencies as
initialiser arguments; only `Services.live()` builds real ones.

Transitions are plain methods on the state object, so they are testable with no
simulator audio and no files.

## Seams

`MemoStore`, `AudioRecorder` and `AudioPlayer` are protocols with one real
implementation and one fake each. They exist because the tests and every
preview run on the fake — not for anticipated flexibility. Don't add a protocol
without both.

`Audio/Fakes.swift` holds the fakes plus `PreviewScenario`, the named sample
data (`emptyStore`, `populatedStore`, `sampleMemo`, …).
`Capture/CapturePreview.swift` does the same for the take screen's four states.
Every `#Preview` sources its data from one of those two — never from a live
service.

## Xcode project

The targets use file-system-synchronized groups: creating a file inside
`DemoMemos/` adds it to the target automatically, no `project.pbxproj` edit.

`GENERATE_INFOPLIST_FILE = YES` — there is no Info.plist. Plist keys go in
build settings as `INFOPLIST_KEY_*` (e.g.
`INFOPLIST_KEY_NSMicrophoneUsageDescription`).

## Audio session

`AudioSession` in `Audio/AudioRecorder.swift` is the only place the category is
configured. Record and playback both go through it, so they can't fight over it.
