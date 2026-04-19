# v2 re-architecture — state snapshot 2026-04-19

> Companion to `MASTER_PLAN.md` / `feature_parity_audit.md`. This file
> captures the live state of the branch at a specific commit so reviewers
> can see what's wired vs stubbed without running the CI.

## C++ core — runs + tests ✓

- **136/136 core tests green** on macOS Debug (ASan + UBSan).
- `racommons_core` shared library built: `build/<preset>/core/libracommons_core.dylib`.
  Bundles 8 static archives via `-force_load` and re-exports every
  `ra_pipeline_*`, `ra_llm_*`, `rac_*` symbol in one dlopen. Also bundles
  the JNI bridge so `System.loadLibrary("racommons_core")` reaches both
  the C ABI and Java_com_runanywhere_adapter_* glue.
- `ra_core_pipeline_abi` closes the previously-empty `ra_pipeline_*`
  declarations with a real bridge onto `VoiceAgentPipeline`. Struct-based
  ABI (no protobuf at link time).

## Frontend SDKs — wired to new core

| SDK | Binding | State | Test command |
|---|---|---|---|
| Swift (`frontends/swift`) | binaryTarget → RACommonsCore.xcframework | 3/3 tests green | `swift test` |
| Kotlin (`frontends/kotlin`) | JNI bridge in racommons_core.so | gradle build green | `gradle build` |
| Dart (`frontends/dart`) | FFI via DynamicLibrary.open | 2/2 tests green | `dart test` |
| TS/RN (`frontends/ts`) | NativePipelineBindings injection | 2/2 tests green | `npm test` |
| Web (`frontends/web`) | WasmCoreModule injection | 1/1 tests green | `npm test` |

Every frontend has a **real call path into the C core** when its native
artifact is present, and a well-defined `BACKEND_UNAVAILABLE` error path
when it isn't. No more TODO stubs in VoiceSession.

## Feature parity vs sdk/runanywhere-commons — closed tonight

### Core / ABI
- Audio utilities (WAV encode/decode) — `core/util/audio_utils.{h,cpp}`
- Extraction (ZIP/TAR/TAR.GZ/TAR.BZ2/TAR.XZ + zip-slip) — `core/util/extraction.{h,cpp}`
- File manager (std::filesystem wrappers + XDG dirs) — `core/util/file_manager.{h,cpp}`
- Storage analyzer — `core/util/storage_analyzer.{h,cpp}`
- Tool-calling parser (DEFAULT + LFM2 formats) — `core/util/tool_calling.{h,cpp}` + 6 tests
- Structured-output JSON extraction — `core/util/structured_output.{h,cpp}` + 5 tests
- Energy-based VAD (no ML deps) — `core/util/energy_vad.{h,cpp}` + 5 tests
- LLM streaming metrics (TTFT + t/s) — `core/util/llm_metrics.{h,cpp}` + 3 tests

### Network / auth
- HTTP client (libcurl) — `core/net/http_client.{h,cpp}`
- Auth manager + environment + endpoints — `core/net/environment.{h,cpp}`
- Auth tokens (access/refresh + expiry) + device registration state — + 5 tests
- Telemetry event queue — `core/net/telemetry.{h,cpp}`

### Error / lifecycle
- Error taxonomy (85 codes, 16 domains) — `core/abi/ra_errors.{h,c}`
- Lifecycle states (8 states) — `core/abi/ra_lifecycle.{h,c}`
- Source-level + binary compat for `rac_*` symbols — `core/abi/rac_compat.{h,c}`

### Pipeline / solutions
- Pipeline C ABI (struct-based, no protobuf) — `core/abi/ra_pipeline.{h,cpp}`

### Model management
- LoRA registry — `core/model_registry/lora_registry.{h,cpp}`
- Model compatibility checker — `core/model_registry/model_compatibility.{h,cpp}`

## Feature parity vs sdk/runanywhere-commons — still gapped

Tracked in `feature_parity_audit.md`:

- LLM LoRA adapter load/remove — plugin capability extension (not core)
- LLM KV-cache injection (`inject_system_prompt`, `append_context`) — plugin
- Device manager (registration orchestrator with HTTP callbacks) — platform callbacks
- OpenAI HTTP server (`/v1/chat/completions` streaming proxy)
- VLM + diffusion engines
- Voice agent state machine (WAITING_WAKEWORD → LISTENING → …)
- Benchmark statistics framework

## What's NOT done

- Sample apps (`examples/ios`, `examples/android`, `examples/flutter`,
  `examples/react-native`, `examples/web`) still consume the legacy
  `sdk/runanywhere-commons`. Migrating them is additive work — the new
  core coexists alongside.
- iOS slice of the xcframework — currently macOS-only. The xcframework
  script already handles the multi-slice case; ios-device / ios-sim
  targets just need invoking.
- WASM bundle from the new core (`setWasmModule` hook is wired, but the
  emscripten build of `racommons_core` against Emscripten SDK is not
  part of this branch yet).
- Event streaming across the FFI / WASM callback boundary for Dart +
  Web. Swift and Kotlin do it; Dart's NativeFunction callback path and
  Web's addFunction path are stubbed behind a clean error message.

## How to verify end-to-end locally

```bash
# C++ core
cmake --preset macos-debug && cmake --build --preset macos-debug && \
  ctest --preset macos-debug
# → 136/136 passed

# Swift SDK (builds xcframework + links it)
bash scripts/build-core-xcframework.sh --platforms=macos
cd frontends/swift && swift test
# → 3/3 passed, with real ra_pipeline_create_voice_agent invocation

# Kotlin SDK (links JNI bridge bundled in racommons_core)
cd frontends/kotlin && gradle --no-daemon build
# → green

# Dart SDK
cd frontends/dart && $FLUTTER_DART_SDK/dart pub get && $FLUTTER_DART_SDK/dart test
# → 2/2 passed

# TS / Web
cd frontends/ts  && npm install && npm test
cd frontends/web && npm install && npm test
# → all green
```

## CI

As of run 24624098111 (commit f08e36352), **6 of 7 jobs pass**:
cpp-macos ✓, cpp-linux ✓, proto-codegen-swift ✓, kotlin-frontend ✓,
dart-frontend ✓, ts-frontend ✓. `swift-frontend` is flaky only because
every new commit queues a fresh run and cancels the one-still-inflight
Swift step; when run to completion it also passes.
