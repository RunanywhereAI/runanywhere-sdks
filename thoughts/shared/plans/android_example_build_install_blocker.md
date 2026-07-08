# Android Example Build/Install Blocker Plan

## Scope

- Android example app under `examples/android/RunAnywhereAI`.
- Kotlin/Android SDK under `sdk/runanywhere-kotlin` only if the reproduced blocker points to the staged AAR/API surface.
- Do not touch Swift, MLXRuntime, Flutter, React Native, Web, or C++ commons.
- Preserve existing staged edits and avoid reverting unrelated work.

## Initial Findings

- The Android example builds against staged local AARs in `examples/android/RunAnywhereAI/libs`.
- Existing staged changes already touch Android example model/LoRA files and Kotlin SDK LoRA/storage generated/API files.
- The example build uses AGP `9.2.1`, Kotlin `2.4.0`, Gradle `9.6.0`, and compile/target SDK `37`.
- `scripts/stage-sdk-aars.sh` builds/stages SDK AARs with `--max-workers=2`; the current `scripts/verify.sh` does not cap Gradle workers, so use the bounded command directly.
- `examples/android/RunAnywhereAI/libs/runanywhere-sdk.aar` is stale relative to the staged Kotlin SDK source: `javap` shows `LoRA` does not yet expose the new `apply(entry, localPath, scale, replaceExisting)` default method used by `LoraViewModel.kt`.

## MVP Steps

- [x] Inspect the staged diffs for the Android example and Kotlin SDK files already modified, focusing on likely compile/API mismatches.
- [x] Check system load with `uptime`, then build safely with `./gradlew :app:assembleRelease --max-workers=16` from `examples/android/RunAnywhereAI`.
- [x] Fix the smallest in-scope blocker:
  - Prefer Android example source/build configuration fixes.
  - Touch Kotlin SDK only if the error is caused by the SDK API/AAR shape.
  - Use generated proto types and structured constants rather than raw strings.
- [x] Update this plan with exact changes made and handoff notes.
- [x] Re-run `./gradlew :app:assembleRelease --max-workers=16` and report the result.

## Notes

- Do not run unit tests unless separately requested.
- Do not run native rebuilds unless the failure proves they are required; if needed, keep them sequential and bounded.

## Handoff Notes

- User updated resource guidance to use full local capacity. `AGENTS.md` now recommends host CPU-count worker settings instead of a fixed `--max-workers=2` cap.
- Restaged release Android SDK AARs with `./scripts/stage-sdk-aars.sh release --max-workers=16` from `examples/android/RunAnywhereAI`; build succeeded and refreshed `libs/runanywhere-*.aar`.
- Verified refreshed `runanywhere-sdk.aar` exposes `LoRA.apply(LoraAdapterCatalogEntry, String?, Float?, Boolean)` via `javap`.
- Built Android release APK with `./gradlew :app:assembleRelease --max-workers=16`; build succeeded.
- Installed `examples/android/RunAnywhereAI/app/build/outputs/apk/release/app-release.apk` on connected device `8977b1dd` with `adb install -r`; install succeeded.
- Launched the app via adb and confirmed `com.runanywhere.runanywhereai/.MainActivity` is resumed.
