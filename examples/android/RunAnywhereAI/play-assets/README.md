# RunAnywhere Google Play assets

These assets were captured from the signed `RunAnywhere` Android release on a
Qualcomm SM8850 / Hexagon v81 device running Android 16.

## Release provenance

- Package: `com.runanywhere.runanywhereai`
- Version: `0.1.5` (`versionCode` 14)
- Installed APK SHA-256:
  `6ab0decfd72bfeec8c4bdaa07fde7647b6e2189b7dcb723057dd5204c422ab8b`
- Capture date: July 10, 2026
- Raw device captures: `screenshots/v81/`
- Play-ready phone captures: `play-console/phone/`

The installed base APK was pulled back from the device and its SHA-256 matched
the local signed artifact before these screenshots were captured.

## Screenshot evidence

1. Home — Qwen3.5 0.8B reports `NPU · Ready`; connected tools are disabled.
2. Documents — the local document pipeline cites one source and correctly
   identifies Juniper, Austin, Osaka, Reykjavik, and Morgan Lee.
3. Tools — the model invokes `calculate` and returns `45 × 12 = 540`.
4. Vision — InternVL reads `42`, `58`, `76`, and `91` from the test chart and
   identifies the increasing trend; the result is revealed automatically.
5. Talk — Whisper, Qwen, Kokoro, and Silero VAD all report ready.

Raw screenshots are 1440×3200 device captures. The checked-in preparation
script pads them symmetrically to 1800×3200, removes alpha, converts to 24-bit
sRGB PNG, validates dimensions/type/depth, and writes `SHA256SUMS`.

## Other store assets

- `play-console/icon/play-icon-512.png`: 512×512, 32-bit PNG with alpha.
- `play-console/graphics/feature-graphic-1024x500.png`: 1024×500, 24-bit PNG
  without alpha.
- `STORE_LISTING_DRAFT.md`: proposed English listing copy and screenshot alt
  text. Publisher contact and policy fields still require confirmation.

Do not upload a release until the policy, privacy/Data Safety, licensing,
production search proxy, and Play Console declaration gates in
`docs/PLAY_STORE_RELEASE.md` are complete.
