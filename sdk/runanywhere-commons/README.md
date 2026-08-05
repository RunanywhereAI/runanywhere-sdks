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
│  │  llamacpp/  │  │  sherpa/ onnx/  │  │  qhexrt/      │  │ cloud/    │ │
│  │  LLM + VLM  │  │ STT/TTS/VAD,    │  │ LLM/VLM/STT/  │  │ STT       │ │
│  │  (GGUF),    │  │ embeddings,     │  │ TTS on the    │  │ (HTTP)    │ │
│  │  rerank     │  │ diarize/segment │  │ Hexagon NPU   │  │           │ │
│  │  Metal/CUDA │  │                 │  │ (Snapdragon)  │  │           │ │
│  └─────────────┘  └─────────────────┘  └───────────────┘  └───────────┘ │
│  ┌─────────────┐  ┌─────────────────┐                                    │
│  │  coreml/    │  │  platform/      │   (Apple only)                     │
│  │  diffusion  │  │  Apple FM,      │                                    │
│  │             │  │  System TTS     │                                    │
│  └─────────────┘  └─────────────────┘                                    │
└──────────────────────────────────────────────────────────────────────────┘
```

## Supported capabilities

Each row is a plugin ABI primitive (`RAC_PRIMITIVE_*`) with the engines that fill its vtable slot. A NULL slot means the engine does not serve that primitive.

| Primitive | vtable slot | Backends |
|-----------|-------------|----------|
| **GENERATE_TEXT** (LLM) | `llm_ops` | LlamaCPP, QHexRT (Hexagon NPU), Platform (Apple Foundation Models), MLX (Apple; registered from the Swift SDK) |
| **VLM** | `vlm_ops` | LlamaCPP (mmproj), QHexRT, MLX |
| **TRANSCRIBE** (STT) | `stt_ops` | Sherpa (offline ONNX), QHexRT, Cloud STT (online HTTP) |
| **SYNTHESIZE** (TTS) | `tts_ops` | Sherpa/ONNX (Piper), QHexRT, Platform (System TTS) |
| **DETECT_VOICE** (VAD) | `vad_ops` | Sherpa (Silero), built-in energy VAD |
| **EMBED** | `embedding_ops` | ONNX Runtime |
| **DIARIZE** | `diarization_ops` | ONNX (Sortformer) |
| **SEGMENT** | `segmentation_ops` | ONNX |
| **RERANK** | `rerank_ops` | LlamaCPP (rank-pooling GGUF) |
| **DIFFUSION** | `diffusion_ops` | Platform (Core ML, Apple) |

RAG and Voice Agent are composed pipelines rather than primitives: they orchestrate the services above and own no vtable of their own.

## Getting started (contributors)

### Prerequisites

- CMake 3.24+
- C++20 compiler (Clang, GCC, or MSVC)
- Platform toolchains as needed (Xcode 26+, Android NDK 27.3.13750724, MSVC on Windows)

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

### QHexRT

LLM, VLM, STT, and TTS on the Qualcomm Hexagon NPU from QNN context bundles. Android arm64 only; registers itself only on supported Snapdragon parts. Registration: `rac_backend_qhexrt_register()`.

### Cloud STT

Online speech-to-text over HTTP. Offline STT is served by Sherpa; a hybrid router picks per request.

### Platform (Apple)

Apple Foundation Models (LLM) and System TTS via Swift callbacks on iOS/macOS.

### NeuRT

ANE text generation + image generation (diffusion) on Apple platforms, via Apple's Core ML framework. Registration: `rac/plugin/rac_plugin_entry_neurt.h`.

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
