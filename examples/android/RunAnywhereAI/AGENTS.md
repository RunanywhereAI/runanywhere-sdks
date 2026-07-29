# Android RunAnywhereAI example

This file applies to `examples/android/RunAnywhereAI/`. Run commands from this directory unless noted otherwise.

## Common commands

```bash
./scripts/smoke.sh                         # Fast static SDK-usage check
./scripts/verify.sh                        # Strict debug APK via Maven Central SDK
./gradlew :app:testDebugUnitTest           # JVM tests
./gradlew :app:lintRelease                 # Release lint

# Optional monorepo override (unreleased SDK/natives):
../../../scripts/build/build-core-android.sh arm64-v8a
./scripts/stage-sdk-aars.sh debug
./gradlew -Prunanywhere.useLocalSdkAars=true :app:assembleDebug
```

Default dependency path is Maven Central (`io.github.sanchitmonga22:runanywhere-*:0.20.11`). Local `libs/*.aar` are only used with `-Prunanywhere.useLocalSdkAars=true`.

## Scripts

| Script | Purpose and normal use |
|---|---|
| `smoke.sh` | Grep-based SDK API coverage check. Set `RUN_BUILD_GATES=1` to call `verify.sh` too. |
| `verify.sh` | Debug APK build gate with strict Gradle dependency verification (Maven Central by default). `REFRESH_NATIVE=1` is only relevant for the local-AAR override path. |
| `stage-sdk-aars.sh` | Optional. Builds local Kotlin SDK AARs into `libs/`; pair with `-Prunanywhere.useLocalSdkAars=true`. |
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
