# `core/` — RunAnywhere C++ core

The single shared C++20 core that every frontend SDK (Swift, Kotlin,
Dart, TypeScript/React Native, Web/WASM) consumes through the public
`ra_*` C ABI.

## Taxonomy

The source tree is organized into the same 7 buckets the frontend SDKs
use, so symbol ownership is obvious from its path:

| Bucket               | Directory                             | Purpose                                                |
| -------------------- | ------------------------------------- | ------------------------------------------------------ |
| **Public API**       | `abi/ra_*.h` (public headers)         | Every symbol a frontend SDK is allowed to call.        |
| **Core primitives**  | `registry/`, `router/`, `graph/`      | Plugin registry, engine routing, scheduler primitives. |
| **Foundation**       | `util/`                               | Cross-cutting utilities: audio, text parsing, extraction, file I/O, VAD energy, metrics. |
| **Features**         | `voice_pipeline/`                     | Voice-agent composite pipeline and related feature code. More feature code lives inside engine plugins under `engines/`. |
| **Infrastructure**   | `model_registry/`, `net/`             | Model catalog + downloader; HTTP client + telemetry + environment + auth manager. |
| **Tests**            | `tests/`                              | gtest suites (see `CMakeLists.txt`).                   |
| **Engine plugins**   | `../engines/*/`                       | `llamacpp`, `sherpa`, `onnx`, `whisperkit`, `metalrt`, `diffusion-coreml`. |
| **Solutions**        | `../solutions/*/`                     | Cross-feature composites: `voice-agent`, `rag`, `openai-server`. |

### How the buckets map to main's `commons/src/` taxonomy

| v2 path                          | main branch counterpart                                       |
| -------------------------------- | ------------------------------------------------------------- |
| `core/abi/ra_*.h`                | `commons/include/rac/*` (public C ABI headers)                |
| `core/abi/ra_*.cpp`              | `commons/src/core/*` + `commons/src/features/*/rac_*.cpp`     |
| `core/registry/`                 | `commons/src/infrastructure/registry/`                        |
| `core/router/`                   | `commons/src/core/` (engine routing logic)                    |
| `core/graph/`                    | `commons/src/core/` (pipeline scheduler)                      |
| `core/util/audio_utils.*`        | `commons/src/utils/audio_*.cpp`                               |
| `core/util/text/*` (tool, struct) | `commons/src/utils/` + `commons/src/features/llm/`           |
| `core/util/extraction.*`         | `commons/src/infrastructure/extraction/`                      |
| `core/util/storage_analyzer.*`   | `commons/src/infrastructure/storage/`                         |
| `core/util/file_manager.*`       | `commons/src/infrastructure/file_management/`                 |
| `core/util/energy_vad.*`         | `commons/src/features/vad/`                                   |
| `core/util/llm_metrics.*`        | `commons/src/features/llm/metrics/`                           |
| `core/voice_pipeline/`           | `commons/src/features/voice_agent/`                           |
| `core/model_registry/`           | `commons/src/infrastructure/model_management/`                |
| `core/net/`                      | `commons/src/infrastructure/network/` + `telemetry/`          |
| `engines/llamacpp/`              | `commons/src/backends/llamacpp/`                              |
| `engines/onnx/`                  | `commons/src/backends/onnx/`                                  |
| `engines/sherpa/`                | `commons/src/backends/sherpa_onnx/` (renamed)                 |
| `engines/whisperkit/`            | `commons/src/backends/whisperkit_coreml/`                     |
| `engines/metalrt/`               | `commons/src/backends/metalrt/`                               |
| `engines/diffusion-coreml/`      | `commons/src/features/diffusion/` + `diffusion_platform/`     |
| `solutions/voice-agent/`         | `commons/src/features/voice_agent/`                           |
| `solutions/rag/`                 | `commons/src/features/rag/`                                   |
| `solutions/openai-server/`       | `commons/src/server/`                                         |

### Public C ABI — `core/abi/`

The C ABI is kept in a single flat directory for two practical reasons:

1. The `ra_*` prefix on every header is self-documenting — grepping
   `ra_stt` or `ra_rag` finds every relevant symbol immediately.
2. The XCFramework module map (`scripts/build-core-xcframework.sh`)
   lists every exported header by name. Grouping the `.h` files into
   `features/`, `infrastructure/`, etc. sub-paths requires parallel
   changes in the module map + all Swift / Kotlin / Dart / TS / Web
   bindings (~40 files). The organisational win is marginal.

The `README.md` sections below act as the canonical grouping:

#### Public Configuration

| Header                     | Purpose                                           |
| -------------------------- | ------------------------------------------------- |
| `ra_core_init.h`           | SDK init / shutdown / is-initialized              |
| `ra_state.h`               | SDKState: env, API key, device ID, auth tokens    |
| `ra_lifecycle.h`           | Global lifecycle callbacks                        |
| `ra_version.h`             | SDK version + build info                          |
| `ra_platform_adapter.h`    | Platform bridge function pointer table            |
| `ra_plugin.h`              | Engine plugin vtable + registration macros        |
| `ra_primitives.h`          | Primitive IDs, formats, runtime IDs, session IDs  |
| `ra_errors.h`              | Status codes + error strings                      |
| `ra_pipeline.h`            | Pipeline creation + driving                       |

#### Public Sessions

| Header               | Purpose                         |
| -------------------- | ------------------------------- |
| `ra_primitives.h`    | `ra_llm_*`, `ra_stt_*`, `ra_tts_*`, `ra_vad_*`, `ra_embed_*`, `ra_ww_*` session APIs |
| `ra_vlm.h`           | Vision-LM session API           |
| `ra_diffusion.h`     | Text-to-image session API       |

#### Public Extensions

| Header                  | Purpose                                                 |
| ----------------------- | ------------------------------------------------------- |
| `ra_tool.h`             | Tool calling detection / parsing / prompt formatting    |
| `ra_structured.h`       | Structured-output JSON extraction + validation          |
| `ra_rag.h`              | Chunker + in-memory vector store                        |
| `ra_model.h`            | Framework × category matrix + format detection          |
| `ra_auth.h`             | Auth manager C ABI                                      |
| `ra_http.h`             | HTTP executor injection                                 |
| `ra_platform_llm.h`     | Platform-LLM callback injection (FoundationModels etc.) |
| `ra_server.h`           | OpenAI-compatible HTTP server control                   |
| `ra_backends.h`         | Swift / Kotlin engine-plugin bridge callback tables     |
| `ra_image.h`            | Image loading/decoding/resize/normalize                 |

#### Public Infrastructure

| Header                 | Purpose                                                   |
| ---------------------- | --------------------------------------------------------- |
| `ra_device.h`          | Device ID, registration, capabilities                     |
| `ra_download.h`        | Download manager + orchestrator + SHA-256 verify          |
| `ra_event.h`           | Event bus (subscribe / publish)                           |
| `ra_file.h`            | File system (create / remove / listings / canonical dirs) |
| `ra_storage.h`         | Disk space + stored-model enumeration                     |
| `ra_extract.h`         | Archive detection + extraction                            |
| `ra_telemetry.h`       | Telemetry manager + HTTP callback injection               |
| `ra_benchmark.h`       | Benchmark timing + stats                                  |

## Build

```
cmake -S . -B build/macos-debug -DRA_BUILD_SERVER=ON -DRA_BUILD_TESTS=ON
cmake --build build/macos-debug -j8
cd build/macos-debug && ctest -j8
```

Expected: 188 / 188 passing, 5 Live* tests skipped (need .gguf / .onnx
model weights present on disk).
