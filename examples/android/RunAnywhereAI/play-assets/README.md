# RunAnywhere Google Play assets

These assets were captured from signed `RunAnywhere` Android release candidates
on a Qualcomm SM8850 / Hexagon v81 device running Android 16.

## Release provenance

- Package: `com.runanywhere.runanywhereai`
- Version: `0.1.5` (`versionCode` 14)
- Latest installed APK SHA-256:
  `7d9c700231090e68117cb2da02c4a0800f858e84732647e24312cf856fc1095a`
- Latest source checkpoint: `564ea7eadd99a5e00e26c6dc87058203bda54742`
- Capture dates: July 10–11, 2026
- Raw device captures: `screenshots/v81/`
- Play-ready phone captures: `play-console/phone/`

Captures 01–05 came from the July 10 candidate
`6ab0decfd72bfeec8c4bdaa07fde7647b6e2189b7dcb723057dd5204c422ab8b`.
Captures 06–07 came from the latest July 11 candidate above after the shared
C++ QHexRT catalog, app-diagnostics telemetry bridge, and stable landscape IME
validation. In both runs, the installed
`base.apk` was pulled back from the device and matched the local artifact.

## Screenshot evidence

1. Home — Qwen3.5 0.8B reports `NPU · Ready`; connected tools are disabled.
2. Documents — the local document pipeline cites one source and correctly
   identifies Juniper, Austin, Osaka, Reykjavik, and Morgan Lee.
3. Tools — the model invokes `calculate` and returns `45 × 12 = 540`.
4. Vision — InternVL reads `42`, `58`, `76`, and `91` from the test chart and
   identifies the increasing trend; the result is revealed automatically.
5. Talk — Whisper, Qwen, Kokoro, and Silero VAD all report ready.
6. QHexRT — public Qwen3.5 0.8B is loaded through QNN on Hexagon v81 and
   returns exactly `QHEXRT_OK`, with TTFT, tokens, and throughput visible.
7. Web search — the model invokes `search_web` and cites the official
   `https://aihub.qualcomm.com/` URL while `Web & tools` is explicitly on.

Raw screenshots 01–05 are 1440×3200 portrait device captures. Raw screenshots
06–07 are unchanged 3200×1440 landscape device captures. Their Play phone
assets are deterministic 1800×3200 marketing compositions that embed the real
capture without redrawing its UI. `scripts/build-marketing-captures.sh`
rebuilds those two assets, removes alpha, emits 24-bit sRGB PNG, and validates
dimensions, type, and depth. Both raw and Play-ready directories include
`SHA256SUMS`.

## Other store assets

- `play-console/icon/play-icon-512.png`: 512×512, 32-bit PNG with alpha.
- `play-console/graphics/feature-graphic-1024x500.png`: 1024×500, 24-bit PNG
  without alpha.
- `STORE_LISTING_DRAFT.md`: proposed English listing copy and screenshot alt
  text. Publisher contact and policy fields still require confirmation.

Do not upload a release until the project's internal policy, privacy/Data
Safety, licensing, production-search, and Play Console declaration gates are
complete.
