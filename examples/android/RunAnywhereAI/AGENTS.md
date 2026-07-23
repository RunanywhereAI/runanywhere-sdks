# Android RunAnywhereAI example

This file applies to `examples/android/RunAnywhereAI/`. Run commands from this directory unless noted otherwise.

## Common commands

```bash
./scripts/smoke.sh                         # Fast static SDK-usage check
../../../scripts/build/build-core-android.sh arm64-v8a
./scripts/stage-sdk-aars.sh debug          # Required after SDK/native changes
./scripts/verify.sh                        # Strict debug APK build from staged AARs
./gradlew :app:testDebugUnitTest           # JVM tests
./gradlew :app:lintRelease                 # Release lint
```

The app consumes four local AARs from `libs/`: core SDK, LlamaCPP, ONNX, and QHexRT. After native or Kotlin SDK changes, rebuild/stage those artifacts before trusting an app build.

## Scripts

| Script | Purpose and normal use |
|---|---|
| `smoke.sh` | Grep-based SDK API coverage check. Set `RUN_BUILD_GATES=1` to call `verify.sh` too. |
| `verify.sh` | Debug APK build gate with strict Gradle dependency verification. The four ignored `libs/*.aar` files must already be staged. `REFRESH_NATIVE=1` only refreshes SDK native inputs; restage the AARs afterward before trusting the app build. |
| `stage-sdk-aars.sh` | `stage-sdk-aars.sh [debug\|release]` builds the four Kotlin SDK AARs from already-staged local native libraries and copies deterministic names into `libs/`. |
| `sync-solutions-yamls.sh` | Regenerates `SolutionsYaml.kt` from canonical Commons YAML. Use `--check` in validation; never edit the generated Kotlin file directly. This checks source synchronization, not end-to-end solution execution. |

Private QHexRT device and Play-release orchestration lives in the sibling checkout. See
`../../../../QHexRT/docs/BUILD.md`, run NPU acceptance through
`../../../../QHexRT/device_suites/run_android_e2e.sh`, and create release evidence through
`../../../../QHexRT/tools/scripts/runanywhere_android_release/build_play_aab.sh`.

After editing these scripts, run `bash -n scripts/*.sh`,
`bash scripts/sync-solutions-yamls.sh --check`, `scripts/smoke.sh`, and `git diff --check`.

## Design System

Brand primary is RunAnywhere orange **#FF6900** (the logo color) — see the canonical
`../../DESIGN_GUIDELINE.md`. Theming is 100% Jetpack Compose Material 3:
`app/src/main/java/com/runanywhere/runanywhereai/ui/theme/Color.kt` (`BrandOrange =
0xFFFF6900` + the `Primary*` tonal ramp around the #FF6900 hue) and `Theme.kt`
(`lightColorScheme`/`darkColorScheme`, no dynamic color so the brand is guaranteed).
`res/values/colors.xml` holds only structural black/white. When changing brand colors,
edit `Color.kt` and keep it in sync with the guideline.
