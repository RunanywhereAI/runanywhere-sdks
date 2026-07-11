# RunAnywhere Google Play assets

These assets were captured from signed `RunAnywhere` Android release candidates
on a Qualcomm SM8850 / Hexagon v81 device running Android 16.

## Release provenance

- Package: `com.runanywhere.runanywhereai`
- Version: `0.1.5` (`versionCode` 14)
- Latest installed APK SHA-256:
  `a11345bbe0efd58695760b5a074c7e044f73eb6d5079f1aa3aced85eebc2b4e7`
- Latest source checkpoint: `b67f6fef1c1b9cfc3354053d4bf1a911a23d8461`
- Capture dates: July 10–11, 2026
- Raw device captures: `screenshots/v81/`
- Play-ready phone captures: `play-console/phone/`

Captures 01–05 came from the July 10 candidate
`6ab0decfd72bfeec8c4bdaa07fde7647b6e2189b7dcb723057dd5204c422ab8b`.
Captures 06–07 came from the latest July 11 candidate above after the shared
C++ QHexRT catalog and landscape IME fixes. In both runs, the installed
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
   returns exactly `4`, with TTFT, tokens, and throughput visible.
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

Do not upload a release until the policy, privacy/Data Safety, licensing,
production search proxy, and Play Console declaration gates in
`docs/PLAY_STORE_RELEASE.md` are complete.
