# Architecture Principles — iOS appendix

Stack-specific *mechanisms* for this repo's iOS app, and project rules that
`docs/PRINCIPLES.md` is silent on. That file is plugin-managed and overwritten
wholesale on update; **this one is not**, so anything hand-written lives here.

Read with `docs/PRINCIPLES.md`, which governs *why* and *where*. This file
governs *how*, for Swift and Apple frameworks.

---

## 1. Never block a realtime audio thread

**Hard rule. No exceptions, no "just this once".**

An audio render callback or tap block — `AVAudioNode.installTap(onBus:…)`,
`AVAudioSourceNode` / `AVAudioSinkNode` render blocks, and any `AUAudioUnit`
render block — runs on a realtime thread with a hard deadline. Miss the
deadline and the user hears a click, a dropout, or a stutter. There is no
recovery and no error; the audio is simply wrong.

Inside such a callback you must **not**:

- **Allocate memory** — no `Array` growth, no `Data`, no `String`, no boxing,
  no implicit CoW copy. Allocation can take a lock in the allocator.
- **Take a lock** — no `NSLock`, no `os_unfair_lock`, no `DispatchQueue.sync`,
  no `@synchronized`. Priority inversion against a lower-priority thread will
  stall you past the deadline.
- **Call Swift concurrency** — no `async`, no `await`, no `Task`, no actor
  hop. The cooperative pool is not realtime-safe and hopping off the thread
  misses the deadline by definition.
- **Touch UI or observable state** — no SwiftUI view state, no `@Published`,
  no `@Observable` property writes, no `NotificationCenter`. These are main-actor
  concerns and most of them allocate.
- **Do file or network I/O**, or call anything whose implementation you have
  not read and cannot vouch for on all three counts above.

**What to do instead:** copy the samples into a **preallocated** lock-free ring
buffer and return. Everything else — writing to disk, computing levels,
updating the UI — happens on another thread that drains the buffer.

Why this is written down: the naive version compiles, runs, and mostly works.
It fails under memory pressure, on older hardware, and in front of the user.
By the time a dropout is reproducible the cause is three layers away.

**Scope:** this binds only realtime callbacks. `AVAudioRecorder` and
`AVAudioPlayer` do not expose one — they are safe to drive from the main actor,
which is one reason to prefer them until a task genuinely needs sample access
(see the `ios-audio` skill's ladder).

---

## 2. The audio layer imports no UI framework

`apps/ios/DemoMemos/Audio/` is in the app target — an Xcode target, not a
module boundary — so nothing mechanically stops it importing SwiftUI. Do not.
It is `docs/PRINCIPLES.md` #3 held by convention rather than by the compiler:
the state machine stays testable in `DemoMemosTests` with no simulator audio
and no files on disk.

The `Core` package enforces the same rule mechanically and is the better home
for anything that does not need `AVAudioSession`. Prefer `Core` when the choice
is genuinely open.

## 3. Every audio seam ships both halves

A protocol in `Audio/` with only a real implementation is a defect, not a
shortcut. Each one gets a fake in `Audio/Fakes.swift`, and every unit test and
`#Preview` runs on the fake. This is the exception to `docs/PRINCIPLES.md` #8's
warning about single-implementation protocols: here the second implementation
is the test seam, and it must exist before the seam counts as built.

## 4. Simulator evidence does not verify the capture path

The simulator's audio input is the Mac's microphone. It reproduces neither
iPhone routing, nor `AVAudioSession` modes, nor interruptions, nor route
changes, nor jetsam. A change to capture is **unverified** until it has run on
a device — say so plainly rather than reporting a green `verify.sh` as proof.
