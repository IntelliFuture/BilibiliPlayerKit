# BilibiliPlayerKit

SwiftUI/UIKit wrapper for Bilibili's official iframe player.

The package intentionally embeds `https://player.bilibili.com/player.html` instead of extracting direct video streams.

## Demo

Open:

```sh
open Example/BilibiliPlayerDemo.xcodeproj
```

The demo includes switches for iframe/direct loading, `p`/`page` part parameters, autoplay, danmaku, and quality so player behavior can be tested in isolation before integration.

## Simulator Note

On the current iOS Simulator, Bilibili playback can render as a green video surface when the official player chooses the mobile WebKit playback path.

The demo has two mitigations enabled by default:

- `preferAVCPlayback`: injects a `WKUserScript` at document start and requests AVC/H.264-oriented playback by disabling HEVC/AV1 config where the embedded player exposes it.
- `desktopSafariUserAgent`: avoids Bilibili's mobile-player redirect, which is the path that reproduced the green surface in Simulator Safari.

The demo app is also portrait-only. If the host app supports landscape, Bilibili's player may request a landscape/fullscreen-style presentation.


## Confirmed control and page-owned looping

`play()` waits for the media play promise. `seek(to:)` pauses internally, waits
for `seeked`, checks the requested position within 25 ms and at least
`HAVE_CURRENT_DATA`, then resumes only if the current playback intent still
wants it. A same-position seek can complete without a redundant seek event.
Commands target the actual media frame through `callAsyncJavaScript`, rather
than broadcasting a fire-and-forget command to every frame.

```swift
try await player.setLoopRange(.init(start: 77.560, end: 91.190))
try await player.seek(to: 77.560)
try await player.play()
// User pause cancels an in-flight loop return without losing the configured range.
try await player.pause()
// Continue normally without a sentence bound.
try await player.setLoopRange(nil)
```

Loop end checks, immediate pause, confirmed seek and replay run inside the
media page. A playback-rate-adjusted timer and animation-frame check supplement
each other. There is no per-round native progress/command round trip. The caller
chooses any early-end margin; the library does not silently add another one.
Internal seek/loop transitions preserve playback intent. `PlaybackSnapshot`
exposes `isSeeking` and `isLoopTransition` so hosts can withhold transient
position updates; `rawCurrentTime` and `loopBoundaryTime` retain diagnostic
positions separately from the bounded, confirmed display position.

Transport commands supersede older waits. Cancelling the latest Swift command
pauses it; cancelling an already-superseded command cannot stop a newer one.
Reloaded content has a new session identity, and stale command revisions or
out-of-order snapshots are discarded. Media metadata, rather than top-frame
navigation completion, establishes readiness. Seek/play waits fail after ten
seconds instead of silently continuing at an unconfirmed position.

The bridge still depends on the official page exposing a video element and on
WebKit scheduling. A page timer is not a decoder-enforced or sample-accurate end
bound. Real Bilibili audio, background behavior and buffering need device
acceptance; a successful build or synthetic DOM test does not establish audible
boundary accuracy.

`PlaybackControlTests` exercise the injected bridge with a controlled media
fixture: delayed seek completion, a newer pause, and page-loop restart/cancellation.
The fixture reports the requested currentTime immediately but withholds seeked,
so a command-dispatch acknowledgement cannot pass as seek completion. No public
Bilibili request is involved. These cases were added without executing them in
this revision, per the integrating application's owner acceptance workflow.
