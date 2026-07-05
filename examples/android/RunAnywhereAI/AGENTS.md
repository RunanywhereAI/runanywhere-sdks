# Android Example App (RunAnywhereAI)

## Info

Kotlin/Jetpack Compose demo app for the RunAnywhere SDK (single `:app` module, `com.runanywhere.runanywhereai`). Source under `app/src/main/java/com/runanywhere/runanywhereai/`: `RunAnywhereApplication.kt` (SDK init + backend/model registration), `MainActivity.kt`, plus `ui/`, `data/`, `state/`, `tools/`, `util/`.

Example apps are UI-only: thin `RunAnywhere.*` SDK calls, no business logic, no SDK-internal knowledge. Global rules: see repo-root AGENTS.md.

- Consumes the Kotlin SDK as flat AARs from `libs/` (`runanywhere-sdk.aar`, `runanywhere-llamacpp.aar`, `runanywhere-onnx.aar`) referenced via `files(...)` in `app/build.gradle.kts`. The AARs are built from `sdk/runanywhere-kotlin/` and copied in by `scripts/examples/android/stage-sdk-aars.sh` (what `./run example android stage` runs).
- Repositories include `mavenLocal()` and JitPack (SDK transitive deps: android-vad, PRDownloader).
- `local.properties` keys `runanywhere.baseUrl` / `runanywhere.apiKey` are injected as `BuildConfig` fields.
- minSdk 24, targetSdk 37.

## Build Info

```bash
# From repo root (dev entry point) — stage rebuilds SDK AARs then copies to libs/
./run example android stage      # scripts/examples/android/stage-sdk-aars.sh release
./run example android build      # stage + :app:assembleDebug
./run example android install    # stage + :app:installDebug + launch via adb
./run example android lint       # :app:ktlintCheck :app:detekt
./run example android clean

# Direct Gradle (from examples/android/RunAnywhereAI/)
./gradlew :app:assembleDebug
./gradlew :app:installDebug

# Verification (scripts live under repo-root scripts/)
../../../scripts/examples/android/verify.sh
../../../scripts/examples/android/smoke.sh

# After C++ commons changes (repo root) — then re-stage
./run sdk commons build-android      # scripts/build/android.sh (.so into SDK jniLibs/)
./run example android stage
```

Re-run `build-android` + `stage` after any change to C++ commons or the Kotlin SDK — the app builds against the staged AAR snapshot, not live SDK sources. Gradle: `--max-workers=2` per repo resource rules.

## Work Ground

Short dated notes for other agents. Add gotchas here; prune stale ones.

- 2026-07-05: `example android stage` always builds the release AAR variant by default; pass `debug` to `stage-sdk-aars.sh` directly if you need debug symbols in the SDK.
- 2026-07-05: Flat-file AARs do not carry transitive deps — the app declares SDK runtime deps (coroutines, serialization, etc.) itself in `app/build.gradle.kts`; missing-class runtime crashes usually mean a new SDK dep needs adding there.
- 2026-07-05: Wireless ADB to the test phone drops to "Android null" — recover with adb kill-server / start-server / reconnect.
