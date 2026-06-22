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
