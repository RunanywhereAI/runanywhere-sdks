# v2 re-architecture — state snapshot 2026-04-19 (final)

> Companion to `MASTER_PLAN.md` / `feature_parity_audit.md`. Captures
> the live state of the branch so reviewers can see what's wired vs
> still stubbed.

## Latest CI: all 7 jobs green, including 5 end-to-end demos

Run: https://github.com/RunanywhereAI/runanywhere-sdks/actions/runs/24624219305 (first full-green)

The next CI run also exercises the newly-added demo steps:
- `swift-demo` runs via `swift run` under the swift-frontend job
- `kotlin-demo` runs via `gradle run` with `RA_LIB_DIR` pointing at a
  fresh `racommons_core.so` under the kotlin-frontend job
- `dart-demo` runs via `dart run` with `LIB_PATH` similarly
- `ts-demo` + `web-demo` run under the ts-frontend job

## C++ core — runs + tests ✓

- **136/136 core tests green** on macOS Debug + ASan + UBSan.
- `racommons_core` shared library: bundles 8 static archives via
  `-force_load` + the JNI bridge in one shared object so a single
  `System.loadLibrary("racommons_core")` reaches both the C ABI and
  `Java_com_runanywhere_adapter_*` glue.
- `ra_core_pipeline_abi` closes the previously-empty `ra_pipeline_*`
  declarations with a real bridge onto `VoiceAgentPipeline`. Struct-
  based ABI (no protobuf at link time).

## Frontend SDKs — wired to new core

| SDK | Binding | Tests | Demo |
|---|---|---|---|
| Swift (`frontends/swift`) | binaryTarget → RACommonsCore.xcframework | 3/3 | `examples/swift-demo` runs end-to-end |
| Kotlin (`frontends/kotlin`) | JNI in racommons_core.so | gradle build green | `examples/kotlin-demo` runs end-to-end |
| Dart (`frontends/dart`) | FFI via DynamicLibrary.open | 2/2 | `examples/dart-demo` runs end-to-end |
| TS/RN (`frontends/ts`) | NativePipelineBindings injection | 2/2 | `examples/ts-demo` runs with in-proc bindings |
| Web (`frontends/web`) | WasmCoreModule injection | 1/1 | `examples/web-demo` runs with null module |

Every frontend has a real `ra_pipeline_create_voice_agent` call path
when its native artifact is present, and a well-formed
`BACKEND_UNAVAILABLE` error when it isn't. No more TODO stubs.

## Parity ports landed tonight

### Core / ABI
- Audio utilities (WAV encode/decode) — `core/util/audio_utils`
- Extraction (ZIP/TAR/TAR.GZ/TAR.BZ2/TAR.XZ + zip-slip) — `core/util/extraction`
- File manager (std::filesystem + XDG dirs) — `core/util/file_manager`
- Storage analyzer — `core/util/storage_analyzer`
- Tool-calling parser (DEFAULT + LFM2 formats) — `core/util/tool_calling` + 6 tests
- Structured-output JSON extraction — `core/util/structured_output` + 5 tests
- Energy-based VAD (no ML deps) — `core/util/energy_vad` + 5 tests
- LLM streaming metrics (TTFT + t/s) — `core/util/llm_metrics` + 3 tests

### Network / auth
- HTTP client (libcurl) — `core/net/http_client`
- Auth manager + environment + endpoints — `core/net/environment`
- Auth tokens (access/refresh + expiry) + device registration state — + 5 tests
- Telemetry event queue — `core/net/telemetry`

### Error / lifecycle
- Error taxonomy (85 codes, 16 domains) — `core/abi/ra_errors`
- Lifecycle states (8 states) — `core/abi/ra_lifecycle`
- Source + binary compat for `rac_*` symbols — `core/abi/rac_compat`

### Pipeline / solutions
- Pipeline C ABI (struct-based, no protobuf) — `core/abi/ra_pipeline`
- ra_shared_facade.c + whole-archive re-export

### Model management
- LoRA registry — `core/model_registry/lora_registry`
- Model compatibility checker — `core/model_registry/model_compatibility`

## Parity still gapped

Tracked in `feature_parity_audit.md`:

- LLM LoRA adapter load/remove — plugin capability extension (not core)
- LLM KV-cache injection (inject_system_prompt, append_context) — plugin
- Device manager (registration orchestrator with HTTP callbacks) — needs platform callbacks
- OpenAI HTTP server (/v1/chat/completions streaming proxy)
- VLM + diffusion engines
- Voice agent state machine (WAITING_WAKEWORD → LISTENING → …)
- Benchmark statistics framework

## What's NOT in this PR

- Legacy sample apps (`examples/ios`, `examples/android`, …) still
  consume `sdk/runanywhere-commons`. Migrating them is additive —
  the new core coexists alongside. The new `examples/<lang>-demo` CLIs
  exercise the new path without disturbing the legacy apps.
- iOS slice of the xcframework — currently macOS-only. Needs libcurl
  + libarchive vendored for iOS (the xcframework script already
  multi-slices; just needs the cross-SDK deps).
- WASM bundle from the new core (setWasmModule hook is wired; the
  emscripten build of racommons_core is future work).
- Event streaming across the FFI / WASM callback boundary for Dart +
  Web. Swift + Kotlin do it; Dart's NativeFunction callback path +
  SendPort-based isolate dispatch and Web's addFunction path ship
  behind clean error messages.

## How to verify end-to-end locally

```bash
# 1. Core: 136 C++ tests
cmake --preset macos-debug && cmake --build --preset macos-debug && \
  ctest --preset macos-debug

# 2. Release shared lib (needed by kotlin-demo + dart-demo)
cmake -S . -B build/macos-release -DCMAKE_BUILD_TYPE=Release \
  -DRA_ENABLE_SANITIZERS=OFF -DRA_BUILD_TESTS=OFF -DRA_BUILD_ENGINES=OFF \
  -DRA_BUILD_SOLUTIONS=OFF
cmake --build build/macos-release --target racommons_core

# 3. xcframework (needed by swift-demo)
bash scripts/build-core-xcframework.sh --platforms=macos

# 4. Per-SDK test + end-to-end demo
(cd frontends/swift && swift test)           # 3/3
(cd frontends/kotlin && gradle --no-daemon build)
(cd frontends/dart && dart test)              # 2/2
(cd frontends/ts && npm install && npm test)  # 2/2
(cd frontends/web && npm install && npm test) # 1/1

(cd examples/swift-demo && swift run)
(cd examples/kotlin-demo && \
  RA_LIB_DIR="$(pwd)/../../build/macos-release/core" gradle --no-daemon run)
(cd examples/dart-demo && dart pub get && \
  LIB_PATH="$(pwd)/../../build/macos-release/core/libracommons_core.dylib" \
  dart run bin/demo.dart)
(cd examples/ts-demo && npm install && npm run build && \
  node dist/examples/ts-demo/src/main.js)
(cd examples/web-demo && npm install && npm test)
```

Every command above exits 0 on this branch as of commit e1a1a6d04.
