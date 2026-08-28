# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this app is

A single-Activity Android app — one button, one text view — that streams one LLM
completion. It is the **contributor test harness for the Kotlin SDK** ("does my
C++/SDK change still work?"), not a showcase app. Deliberately absent: Compose, a
design system, model catalogs, navigation. The full-featured consumer app lives in a
separate repo, [runanywhere-android](https://github.com/RunanywhereAI/runanywhere-android).

It is an Android app rather than a JVM console app because the Kotlin SDK ships as
an Android library (`com.android.library`) and its JNI core needs an Android
`Context` and a real device/emulator ABI.

## How it consumes the SDK

`settings.gradle.kts` pulls `bindings/kotlin` in as a **composite build**
(`includeBuild` + `dependencySubstitution`), so the app compiles against the SDK
**from local source** with no AAR staging step and no repository resolution:

```
com.runanywhere:runanywhere-kotlin        -> project ':runanywhere-kotlin'
com.runanywhere:runanywhere-core-llamacpp -> project ':runanywhere-kotlin:modules:runanywhere-core-llamacpp'
```

Those coordinates in `app/build.gradle.kts` are placeholders that exist only to be
substituted. This also pulls in the SDK's transitive runtime deps (coroutines,
OkHttp, Wire) automatically — the app declares none of them, and there is no AAR
staging step to re-run after an SDK edit.

## Commands

```bash
cd bindings/kotlin/example

# Build + install + launch on a connected arm64 device/emulator
./gradlew :app:installDebug
adb shell am start -n com.runanywhere.minimal/.MainActivity

# Compile only — fastest gate after an SDK change
./gradlew :app:compileDebugKotlin

./gradlew clean
```

Or, from the repo root, `./run example android {build|install|clean}` (defined in
the root `./run` script) does the same and additionally starts the activity for you
after `install`.

## Prerequisites

- `local.properties` with `sdk.dir` (Android Studio writes it; gitignored):
  ```bash
  echo "sdk.dir=$HOME/Library/Android/sdk" > bindings/kotlin/example/local.properties
  ```
- The SDK's `gradle.properties` sets `runanywhere.useLocalNatives=true`, so the
  build wants the commons JNI `.so` files already staged under
  `bindings/kotlin/src/main/jniLibs/` and
  `bindings/kotlin/modules/runanywhere-core-llamacpp/src/main/jniLibs/`. If present,
  the build reuses them; if not, it shells out to the slow native build:
  ```bash
  ./scripts/build/build-core-android.sh   # from the repo root
  ```

Tap **Generate**. The first run downloads the model, so give it a minute and watch
`adb logcat`.

## What it exercises

| Step | API |
|------|-----|
| Backend registration | `LlamaCPP.register()` |
| SDK bring-up | `RunAnywhere.initialize(context = this)` |
| Catalog entry | `RunAnywhere.models.register(ModelRegistration.url(...))` |
| Streaming generation | `RunAnywhere.llm.generateStream(prompt, LlmOptions(...))` |

`initialize` here is single-phase from the caller's perspective — there is no
explicit `completeServicesInitialization()` call in `MainActivity`; download and
load are automatic, so passing `LlmOptions.model` is enough. The catalog is *not*
auto-seeded, though: an unknown id is rejected before generation, so the one
`models.register` call in `bootstrap` (in `MainActivity.onCreate`) is required. To
try a different model, change `MODEL_ID`/`MODEL_URL` at the top of
`app/src/main/java/com/runanywhere/minimal/MainActivity.kt` (the canonical ids and
URLs live in the [RCLI](https://github.com/RunanywhereAI/RCLI) catalog (`src/catalog/catalog.cpp`).

## Source layout

Everything is in `app/`: `build.gradle.kts` (namespace
`com.runanywhere.minimal`, `arm64-v8a`-only to keep the APK small),
`src/main/AndroidManifest.xml`, and the single `MainActivity.kt`. There is no other
Kotlin source in this module — resist adding a second Activity, a view model, or a
DI framework here; that complexity belongs in the consumer app repo, not the SDK
test harness.

## Gotcha: the Kotlin version pin

`build.gradle.kts` (root of this module, not `app/`) applies
`org.jetbrains.kotlin.plugin.serialization` version 2.4.0 even though nothing here
is `@Serializable`. AGP 9 supplies Kotlin itself (applying `kotlin.android` directly
is a hard error now), and its bundled compiler is 2.2.0, which cannot read the SDK's
2.4.0 metadata. Putting a 2.4.0 Kotlin compiler plugin on the buildscript classpath
pins the built-in compiler to 2.4.0 instead — the same trick `bindings/kotlin`
itself uses. `app/build.gradle.kts` applies the same plugin for the same reason.
Removing either occurrence reintroduces "Module was compiled with an incompatible
version of Kotlin".
