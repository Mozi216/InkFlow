# NetEase audio fingerprint runtime

This prototype computes a fingerprint locally and sends it directly to NetEase's
`https://interface.music.163.com/api/music/audio/match` service. It does not send
raw PCM, use ShazamKit, run a relay server, or download executable code at runtime.

`afp.js` and `afp.wasm` are copied from the MIT-licensed
[NeteaseCloudMusicApiEnhanced example](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced/tree/main/public/audio_match_demo).
The upstream license is retained in `LICENSE.txt`. The WASM algorithm is a
NetEase-distributed binary; the example repository's license is not proof of
rights to redistribute NetEase's underlying algorithm in a commercial app.
This integration is for the present personal-device prototype. Distribution and
service terms need separate review before an App Store release.

WASM SHA-256: `8064415bb66e45410e88877f07cd007a3ae62ebf463aac13c159a8f13e4c8fe8`.
The same binary was observed in NetEase's official Chrome extension 1.0.4.

To reproduce `fingerprint-runtime.js` with Binaryen version 133:

```sh
wasm2js afp.wasm -O -o fingerprint-core.js
node compile-runtime.cjs
node ../../scripts/test-fingerprint.cjs
```

The build script removes the browser/WASM loader, uses the generated synchronous
module, and adds a PCM base64 input and fingerprint base64 output. JavaScriptCore
runs this static resource on its own serial queue. Both App and ReplayKit targets
bundle it; the Widget does not. `fingerprint-core.js` is an intermediate output.

2026-10-16 checks: the converted implementation exactly matched the WASM output
for a 12-second public preview sample; generated noise was rejected by the music
service. Several 12-second excerpts correctly matched Shape of You and their
reported positions followed the excerpts' 3-second changes. Other window lengths
failed to match that sample, so this prototype uses 12 seconds. This does not yet
establish recognition accuracy across songs or timing accuracy on the iPhone.
