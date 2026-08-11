# runanywhere-minimal (Kotlin / Android)

A single-Activity Android app — one button, one text view — that streams one LLM
completion. It is the contributor test harness for the Kotlin SDK: *"does my
C++/SDK change still work?"* — not a showcase app.

It is an Android app rather than a JVM console app because the Kotlin SDK ships
as an Android library (`com.android.library`) and its JNI core needs an Android
`Context` and a real device/emulator ABI.

## How it consumes the SDK

`settings.gradle.kts` pulls `sdk/runanywhere-kotlin` in as a **composite build**
(`includeBuild` + `dependencySubstitution`), so the app compiles against the SDK
**from local source** with no AAR staging step:

```
com.runanywhere:runanywhere-kotlin        -> project ':runanywhere-kotlin'
com.runanywhere:runanywhere-core-llamacpp -> project ':runanywhere-kotlin:modules:runanywhere-core-llamacpp'
```

Those coordinates are placeholders that exist only to be substituted; nothing is
ever resolved from a repository. Unlike the `files("../libs/*.aar")` approach the
full consumer app used before it moved to
[RunanywhereAI/runanywhere-android](https://github.com/RunanywhereAI/runanywhere-android), this also brings the SDK's
transitive runtime deps (coroutines, OkHttp, Wire) automatically, so the app
declares none of them — and there is no AAR staging step to re-run after an SDK
edit.

## Prerequisites

The SDK's `gradle.properties` sets `runanywhere.useLocalNatives=true`, so the
build wants the commons JNI `.so` files staged under
`sdk/runanywhere-kotlin/src/main/jniLibs/` and the backend module's
`modules/runanywhere-core-llamacpp/src/main/jniLibs/`. If they are already
present the build reuses them; if not, it shells out to the (slow) native build:

```bash
# From the repo root — only needed when the .so files are missing or stale.
./scripts/build/build-core-android.sh
```

You also need `local.properties` with `sdk.dir` (Android Studio writes it; it is
gitignored):

```bash
echo "sdk.dir=$HOME/Library/Android/sdk" > examples/kotlin/minimal/local.properties
```

## Run

```bash
cd examples/kotlin/minimal

# Build + install + launch on a connected arm64 device/emulator
./gradlew :app:installDebug
adb shell am start -n com.runanywhere.minimal/.MainActivity

# Or just compile (fastest gate after an SDK change)
./gradlew :app:compileDebugKotlin
```

Tap **Generate**. The first run downloads the model, so give it a minute and
watch `adb logcat`.

## What it exercises

| Step | API |
|------|-----|
| Backend registration | `LlamaCPP.register()` |
| SDK bring-up | `RunAnywhere.initialize(context = this)` |
| Catalog entry | `RunAnywhere.models.register(ModelRegistration.url(...))` |
| Streaming generation | `RunAnywhere.llm.generateStream(prompt, LlmOptions(...))` |

`initialize` is single-phase; there is no `completeServicesInitialization()`
call to make. **Download and load are automatic** — passing `LlmOptions.model`
is enough. The catalog is *not* auto-seeded, though: an unknown id is rejected
before generation, so the one `models.register` call is required. To try a
different model, change `MODEL_ID`/`MODEL_URL` in `MainActivity.kt` (the
canonical ids and URLs live in `sdk/runanywhere-cli/src/catalog/catalog.cpp`).

Deliberately absent: Compose, a design system, model catalogs, navigation.

## Note on the Kotlin version pin

`build.gradle.kts` applies `org.jetbrains.kotlin.plugin.serialization` 2.4.0
even though nothing here is `@Serializable`. AGP 9 supplies Kotlin itself
(applying `kotlin.android` is a hard error now) and its bundled compiler is
2.2.0, which cannot read the SDK's 2.4.0 metadata. Putting a 2.4.0 Kotlin
compiler plugin on the buildscript classpath pins the built-in compiler to
2.4.0 — the same trick `sdk/runanywhere-kotlin` itself uses.
