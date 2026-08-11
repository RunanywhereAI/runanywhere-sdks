# Android RunAnywhereAI example

This file applies to `examples/android/RunAnywhereAI/`. Run commands from this directory unless noted otherwise.

## Common commands

```bash
./scripts/smoke.sh                         # Fast static SDK-usage check
./scripts/verify.sh                        # Strict debug APK build gate
./gradlew :app:assembleDebug               # Debug APK
./gradlew :app:testDebugUnitTest           # JVM tests
./gradlew :app:lintRelease                 # Release lint
```

## SDK dependency

The app consumes the RunAnywhere SDK **entirely from Maven Central** — there are no
local AARs and no relative paths into any SDK source tree. Coordinates live in
`gradle/libs.versions.toml` under the single `runanywhere` version:

| Coordinate | Role |
|---|---|
| `io.github.sanchitmonga22:runanywhere-sdk` | Core SDK + commons native libraries |
| `io.github.sanchitmonga22:runanywhere-llamacpp` | LlamaCPP backend (LLM, VLM) |
| `io.github.sanchitmonga22:runanywhere-onnx` | Sherpa-ONNX backend (STT, TTS, VAD) |
| `io.github.sanchitmonga22:runanywhere-qhexrt-android` | QHexRT backend (Qualcomm Hexagon NPU) |

All four are published together; never mix versions. To move to a new SDK release,
bump `runanywhere` in `gradle/libs.versions.toml`, then regenerate
`app/gradle.lockfile` (`./gradlew :app:dependencies --write-locks`) and
`gradle/verification-metadata.xml`
(`./gradlew --write-verification-metadata sha256 :app:assembleDebug`).

The published POMs supply the SDK's own transitive dependencies (wire-runtime,
okhttp, coroutines-core, okio, kotlin-stdlib, kotlinx-serialization-json,
androidx core-ktx), so `app/build.gradle.kts` declares only what the app itself uses.

## Scripts

| Script | Purpose and normal use |
|---|---|
| `smoke.sh` | Grep-based SDK API coverage check. Set `RUN_BUILD_GATES=1` to call `verify.sh` too. |
| `verify.sh` | Debug APK build gate with strict Gradle dependency verification. Needs only the Android SDK and network access. |

`app/src/main/java/.../solutions/SolutionsYaml.kt` is generated from the canonical
Commons solution YAMLs in the SDK monorepo. It is committed verbatim; regenerate it
there, not here.

After editing these scripts, run `bash -n scripts/*.sh`, `scripts/smoke.sh`, and
`git diff --check`.

## Design System

Brand primary is RunAnywhere orange **#FF6900** (the logo color). Theming is 100%
Jetpack Compose Material 3:
`app/src/main/java/com/runanywhere/runanywhereai/ui/theme/Color.kt` (`BrandOrange =
0xFFFF6900` + the `Primary*` tonal ramp around the #FF6900 hue) and `Theme.kt`
(`lightColorScheme`/`darkColorScheme`, no dynamic color so the brand is guaranteed).
`res/values/colors.xml` holds only structural black/white. When changing brand colors,
edit `Color.kt` and keep it in sync with the RunAnywhere design guideline.
