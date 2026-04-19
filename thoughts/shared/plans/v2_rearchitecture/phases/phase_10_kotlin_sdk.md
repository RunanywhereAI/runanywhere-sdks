# Phase 10 — Kotlin Multiplatform SDK migration + Android example app

> Goal: rewire `sdk/runanywhere-kotlin/` onto the new commons C ABI
> + proto3 wire types via JNI. Absorb any residual
> `sdk/runanywhere-android/` responsibilities into KMP
> (Android-specific code lives under `androidMain/`). Rewrite the
> Android example app. Keep IntelliJ plugin demo building.

---

## Prerequisites

- Phase 9 (Swift SDK) either merged or at least validated the
  XCFramework pipeline. Not strictly blocking, but confirms the
  shape.
- Phase 7 produced Android `.so` plugin files; Phase 10 consumes
  them through KMP's Android target.
- `sdk/runanywhere-android/` does not currently exist as a separate
  module — the CLAUDE.md mention was pre-consolidation. This phase
  ratifies the KMP-only structure.

---

## What this phase delivers

1. **Wire-protobuf codegen** in the common module from
   `sdk/runanywhere-commons/idl/*.proto` into
   `modules/core/src/commonMain/kotlin/ra/idl/`. We use **Wire 5.x**
   (Square) for its smaller runtime, multiplatform support
   (commonMain-friendly), and explicit nullability (better than
   `protobuf-kotlin`'s `has_*` story for proto3).

2. **New Android JNI bridge** under `modules/core/src/androidMain/`
   that links the commons Android `.so` + plugin `.so`s, exposes
   `external fun` functions returning/accepting `ByteArray` (the
   length-prefixed proto bytes).

3. **New JVM JNI bridge** under `modules/core/src/jvmMain/` for
   desktop / IntelliJ plugin consumers, using the commons
   `.dylib`/`.so` built for host desktop.

4. **Actor-like public API** via `Flow<T>` for streams and `suspend
   fun` for one-shots — matches the existing CLAUDE.md guidance
   and KMP conventions.

5. **Rewritten Android example app** at
   `examples/android/RunAnywhereAI/` on the new SDK. Compose UI.

6. **IntelliJ plugin demo updated** at
   `examples/intellij-plugin-demo/` consuming the JVM artifact.

7. **Delete every remaining old service/callback API** under
   `sdk/runanywhere-kotlin/`. Full rewrite of the public surface
   where needed, no deprecation shims.

---

## Exact file-level deliverables

### KMP module structure

```text
sdk/runanywhere-kotlin/
├── modules/
│   ├── core/
│   │   ├── build.gradle.kts                UPDATED — Wire plugin, strict concurrency
│   │   └── src/
│   │       ├── commonMain/kotlin/com/runanywhere/
│   │       │   ├── RunAnywhere.kt              top-level; coroutine scope, bootstrap()
│   │       │   ├── core/
│   │       │   │   └── RABridge.kt             expect class declarations
│   │       │   ├── llm/
│   │       │   │   ├── LLMSession.kt           suspend + Flow<LLMEvent>
│   │       │   │   ├── LLMEvent.kt             sealed class
│   │       │   │   └── LLMConfiguration.kt
│   │       │   ├── stt/, tts/, vad/, vlm/, rag/, voice_agent/, wake_word/, download/, observability/
│   │       │   ├── proto/                      wire-generated; gitignored
│   │       │   │   └── (Ra_Idl_*.kt)
│   │       │   └── util/
│   │       │       └── RAError.kt              sealed class
│   │       ├── commonTest/kotlin/…
│   │       ├── androidMain/kotlin/com/runanywhere/core/
│   │       │   └── RABridgeAndroid.kt          actual class — loads .so, JNI calls
│   │       ├── androidMain/cpp/
│   │       │   └── ra_jni_bridge.cpp           NEW — C++ JNI stubs that call ra_* ABI
│   │       ├── androidMain/AndroidManifest.xml
│   │       ├── jvmMain/kotlin/com/runanywhere/core/
│   │       │   └── RABridgeJvm.kt              actual class — JNA or JNI via System.load
│   │       └── jvmMain/cpp/
│   │           └── ra_jni_bridge.cpp           shared w/ android via build.gradle `srcDir`
│   ├── whisper/                                existing external module
│   ├── llama/                                  existing external module
│   └── …                                       other feature modules migrate inside
├── build.gradle.kts                             UPDATED — Kotlin 2.1.21, Gradle 8.11.1, JVM 17
├── settings.gradle.kts
├── gradle.properties                            UPDATED — kotlin.code.style=official
└── scripts/
    ├── sdk.sh                                   UPDATED — new build steps
    ├── build-commons-android.sh                 NEW — builds commons .so for 4 Android ABIs
    ├── build-commons-jvm.sh                     NEW — builds commons .dylib/.so for host
    └── codegen-proto.sh                         NEW — runs `wire-compiler` on idl/
```

### `build.gradle.kts` (module/core) key shape

```kotlin
plugins {
    kotlin("multiplatform") version "2.1.21"
    id("com.android.library") version "8.7.0"
    id("com.squareup.wire") version "5.0.0"
}

kotlin {
    androidTarget { publishLibraryVariants("release") }
    jvm()
    // iOS / macOS targets intentionally omitted — Swift SDK owns Apple
    // platforms. If we need KMP-on-iOS later, re-enable here.

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation("com.squareup.wire:wire-runtime:5.0.0")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("androidx.core:core-ktx:1.13.1")
            }
        }
    }
}

wire {
    sourcePath {
        srcDir("../../../../sdk/runanywhere-commons/idl")
    }
    kotlin {
        out = "${layout.buildDirectory.get().asFile}/generated/source/wire/commonMain"
    }
}

android {
    namespace = "com.runanywhere.core"
    compileSdk = 36
    defaultConfig {
        minSdk = 24
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DRA_STATIC_PLUGINS=OFF",      // Android dlopens
                    "-DANDROID_STL=c++_shared"
                )
            }
        }
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64") }
    }
    externalNativeBuild {
        cmake {
            path = file("src/androidMain/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
}
```

### Example expect/actual bridge

`commonMain/RABridge.kt`:

```kotlin
expect object RABridge {
    fun llmCreate(cfgBytes: ByteArray): Long           // returns session handle (pointer as long)
    fun llmDestroy(handle: Long)
    fun llmStart(handle: Long, promptBytes: ByteArray)
    fun llmNext(handle: Long): ByteArray?              // null = stream closed
    fun llmCancel(handle: Long)
    // …same shape for STT, TTS, VAD, VLM, RAG, VoiceAgent…
}
```

`androidMain/RABridgeAndroid.kt`:

```kotlin
actual object RABridge {
    init {
        System.loadLibrary("ra_jni_bridge")   // pulls in libcommons.so via its rpath
    }

    external actual fun llmCreate(cfgBytes: ByteArray): Long
    external actual fun llmDestroy(handle: Long)
    external actual fun llmStart(handle: Long, promptBytes: ByteArray)
    external actual fun llmNext(handle: Long): ByteArray?
    external actual fun llmCancel(handle: Long)
    // …
}
```

`androidMain/cpp/ra_jni_bridge.cpp`:

```cpp
#include <jni.h>
#include "rac/abi/ra_llm.h"

extern "C" JNIEXPORT jlong JNICALL
Java_com_runanywhere_core_RABridge_llmCreate(JNIEnv* env, jobject, jbyteArray cfgBytes) {
    jsize len = env->GetArrayLength(cfgBytes);
    jbyte* data = env->GetByteArrayElements(cfgBytes, nullptr);
    ra_llm_session_t* session = nullptr;
    ra_status_t st = ra_llm_create(reinterpret_cast<const uint8_t*>(data),
                                   static_cast<size_t>(len),
                                   &session);
    env->ReleaseByteArrayElements(cfgBytes, data, JNI_ABORT);
    if (st != RA_STATUS_OK) {
        throw_ra_exception(env, st);
        return 0;
    }
    return reinterpret_cast<jlong>(session);
}

// …matching stubs for every ra_* function…
```

### Public `LLMSession` shape

```kotlin
class LLMSession private constructor(private val handle: Long) : AutoCloseable {

    companion object {
        suspend fun create(configuration: LLMConfiguration): LLMSession =
            withContext(Dispatchers.IO) {
                val bytes = configuration.toProto().encode()
                LLMSession(RABridge.llmCreate(bytes))
            }
    }

    fun generate(prompt: Prompt): Flow<LLMEvent> = flow {
        RABridge.llmStart(handle, prompt.toProto().encode())
        while (currentCoroutineContext().isActive) {
            val bytes = RABridge.llmNext(handle) ?: break
            val ev = Ra_Idl_LlmEvent.ADAPTER.decode(bytes)
            val mapped = LLMEvent.from(ev) ?: continue
            emit(mapped)
            if (mapped is LLMEvent.End) break
        }
    }.flowOn(Dispatchers.IO)
        .onCompletion { cause ->
            if (cause is CancellationException) RABridge.llmCancel(handle)
        }

    override fun close() {
        RABridge.llmDestroy(handle)
    }
}
```

### Android example app (examples/android/RunAnywhereAI/)

```text
examples/android/RunAnywhereAI/
├── app/build.gradle.kts            UPDATED — depends on sdk/runanywhere-kotlin maven-local
├── app/src/main/
│   ├── AndroidManifest.xml
│   ├── java/com/runanywhere/ai/
│   │   ├── RunAnywhereApp.kt       @HiltAndroidApp (or DI of choice)
│   │   ├── MainActivity.kt         Compose host
│   │   └── ui/
│   │       ├── ChatScreen.kt       — collectAsState(llmSession.generate(…))
│   │       ├── VoiceAgentScreen.kt
│   │       └── SettingsScreen.kt
│   └── cpp/ (none — app doesn't reach into JNI; only SDK does)
├── build.gradle.kts
└── settings.gradle.kts
```

### IntelliJ plugin demo (examples/intellij-plugin-demo/)

```text
examples/intellij-plugin-demo/
├── build.gradle.kts                UPDATED — depends on RunAnywhereKotlinSDK-jvm via mavenLocal
├── src/main/kotlin/…
└── plugin.xml                       UPDATED — new action names, same UX
```

### Deletions

```text
sdk/runanywhere-android/                       — if any leftover files exist, delete now
sdk/runanywhere-kotlin/modules/*/src/.../Old*  — pre-refactor service / provider classes
sdk/runanywhere-kotlin/modules/*/src/.../*Impl.kt — generic Impl suffix files superseded
sdk/runanywhere-kotlin/src/commonMain/kotlin/.../ModuleRegistry.kt — plugin registration now happens in commons
```

The `ModuleRegistry` pattern described in CLAUDE.md moves entirely
into commons' `PluginRegistry`. Kotlin side just consumes the
registered engines; it doesn't register them. One less thing for
frontend developers to wire up per module.

### Tests

```text
modules/core/src/commonTest/kotlin/
  ├── LLMSessionTest.kt
  ├── STTFlowTest.kt
  ├── VoiceAgentTest.kt
  ├── RAGPipelineTest.kt
  └── BridgeRoundTripTest.kt

modules/core/src/androidTest/kotlin/
  └── JniLibraryLoadTest.kt                — verifies System.loadLibrary resolves

modules/core/src/jvmTest/kotlin/
  └── JniLibraryLoadTest.kt                — same for desktop variant
```

---

## Implementation order

1. **Build commons .so for 4 Android ABIs** via
   `scripts/build-commons-android.sh` that invokes the commons CMake
   with the Android NDK toolchain. Confirm each `.so` opens via
   `dlopen` on a device.

2. **Build commons .dylib / .so for JVM host** via
   `scripts/build-commons-jvm.sh`. Confirm JNA / JNI can reach it.

3. **Integrate Wire**. Generate one proto, inspect the output, confirm
   the Kotlin class names align with our expectations (`Ra_Idl_LlmConfig`).

4. **Write the JNI bridge in C++** one primitive at a time. LLM first.
   Compile, run from an androidMain unit test, round-trip one `Token`.

5. **Write `RABridgeAndroid` + `RABridgeJvm`** actuals. Same
   signatures; different `System.loadLibrary` names.

6. **Port the common module public API** primitive-by-primitive to
   the new Flow-based shape. Delete old `Component` classes and the
   `ModuleRegistry` abstraction (now unnecessary).

7. **Migrate every existing test** to the new API. Drop mock providers
   that existed to satisfy the old `STTServiceProvider` interface.

8. **Rewrite the Android example app.** Fresh Compose project,
   depends on `com.runanywhere.sdk:RunAnywhereKotlinSDK-android` from
   maven-local. Port each screen.

9. **Update the IntelliJ plugin demo.** Update dependencies to the
   new SDK. Port whatever small surface it consumes (voice capture +
   LLM dictation).

10. **Android CI**: update `.github/workflows/android-sdk.yml` and
    `android-app.yml` to match the new build outputs.

---

## API changes

### New public Kotlin API

| Old | New |
| --- | --- |
| `STTComponent(config).apply { initialize() }` | `STTSession.create(configuration)` |
| `llmComponent.generate(prompt) { tok → … }` | `llmSession.generate(prompt).collect { ev → … }` |
| `VoiceAgentComponent` | `VoiceAgent.create(configuration)` + Flow |
| `EventBus.componentEvents` | lifecycle Flows on each session — no central bus |
| `ServiceContainer.shared` | `RunAnywhere.bootstrap(applicationContext)` returns the DI graph |
| `ModuleRegistry.registerSTT(…)` | deleted — backends register through commons PluginRegistry |

### Removed

- `BaseComponent`, `Component`, `ComponentState`, `ComponentHealth`
  — KMP-specific lifecycle abstraction superseded by structured
  concurrency (`suspend fun close()`, `AutoCloseable`).
- `ServiceContainer` — replaced by a lighter `RunAnywhere` singleton
  (holds the one `CoroutineScope` we care about).
- `EventBus` — per-session Flows replace it.
- Any `Impl`-suffixed class in platform source sets.
- Legacy callback interfaces (`STTCallback`, `TTSCallback`, etc.).

---

## Acceptance criteria

- [ ] `./scripts/sdk.sh build-all --clean` green: produces
      `RunAnywhereKotlinSDK-jvm-2.0.0.jar` and
      `RunAnywhereKotlinSDK-android-2.0.0.aar`.
- [ ] `./scripts/sdk.sh test` green on JVM and Android instrumented
      tests.
- [ ] `detekt` + lint green.
- [ ] Android example app builds and runs on a physical arm64
      Android device; chat + voice agent flows work end to end.
- [ ] IntelliJ plugin demo loads in the sandbox IDE and the voice
      feature still works.
- [ ] AAR size ≤ 60 MB per ABI slice (mostly plugin `.so` payload).
- [ ] `.github/workflows/android-sdk.yml` + `android-app.yml` green.
- [ ] `grep -rn "ModuleRegistry\|ServiceContainer\|BaseComponent" sdk/runanywhere-kotlin/`
      returns empty.
- [ ] No `NSLock` (the rule applies to Swift; its Kotlin analogue is
      "no `java.util.concurrent.locks.ReentrantLock` in hot paths;
      use coroutine primitives"). grep gate enforced.

## Validation checkpoint — frontend major

See `testing_strategy.md`. Phase 10 runs the common frontend
gates plus:

- **Compilation, all targets.**
  ```bash
  cd sdk/runanywhere-kotlin
  ./scripts/sdk.sh build-all --clean                            # JVM JAR + Android AAR
  ./scripts/sdk.sh jvm                                          # JVM only
  ./scripts/sdk.sh android                                      # Android only
  ./scripts/sdk.sh test                                         # unit + instrumented
  ./scripts/sdk.sh publish-local                                # Maven Local publish
  ```
  All exit 0 with **zero new lint warnings**. Kotlin compiler
  warnings cleared in-PR; `-Werror` not mandatory yet but any
  new warning must be justified.
- **detekt + ktlint green.** Full ruleset from `detekt.yml`.
  Android lint (`./gradlew lint`) green.
- **Tests green.**
  - JVM: `./gradlew :modules:core:jvmTest`
  - Android unit: `./gradlew :modules:core:testDebugUnitTest`
  - Android instrumented on emulator: `./gradlew connectedAndroidTest`
- **JNI library load smoke.** On both Android emulator and JVM
  desktop, `System.loadLibrary("ra_jni_bridge")` succeeds and a
  round-trip `ra_status_string(0)` returns `"OK"`.
- **Commons `.so` ABI coverage.** arm64-v8a, armeabi-v7a, x86_64
  all present in the AAR's `jniLibs/`. `unzip -l` shows all three.
- **Android example app builds + runs from clean clone.** Launch
  on emulator + physical Pixel arm64. Chat + voice agent smoke.
- **IntelliJ plugin demo builds + loads.** `./gradlew runIde`
  opens the sandbox; the plugin action list includes the
  voice-feature entries; one voice capture round-trip works.
- **Feature parity.** Every feature the Kotlin SDK supported
  pre-Phase-10 works post-Phase-10, through the new Flow-based
  API.
- **Maven Local publish smoke.** An external Gradle consumer
  project depends on the just-published artifact and compiles.
- **CI.** `.github/workflows/android-sdk.yml`,
  `android-app.yml` green.

**Fix-as-you-go rule strictly enforced**: warnings introduced
by the rewrite are fixed in this phase's PRs, not a cleanup
phase.

---

## What this phase does NOT do

- No KMP iOS target resurrection. Apple platforms are Swift-only as
  of this plan; resurrecting the KMP iOS target is a future project.
- No Wire-to-Proto3 feature parity check beyond the messages we
  actually use. If a proto3 feature (e.g. `Any`) is never sent across
  the ABI, we don't need Wire to support it.
- No migration for side-modules that aren't core (e.g. telemetry
  exporters). They follow the same pattern post-phase if they need to
  touch commons.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| JNI ByteArray copy on every `llmNext` adds measurable latency | Medium | For the hot token path, add a DirectByteBuffer fast-path in the JNI layer. Benchmark both; keep whichever is faster |
| Wire 5.x doesn't yet support a proto3 feature we rely on | Low | Wire's proto3 support is mature. If we hit a gap, fall back to `protobuf-kotlin` (Google) on a per-message basis behind the same Kotlin interface |
| Android NDK version drift breaks commons build inside the KMP CMake step | Medium | Pin NDK version in `local.properties` and in `build-commons-android.sh`. CI sets `ANDROID_NDK_ROOT` to the pinned version |
| IntelliJ plugin classloader isolation fights JNI `System.loadLibrary` | Medium | Load the desktop commons `.dylib`/`.so` via a JVM-agent bootstrap that runs before the plugin class loads. Documented pattern |
| Android `System.loadLibrary` fails if our `.so` transitively depends on `libc++_shared.so` that the host app also ships, mismatched versions | Medium | Compile commons with `c++_shared` from the NDK we pin. AAR bundles `libc++_shared.so` via `ndk.abiFilters` + `packagingOptions.jniLibs.pickFirsts` |
| Absorbing any residual `runanywhere-android/` leaves dead Gradle settings in the root | Low | The delete sweep is grep-gated; fix in passing |
| Coroutine scope leaks when a `Flow` is cancelled but the C ABI session isn't `destroy`'d | Medium | Every `generate(...)` flow pairs with an `onCompletion { destroy() }` or `AutoCloseable` wrapper on the session — tested explicitly |
| Wire generator's Kotlin package names differ from swift-protobuf's Swift ones; cross-SDK docs get confusing | Low | Document the mapping in `docs/proto3_wire_format.md` (commons side) |
