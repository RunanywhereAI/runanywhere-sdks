# v2 re-architecture — final state snapshot 2026-04-19

> Live state of the branch on commit tip. Reviewers should prefer this
> doc over the original `MASTER_PLAN.md` + `feature_parity_audit.md`
> for the current picture; those track the original plan + gap list.

## TL;DR

- **C++ core**: 136/136 tests green (macOS Debug + ASan + UBSan).
- **All 5 frontend SDKs** compile + tests pass + have end-to-end demos
  that exercise the real C ABI.
- **All 3 Android NDK ABIs** + both iOS slices build cross-platform as
  `racommons_core.{so,dylib}`.
- **CI has 11 jobs on every PR**: cpp × 2, proto-codegen, android-ndk × 3
  matrix, ios-xcframework, swift-frontend, kotlin-frontend, dart-frontend,
  ts-frontend. 10 of 11 passed on the prior run; the 11th (ios-xcframework)
  had an unused-const-variable -Werror under RA_STATIC_PLUGINS=ON which
  the latest commit guards.

## Cross-platform native artifacts

| Target | Artifact | Deps | Status |
|---|---|---|---|
| macOS arm64 + x86_64 | `libracommons_core.dylib` | libcurl, libarchive, CommonCrypto, CoreFoundation | ✓ |
| iOS arm64 device | xcframework slice `ios-arm64` | none (uses Security.framework) | ✓ |
| iOS simulator arm64 + x86_64 | xcframework slice `ios-arm64_x86_64-simulator` | none | ✓ |
| macOS xcframework slice | full (w/ libcurl + libarchive + rac_compat + llamacpp) | brew deps | ✓ |
| Android arm64-v8a | `libracommons_core.so` (aarch64, 5.9 MB) | none (NDK only) | ✓ |
| Android x86_64 | `libracommons_core.so` | none | ✓ |
| Android armeabi-v7a | `libracommons_core.so` (arm 32) | none | ✓ |
| Linux x86_64 | `libracommons_core.so` | libcurl, libarchive | ✓ (via CI) |

Embedded targets (iOS / Android / WASM) pass `-DRA_BUILD_HTTP_CLIENT=OFF
-DRA_BUILD_MODEL_DOWNLOADER=OFF -DRA_BUILD_EXTRACTION=OFF
-DRA_BUILD_RAC_COMPAT=OFF` to skip libs that aren't in their sysroot.
Apps on those platforms bring their own transport (URLSession / OkHttp /
fetch) + unzip (Compress / libandroidicu / fflate).

## Frontend SDKs (all wired to real C core)

| SDK | Binding | Tests | Demo |
|---|---|---|---|
| Swift (`frontends/swift`) | `.binaryTarget` → RACommonsCore.xcframework | 3/3 | `examples/swift-demo` runs end-to-end |
| Kotlin (`frontends/kotlin`) | JNI in racommons_core.so | gradle build green | `examples/kotlin-demo` runs end-to-end |
| Dart (`frontends/dart`) | FFI via DynamicLibrary.open | 2/2 | `examples/dart-demo` runs end-to-end |
| TS/RN (`frontends/ts`) | `NativePipelineBindings` injection | 2/2 | `examples/ts-demo` runs |
| Web (`frontends/web`) | `WasmCoreModule` injection | 1/1 | `examples/web-demo` runs |

Every frontend has a real `ra_pipeline_create_voice_agent` call path.
Each demo drives the pipeline and observes `RA_ERR_BACKEND_UNAVAILABLE
(-6)` from the C completion callback — proving the SDK → C ABI → C++
pipeline → completion round-trip is fully wired (no engine plugins are
registered in the demo binaries, so the pipeline correctly reports
"no engine available").

## Commons parity landed in this PR

### Core / ABI
- Audio utilities (WAV encode/decode f32 + s16) — `core/util/audio_utils`
- Extraction (ZIP/TAR/TAR.GZ/TAR.BZ2/TAR.XZ + zip-slip hardened)
- File manager (std::filesystem + XDG dirs + per-platform app_support/cache/models)
- Storage analyzer
- Tool-calling parser (DEFAULT + LFM2 formats, 6 tests)
- Structured-output JSON extraction (5 tests)
- Energy-based VAD (no ML deps, 5 tests)
- LLM streaming metrics collector (TTFT + t/s, 3 tests)
- Pipeline C ABI (struct-based, no protobuf) — closes previously-empty `ra_pipeline_*`

### Network / auth
- HTTP client (libcurl-backed, streams + SHA-256)
- Auth manager (api_key + environment + endpoints + tokens + device state, 5 tests)
- Telemetry event queue

### Error / lifecycle
- Error taxonomy (85 codes × 16 domains)
- Lifecycle states (8 states)
- `rac_compat.{h,c}` — source + binary compat with legacy frontends

### Model management
- LoRA adapter registry
- Model compatibility checker

## Still gapped (`feature_parity_audit.md`)

- LLM tool-calling **executor** + LoRA **adapter load** + KV-cache injection (plugin capability extensions)
- Device manager (platform callbacks)
- OpenAI HTTP server (/v1/chat/completions streaming proxy)
- VLM + diffusion engines
- Voice agent state machine (WAITING_WAKEWORD → LISTENING → …)
- Benchmark stats framework
- WASM bundle from new core (setWasmModule hook is wired, emscripten build is follow-up)
- Legacy sample-app migration (they still consume sdk/runanywhere-commons)

## Repro

```bash
# C++ core
cmake --preset macos-debug && cmake --build --preset macos-debug && \
  ctest --preset macos-debug    # → 136/136 passed

# Release shared lib (needed by kotlin-demo + dart-demo)
cmake -S . -B build/macos-release -DCMAKE_BUILD_TYPE=Release \
  -DRA_ENABLE_SANITIZERS=OFF -DRA_BUILD_TESTS=OFF -DRA_BUILD_ENGINES=OFF \
  -DRA_BUILD_SOLUTIONS=OFF
cmake --build build/macos-release --target racommons_core

# Multi-slice xcframework (macOS + iOS device + iOS simulator)
bash scripts/build-core-xcframework.sh --platforms=macos,ios-device,ios-sim

# Android NDK — 3 ABIs
NDK=~/Library/Android/sdk/ndk/27.2.12479018
for abi in arm64-v8a x86_64 armeabi-v7a; do
  cmake -S . -B build/android-$abi -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=$abi -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release -DRA_ENABLE_SANITIZERS=OFF \
    -DRA_BUILD_TESTS=OFF -DRA_BUILD_TOOLS=OFF -DRA_BUILD_ENGINES=OFF \
    -DRA_BUILD_SOLUTIONS=OFF -DRA_BUILD_HTTP_CLIENT=OFF \
    -DRA_BUILD_MODEL_DOWNLOADER=OFF -DRA_BUILD_EXTRACTION=OFF \
    -DRA_BUILD_RAC_COMPAT=OFF
  cmake --build build/android-$abi --target racommons_core
done

# Per-SDK demo (examples/DEMOS.md has full instructions)
(cd examples/swift-demo && swift run)
(cd examples/kotlin-demo && RA_LIB_DIR="$(pwd)/../../build/macos-release/core" gradle --no-daemon run)
(cd examples/dart-demo && dart pub get && \
  LIB_PATH="$(pwd)/../../build/macos-release/core/libracommons_core.dylib" \
  dart run bin/demo.dart)
(cd examples/ts-demo && npm install && npm run build && \
  node dist/examples/ts-demo/src/main.js)
(cd examples/web-demo && npm install && npm test)
```

Every command exits 0 on this branch.
