# RunAnywhere Commons

**Internal C/C++ core** for the RunAnywhere SDK ecosystem. This is not a consumer-facing SDK — platform SDKs (Swift, Kotlin, React Native, Flutter, Web, Python, Electron, CLI) bind to commons through the stable `rac_*` C ABI.

Commons provides the shared infrastructure, engine plugin registry, model lifecycle, download orchestration, and ML backend integrations that power on-device AI across iOS, Android, macOS, Linux, Windows, and WebAssembly.

**Version:** tracks the repo `VERSION` file (currently **0.20.11**).

## What commons provides

- **Unified C API** — all public functions use the `rac_` prefix
- **Engine plugin registry** — vtable-based backends registered at startup or via `dlopen`
- **Cross-platform core** — single codebase for mobile, desktop, and WASM targets
- **AI primitives** — LLM, VLM, STT, TTS, VAD, embeddings, RAG, Voice Agent, and more
- **Platform adapters** — storage, logging, secure store, and HTTP download hooks for each host SDK

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Platform SDKs                                                           │
│  Swift · Kotlin · React Native · Flutter · Web · Python · Electron · CLI │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ C ABI (rac_*)
┌───────────────────────────────▼──────────────────────────────────────────┐
│  RAC Public C API                                                        │
│  rac_llm_service.h · rac_stt_service.h · rac_tts_service.h · …         │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ rac_engine_vtable_t dispatch
┌───────────────────────────────▼──────────────────────────────────────────┐
│  Plugin Registry + Engine Router                                         │
│  ABI-versioned handshake · hardware-aware routing · static or dlopen     │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │
┌───────────────────────────────▼──────────────────────────────────────────┐
│  Engine Plugins (engines/)                                               │
│  ┌─────────────┐  ┌─────────────────┐  ┌───────────────┐  ┌───────────┐ │
│  │  llamacpp/  │  │  sherpa/ onnx/  │  │  cloud/       │  │ platform/ │ │
│  │  LLM (GGUF) │  │ STT/TTS/VAD,    │  │  STT (HTTP)   │  │ Apple FM  │ │
│  │  Metal/CUDA │  │ embeddings      │  │               │  │ System TTS│ │
│  └─────────────┘  └─────────────────┘  └───────────────┘  └───────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

## Supported capabilities

| Capability | Backends |
|------------|----------|
| **TEXT_GENERATION** (LLM) | LlamaCPP, Platform (Apple Foundation Models), MLX (macOS) |
| **VLM** | LlamaCPP (mmproj), MLX |
| **STT** | Sherpa (offline ONNX), Cloud STT (online HTTP) |
| **TTS** | Sherpa/ONNX (Piper), Platform (System TTS) |
| **VAD** | ONNX (Silero), built-in energy VAD |
| **EMBEDDINGS** | ONNX Runtime |
| **VOICE_AGENT** | Composite (VAD + STT + LLM + TTS) |

## Getting started (contributors)

### Prerequisites

- CMake 3.22+
- C++20 compiler (Clang, GCC, or MSVC)
- Platform toolchains as needed (Xcode 15+, Android NDK r25+, MSVC on Windows)

### Clone and build

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks/sdk/runanywhere-commons

cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build

# With ML backends
cmake -B build -DRAC_BUILD_BACKENDS=ON
cmake --build build
```

### Minimal usage (C)

```c
#include "rac/core/rac_core.h"
#include "rac/features/llm/rac_llm_service.h"

rac_config_t config = {
    .platform_adapter = &my_platform_adapter,
    .log_level = RAC_LOG_INFO,
    .log_tag = "MyApp"
};
rac_init(&config);

rac_backend_llamacpp_register();
rac_backend_onnx_register();

rac_handle_t llm;
rac_llm_create("my-model-id", &llm);

rac_llm_result_t result;
rac_llm_generate(llm, "Hello!", NULL, &result);

rac_llm_result_free(&result);
rac_llm_destroy(llm);
rac_shutdown();
```

## Backend overview

### LlamaCPP

GGUF models for LLM and VLM. GPU acceleration via Metal (Apple), CUDA (Windows/Linux), and WebGPU (Web). Header: `include/rac/backends/rac_llm_llamacpp.h`.

### Sherpa-ONNX

Offline STT, TTS, and VAD via ONNX. Registration: `rac/plugin/rac_plugin_entry_sherpa.h`.

### ONNX Runtime

Embeddings and general ONNX inference. Registration: `rac/plugin/rac_plugin_entry_onnx.h`.

### Cloud STT

Online speech-to-text over HTTP. Offline STT is served by Sherpa; a hybrid router picks per request.

### Platform (Apple)

Apple Foundation Models (LLM) and System TTS via Swift callbacks on iOS/macOS.

## Platform SDK integration

| SDK | Binding |
|-----|---------|
| Swift | `CRACommons` module, XCFrameworks in `runanywhere-swift` |
| Kotlin | JNI (`librac_*_jni.so`) |
| React Native | JSI / native module over commons |
| Flutter | FFI over commons |
| Web | Emscripten WASM modules in `runanywhere-web` |
| Python | pybind11 / scikit-build extension in `runanywhere-python` |
| Electron | N-API addon in `runanywhere-electron` |
| CLI | Direct C++ consumer (`rcli`) |

Each host implements a `rac_platform_adapter_t` for file I/O, secure storage, logging, and downloads.

## Version management

Version pins for dependencies and the project version live in `VERSIONS` and the repo-root `VERSION` file. Load in scripts with `source scripts/load-versions.sh` or in CMake with `include(LoadVersions)`.

## Further reading

- Contributor build guide: [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md)
- Architecture details: [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md)
- Per-platform integration notes: [docs/md/](./docs/md/)

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## License

See the repository [LICENSE](../../LICENSE).
