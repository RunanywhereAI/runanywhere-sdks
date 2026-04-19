# Kotlin SDK — migration plan

> `sdk/runanywhere-kotlin/` is a Kotlin Multiplatform project with JVM +
> Android targets. The Android build links `jniLibs/<abi>/librunanywhere_commons.so`
> produced by cross-compiling `sdk/runanywhere-commons/` against each
> Android ABI. The JVM build packages a similar shared library.
>
> **Goal of this migration:** the native `.so` is rebuilt from the new
> `core/` + `engines/` trees, with the JNI bridge rewritten to call
> `ra_*` entry points instead of the legacy `rac_*`. The Kotlin
> public API surface stays identical.

## Step 1 — Current interop layer

- `sdk/runanywhere-kotlin/modules/runanywhere-core/src/androidMain/cpp/runanywhere_commons_jni.cpp`
  — ~4,800 LOC of JNI bridge calling `rac_*` from Java land.
- `sdk/runanywhere-kotlin/modules/runanywhere-core-llamacpp/src/jvmMain/cpp/`
  — llama.cpp-specific JNI glue.
- Java/Kotlin classes that load those libraries via `System.loadLibrary`.

## Step 2 — Symbol inventory

Every `rac_*` called from JNI is listed in `runanywhere_commons_jni.cpp`.
The registry approach mirrors Swift — group by primitive + lifecycle +
infrastructure + events + errors + network + download.

## Step 3 — ABI mapping

One-time generation of a `rac_compat.h` header (same idea as Swift),
plus C glue for call-shape differences. Because the JNI bridge is in
C++, inline wrappers or `constexpr auto* rac_llm_generate = &ra_llm_generate;`
work cleanly.

Special attention to:
- Callback adapter signatures — the legacy JNI signals via
  `rac_event_callback_t`; the new ABI uses streams. JNI bridge polls
  streams and posts per-event to Java via `JNIEnv::CallVoidMethod`.
- Stream completion signal — new ABI closes streams; JNI emits a
  terminal "done" event to Java.

## Step 4 — Native artifact

`sdk/runanywhere-kotlin/scripts/build-core-aar.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
ANDROID_NDK=${ANDROID_NDK:-$HOME/Library/Android/sdk/ndk/26.3.11579264}

for abi in arm64-v8a armeabi-v7a x86_64; do
    cmake -S ${ROOT} -B build/android-${abi} \
        -DCMAKE_TOOLCHAIN_FILE=${ANDROID_NDK}/build/cmake/android.toolchain.cmake \
        -DANDROID_ABI=${abi} \
        -DANDROID_PLATFORM=24 \
        -DRA_BUILD_TESTS=OFF \
        -DRA_BUILD_TOOLS=OFF \
        -DRA_STATIC_PLUGINS=OFF
    cmake --build build/android-${abi} --config Release

    mkdir -p sdk/runanywhere-kotlin/modules/runanywhere-core/src/androidMain/jniLibs/${abi}
    cp build/android-${abi}/core/libra_core.so \
       build/android-${abi}/engines/llamacpp/librunanywhere_llamacpp.so \
       build/android-${abi}/engines/sherpa/librunanywhere_sherpa.so \
       sdk/runanywhere-kotlin/modules/runanywhere-core/src/androidMain/jniLibs/${abi}/
done
```

The JVM target uses the host-compiled `.dylib`/`.so`/`.dll` placed in
`src/jvmMain/resources/<platform>/`.

## Step 5 — Wire the interop layer

Replace `runanywhere_commons_jni.cpp` with
`runanywhere_core_jni.cpp` that maps every Java_com_runanywhere_* JNI
entry point onto the new ABI. Same class name exposure; new native
implementation.

## Step 6 — Run the SDK's own tests

```
cd sdk/runanywhere-kotlin
./scripts/sdk.sh test
```

JVM + Android instrumented tests should stay green.

## Step 7 — Run the example app

```
cd examples/android/RunAnywhereAI
./gradlew installDebug
```

Verify chat + voice agent + model download flows on an emulator.

## Known risks

- **NDK version** pinning — the new core's llama.cpp FetchContent step
  needs a specific NDK range. Document in `local.properties.example`.
- **16 KB page-alignment** enforced by Play Store — linker flags must
  match what legacy commons set.
- **JNI thread attach** for async callbacks — keep the same attach/detach
  patterns from the legacy bridge.
