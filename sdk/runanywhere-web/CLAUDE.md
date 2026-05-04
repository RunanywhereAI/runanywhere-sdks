# RunAnywhere Web SDK — CLAUDE.md

## Overview

TypeScript/WebAssembly SDK for on-device AI in the browser. Three npm workspace packages: a pure-TypeScript core (`@runanywhere/web`) and two WASM backend packages (`@runanywhere/web-llamacpp`, `@runanywhere/web-onnx`). Version `0.19.13`.

The core has **zero WASM** — it defines types, lifecycle management, model downloading, storage, the extension/provider registry, and dispatch infrastructure. Backend packages ship pre-built `.wasm` binaries and register themselves at runtime via the plugin/provider pattern.

---

## Quick Reference — How to Run

```bash
# First-time setup (installs Emscripten 5.0.0, npm deps, builds WASM + TypeScript)
./scripts/build-web.sh --setup

# Build WASM + TypeScript (all backends)
./scripts/build-web.sh

# Build WASM with specific backends
./scripts/build-web.sh --build-wasm --llamacpp --onnx
./scripts/build-web.sh --build-wasm --llamacpp --vlm --webgpu

# Build TypeScript only (after WASM already built)
./scripts/build-web.sh --build-ts
# Or via npm directly:
npm run build:ts     # runs tsc in core, llamacpp, onnx sequentially
npm run build        # alias for build:ts

# Dev mode (TypeScript watch on core)
npm run dev

# Type-check without emitting
npm run typecheck

# Lint
npm run lint

# Run tests (core package only — llamacpp/onnx have no tests)
cd packages/core && npm test          # vitest run
cd packages/core && npm run test:types # tsd type-level tests

# Clean all build artifacts
npm run clean

# Build WASM from scratch
npm run build:wasm          # Release build
npm run build:wasm:debug    # Debug build with assertions
npm run build:wasm:clean    # Clean + rebuild

# Build sherpa-onnx WASM separately
cd wasm && ./scripts/build-sherpa-onnx.sh

# Package for CI/release
./scripts/package-sdk.sh
```

### Example Web App

```bash
cd ../../examples/web/RunAnywhereAI/
npm install
npm run dev
# Opens at localhost with COOP/COEP headers for SharedArrayBuffer
```

---

## Directory Structure

```
sdk/runanywhere-web/
├── package.json                 # Workspace root (@runanywhere/web-root, private)
├── tsconfig.base.json           # Shared TS config (ES2022, ESNext modules, strict)
├── eslint.config.mjs            # ESLint 9 flat config (workspace-wide)
├── scripts/
│   └── package-sdk.sh           # CI packaging: npm pack + sha256 checksums
├── wasm/                        # C++/Emscripten WASM build system
│   ├── CMakeLists.txt           # 1031-line CMake build definition
│   ├── src/wasm_exports.cpp     # WASM entry point + sizeof/offsetof helpers
│   ├── platform/wasm_platform_shims.cpp  # Returns "emscripten" platform string
│   ├── scripts/
│   │   ├── build.sh             # Main WASM build script (flags: --llamacpp, --vlm, --webgpu, --debug, etc.)
│   │   ├── build-sherpa-onnx.sh # Sherpa-ONNX v1.12.20 WASM build
│   │   ├── setup-emsdk.sh       # Installs Emscripten SDK 5.0.0
│   │   └── patch-sherpa-glue.js # 7 browser-compat patches on sherpa glue JS
│   ├── third_party/sherpa-onnx/ # Cloned at build time
│   ├── build/                   # CMake build tree (CPU)
│   ├── build-webgpu/            # CMake build tree (WebGPU)
│   └── build-sherpa-onnx/       # CMake build tree (sherpa-onnx)
├── emsdk/                       # Emscripten SDK (cloned by setup-emsdk.sh)
└── packages/
    ├── core/                    # @runanywhere/web — pure TypeScript, no WASM
    ├── llamacpp/                # @runanywhere/web-llamacpp — llama.cpp WASM backend
    └── onnx/                    # @runanywhere/web-onnx — sherpa-onnx WASM backend
```

---

## Package Details

### `packages/core/` — `@runanywhere/web`

Pure TypeScript. Entry point: `src/index.ts` (308-line barrel export). ESM-only (`type: "module"`), tree-shakeable (`sideEffects: false`).

**Dependencies:** `@runanywhere/proto-ts` (local file ref), `long`, `protobufjs`
**Dev deps:** `vitest`, `tsd`, `typescript`, `eslint`

```
packages/core/src/
├── index.ts                          # Public barrel export (308 lines)
├── types.ts                          # Type re-exports
├── types/
│   ├── index.ts                      # Proto-ts re-exports + web ergonomic types
│   ├── enums.ts                      # String enums: ModelCategory, ModelStatus, LLMFramework, etc.
│   └── models.ts                     # SDKInitOptions, ModelInfo, StorageInfo, DeviceInfoData
├── Public/
│   ├── RunAnywhere.ts                # Main SDK singleton object (~900 lines)
│   └── Extensions/                   # 20 namespace extension files
│       ├── RunAnywhere+Convenience.ts    # Flat verbs: chat/generate/transcribe/synthesize/speak/detectSpeech
│       ├── RunAnywhere+TextGeneration.ts # LLM generate/stream + structured output extraction
│       ├── RunAnywhere+STT.ts            # Speech-to-text namespace
│       ├── RunAnywhere+TTS.ts            # Text-to-speech namespace
│       ├── RunAnywhere+VAD.ts            # Voice activity detection namespace
│       ├── RunAnywhere+VoiceAgent.ts     # Voice agent orchestration + streaming
│       ├── RunAnywhere+VisionLanguage.ts # VLM namespace
│       ├── RunAnywhere+VLMModels.ts      # VLM model management
│       ├── RunAnywhere+Diffusion.ts      # Image diffusion namespace
│       ├── RunAnywhere+Embeddings.ts     # Embeddings namespace
│       ├── RunAnywhere+StructuredOutput.ts # JSON schema constrained generation
│       ├── RunAnywhere+ToolCalling.ts    # Tool/function calling
│       ├── RunAnywhere+LoRA.ts           # LoRA adapter management
│       ├── RunAnywhere+RAG.ts            # RAG pipeline
│       ├── RunAnywhere+ModelManagement.ts # Model download/load/unload verbs
│       ├── RunAnywhere+ModelAssignments.ts # Role-to-model mapping
│       ├── RunAnywhere+Frameworks.ts     # Registered backend capabilities
│       ├── RunAnywhere+Solutions.ts      # L5 pipeline solutions runtime
│       ├── RunAnywhere+Storage.ts        # Storage info namespace
│       ├── RunAnywhere+Logging.ts        # Log level control
│       ├── RunAnywhere+Hardware.ts       # Hardware profile detection
│       └── RunAnywhere+PluginLoader.ts   # Extension/plugin registration
├── Foundation/
│   ├── EventBus.ts           # Typed pub/sub singleton (on/once/onAny/emit)
│   ├── SDKLogger.ts          # Category-tagged console logger with log levels
│   ├── SDKException.ts       # Single exception class with signed-negative error codes
│   ├── RuntimeConfig.ts      # Acceleration mode preference (cpu/webgpu/auto)
│   ├── AsyncQueue.ts         # Single-producer/single-consumer AsyncIterable<T>
│   ├── StructOffsets.ts      # C struct offset type definitions (AllOffsets, etc.)
│   ├── WASMBridge.ts         # AccelerationMode type only
│   └── ProtoHelpers.ts       # tokensUsed/latencyMs accessors for LLMGenerationResult
├── Infrastructure/
│   ├── ModelManager.ts       # Central model lifecycle orchestrator (singleton, ~680 lines)
│   ├── ModelRegistry.ts      # In-memory model catalog + CompactModelDef resolver
│   ├── ModelDownloader.ts    # Download + storage + SHA-256 verification + LRU eviction
│   ├── ModelStateStore.ts    # Runtime loaded-model state per category
│   ├── ModelLoaderTypes.ts   # LLMModelLoader/STTModelLoader/TTSModelLoader/VADModelLoader interfaces
│   ├── ModelFileInference.ts # Infer model metadata from filename (.gguf → LLM, etc.)
│   ├── ModelDownloadValidation.ts  # URL validation pre-download
│   ├── ModelDownloadQuota.ts       # Per-model quota checks
│   ├── OPFSStorage.ts       # Origin Private File System storage (nested paths, sanitization)
│   ├── LocalFileStorage.ts   # File System Access API storage (Chrome 122+, IndexedDB handle persistence)
│   ├── StorageProvider.ts    # StorageProvider/StorageProviderId interfaces
│   ├── StoragePathResolver.ts # localStorage path helpers
│   ├── ExtensionPoint.ts     # Backend + provider + service triple-registry (singleton)
│   ├── ExtensionRegistry.ts  # Ordered list of named SDK extensions
│   ├── ProviderTypes.ts      # LLMProvider/STTProvider/TTSProvider/VADProvider interfaces
│   ├── DeviceCapabilities.ts # WebGPU, SharedArrayBuffer, WASM SIMD, OPFS detection
│   ├── AudioCapture.ts       # Microphone capture via Web Audio API (ScriptProcessorNode)
│   ├── AudioPlayback.ts      # TTS playback via AudioBufferSourceNode
│   ├── AudioFileLoader.ts    # Load audio files as Float32Array via AudioContext.decodeAudioData
│   ├── VideoCapture.ts       # Camera capture via getUserMedia + canvas
│   └── ArchiveUtility.ts     # .tar.gz extraction
├── Adapters/
│   ├── HTTPAdapter.ts            # Wraps rac_http_client C ABI (request/stream/download)
│   ├── FetchHttpTransport.ts     # JS-side sync XHR transport registered via C vtable
│   ├── LLMStreamAdapter.ts      # WASM proto-callback → AsyncIterable<LLMStreamEvent> (fan-out)
│   ├── VoiceAgentStreamAdapter.ts # WASM proto-callback → AsyncIterable<VoiceEvent> (fan-out)
│   ├── ModelRegistryAdapter.ts   # Wraps rac_model_registry_refresh C ABI
│   └── SolutionAdapter.ts       # Wraps rac_solution_* C ABI (SolutionHandle lifecycle)
├── Features/LLM/
│   └── LlmThinking.ts           # extract/strip/splitTokens for think-block parsing
├── runtime/
│   └── EmscriptenModule.ts       # Typed Emscripten module interface + singleton Proxy
├── services/
│   └── AnalyticsEmitter.ts       # Singleton telemetry proxy (safe no-op if no backend)
└── __tests__/
    └── types.test-d.ts           # tsd compile-time type assertions
```

### `packages/llamacpp/` — `@runanywhere/web-llamacpp`

WASM backend for LLM, VLM, embeddings, tool calling, structured output, diffusion. Peer-depends on `@runanywhere/web`.

Additional package.json exports: `"./vlm-worker"` (Web Worker entry), `"./wasm/*"` (direct WASM file access).

```
packages/llamacpp/
├── src/
│   ├── index.ts                # Barrel export
│   ├── LlamaCPP.ts             # Public facade: LlamaCPP.register(acceleration?) + autoRegister
│   ├── LlamaCppProvider.ts     # Registration orchestrator (loads WASM, registers all extensions/providers)
│   ├── Foundation/
│   │   ├── LlamaCppBridge.ts       # WASM loader singleton (~700 lines): module load, rac_init, backend register
│   │   ├── LlamaCppOffsets.ts      # Lazy-cached C struct byte-offset loader via _rac_wasm_offsetof_*
│   │   ├── PlatformAdapter.ts      # Registers 11 JS callbacks as rac_platform_adapter_t C vtable
│   │   ├── AnalyticsEventsBridge.ts # C++ analytics events → TypeScript EventBus
│   │   ├── TelemetryService.ts     # C++ telemetry manager → browser fetch
│   │   └── WASMAnalyticsEmitter.ts # TypeScript → C analytics emit helpers
│   ├── Extensions/
│   │   ├── RunAnywhere+TextGeneration.ts  # LLM generate/stream via WASM C ABI
│   │   ├── RunAnywhere+VLM.ts             # Vision-language model via WASM
│   │   ├── RunAnywhere+ToolCalling.ts     # Tool calling via WASM
│   │   ├── RunAnywhere+StructuredOutput.ts # Structured output via WASM
│   │   ├── RunAnywhere+Embeddings.ts      # Embeddings via WASM
│   │   ├── RunAnywhere+Diffusion.ts       # Image diffusion via WASM
│   │   └── *Types.ts                      # Type definitions per extension
│   ├── Infrastructure/
│   │   ├── VLMWorkerBridge.ts   # Main-thread bridge to VLM Web Worker
│   │   └── VLMWorkerRuntime.ts  # Worker-side WASM runtime (~800 lines)
│   └── workers/
│       ├── vlm-worker.ts       # VLM Web Worker TypeScript entry
│       └── vlm-worker.js       # Bundler-facing JS proxy
└── wasm/
    ├── racommons-llamacpp.wasm          # Pre-built CPU variant (2.9 MB)
    ├── racommons-llamacpp.js            # Emscripten glue (68 KB)
    ├── racommons-llamacpp-webgpu.wasm   # Pre-built WebGPU variant (4.5 MB)
    └── racommons-llamacpp-webgpu.js     # WebGPU glue (95 KB)
```

### `packages/onnx/` — `@runanywhere/web-onnx`

WASM backend for STT (Whisper/Zipformer/Paraformer), TTS (Piper/VITS), VAD (Silero). Peer-depends on `@runanywhere/web`.

```
packages/onnx/
├── src/
│   ├── index.ts                # Barrel export
│   ├── ONNX.ts                 # Public facade: ONNX.register() + autoRegister
│   ├── ONNXProvider.ts         # Registration orchestrator
│   ├── Foundation/
│   │   ├── SherpaONNXBridge.ts     # WASM loader singleton: async instantiate, timeout, helper URL derivation
│   │   └── SherpaHelperLoader.ts   # Loads sherpa-onnx-asr/tts/vad.js as Blob URL ESM modules
│   └── Extensions/
│       ├── RunAnywhere+STT.ts      # STT via sherpa-onnx (offline/online recognizer, streaming)
│       ├── RunAnywhere+TTS.ts      # TTS via sherpa-onnx (Piper VITS)
│       ├── RunAnywhere+VAD.ts      # VAD via sherpa-onnx (Silero)
│       └── *Types.ts               # Type definitions per extension
└── wasm/sherpa/
    ├── sherpa-onnx.wasm             # Pre-built (12 MB, includes ONNX Runtime)
    ├── sherpa-onnx-glue.js          # Patched Emscripten glue (92 KB, 7 browser patches applied)
    ├── sherpa-onnx-asr.js           # Sherpa struct-packing helper (40 KB)
    ├── sherpa-onnx-tts.js           # Sherpa struct-packing helper (18 KB)
    ├── sherpa-onnx-vad.js           # Sherpa struct-packing helper (7.5 KB)
    └── sherpa-onnx-wave.js          # Sherpa audio format helper (2.4 KB)
```

---

## Architecture

### Plugin/Provider Pattern

The core defines capability slots. Backend packages fill them at runtime:

```
ExtensionPoint (singleton)
├── Backend registry:    id → BackendExtension (capabilities + cleanup)
├── Provider registry:   'llm' | 'stt' | 'tts' | 'vad' → typed provider impl
└── Service registry:    ServiceKey → service object

@runanywhere/web-llamacpp registers:
  - Provider 'llm' → TextGeneration (LLM, VLM, structured output, tool calling)
  - Services: Embeddings, Diffusion
  - Capabilities: LLM, VLM, ToolCalling, StructuredOutput, Embeddings, Diffusion

@runanywhere/web-onnx registers:
  - Provider 'stt' → STTService
  - Provider 'tts' → TTSService
  - Provider 'vad' → VADService
  - Capabilities: STT, TTS, VAD
```

### Two-Phase Initialization

```typescript
// Phase 1: Core init (pure TypeScript — no WASM needed)
await RunAnywhere.initialize({ environment: 'development' });

// Phase 2: Backend WASM load + registration
await LlamaCPP.register();   // loads racommons-llamacpp.wasm, registers providers
await ONNX.register();        // loads sherpa-onnx.wasm, registers providers
```

### WASM Module Lifecycle (LlamaCpp)

`LlamaCppBridge._doLoad()`:
1. `detectWebGPUWithJSPI()` — checks `navigator.gpu` + `WebAssembly.promising`
2. Dynamic `import()` of Emscripten glue `.js`
3. `createModule({...})` — Emscripten instantiates `.wasm`
4. `_rac_wasm_ping()` → verify returns `42`
5. `PlatformAdapter.register()` — 11 JS callbacks as C vtable
6. `rac_init()` via `ccall({async: true})`
7. `rac_backend_llamacpp_register()` + `rac_backend_llamacpp_vlm_register()`
8. Analytics/telemetry bridges init
9. `setRunanywhereModule()` — installs global singleton
10. `HTTPAdapter.setDefaultModule()` + `ModelRegistryAdapter.setDefaultModule()`
11. Falls back to CPU if WebGPU load fails in `auto` mode

### TypeScript → WASM Call Patterns

**Pattern 1: Direct function call** — `m._rac_*(args)` for synchronous non-blocking functions

**Pattern 2: `ccall` with `{async: true}`** — for blocking HTTP/LLM calls that suspend via ASYNCIFY/JSPI

**Pattern 3: `addFunction` trampolines** — C++ calls back into JS via function table entries. Signature strings follow Emscripten encoding (`'viii'` = void return, 3 int args). Always cleaned up via `removeFunction()`.

**Pattern 4: Direct WASM heap reads** — `HEAPU8`/`HEAP32`/`HEAPU32` typed arrays for performance. Always `.slice()` to copy data out before the callback returns (WASM buffer may relocate).

### Struct Layout Safety

TypeScript never hard-codes C struct offsets. Every field access uses runtime `_rac_wasm_offsetof_*()` and `_rac_wasm_sizeof_*()` helpers from `wasm_exports.cpp`. `LlamaCppOffsets.ts` caches all offsets on first access via a Proxy.

### Model Lifecycle Flow

```
registerModel(def) → ModelRegistry.registerModels([def])
    ↓
downloadModel(id) → ModelDownloader.downloadModel(id)
    ↓  streaming fetch → OPFSStorage.saveModelFromStream
    ↓  SHA-256 verify if checksumSha256 set
    ↓  additional files downloaded sequentially
    ↓
loadModel(id) → ModelManager.loadModel(id)
    ↓  dispatches by modality:
    ↓  Language → llmLoader.loadModelFromData(ctx)
    ↓  Multimodal → vlmLoader (locates mmproj sidecar)
    ↓  SpeechRecognition → sttLoader.loadModelFromData(ctx)
    ↓  SpeechSynthesis → ttsLoader.loadModelFromData(ctx)
    ↓  Audio → vadLoader.loadModelFromData(ctx)
    ↓
generate/transcribe/synthesize → providers via ExtensionPoint
    ↓
unloadModel → loader.unloadModel/cleanup
```

### Streaming Architecture

**LLM streaming:** `LLMStreamAdapter` wraps `_rac_llm_set_stream_proto_callback` into `AsyncIterable<LLMStreamEvent>`. Uses fan-out pattern — one WASM trampoline serves multiple concurrent JS subscribers.

**Voice agent streaming:** `VoiceAgentStreamAdapter` wraps `_rac_voice_agent_set_proto_callback` into `AsyncIterable<VoiceEvent>`. Same fan-out pattern. `WeakMap` keyed by module instance prevents cross-module handle collision.

### Storage Backends (Priority Order)

1. **File System Access API** (`LocalFileStorage`) — Chrome 122+, user-granted directory, IndexedDB handle persistence
2. **OPFS** (`OPFSStorage`) — Origin Private File System, nested paths, LRU eviction
3. **Memory** — `Map<string, Uint8Array>` fallback when quota exceeded

### Cross-Origin Requirements

The example app's Vite config sets `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: credentialless` for `SharedArrayBuffer` support. A `coi-serviceworker.js` provides fallback header injection.

---

## WASM Build System

### CMakeLists.txt Build Options

| Option | Default | Effect |
|---|---|---|
| `RAC_WASM_LLAMACPP` | OFF | Include llama.cpp LLM backend |
| `RAC_WASM_VLM` | OFF | VLM via mtmd (forces LLAMACPP=ON) |
| `RAC_WASM_WEBGPU` | OFF | WebGPU acceleration (forces LLAMACPP=ON, uses JSPI) |
| `RAC_WASM_WHISPERCPP` | OFF | whisper.cpp STT (incompatible with llamacpp b8011+) |
| `RAC_WASM_ONNX` | OFF | sherpa-onnx (built separately via build-sherpa-onnx.sh) |
| `RAC_WASM_PTHREADS` | OFF | pthreads (requires SharedArrayBuffer) |
| `RAC_WASM_DEBUG` | OFF | Debug assertions, SAFE_HEAP, STACK_OVERFLOW_CHECK |

### Key Emscripten Flags

- 32 MB initial heap, 4 GB max, 1 MB stack
- `MODULARIZE=1`, `EXPORT_ES6=1`, factory name `createLlamaCppModule`
- `ENVIRONMENT=web,worker`
- `ALLOW_TABLE_GROWTH=1` (required for `addFunction` trampolines)
- `ERROR_ON_UNDEFINED_SYMBOLS=0` (feature stubs return null at runtime)
- Release: `-O3 --closure=1`, Debug: `-g3 -sASSERTIONS=2 -sSAFE_HEAP=1`
- WebGPU: `-sJSPI` with narrow import/export lists, `-fwasm-exceptions`

### Build Outputs

| File | Size | Source |
|---|---|---|
| `packages/llamacpp/wasm/racommons-llamacpp.wasm` | 2.9 MB | `build.sh --llamacpp` |
| `packages/llamacpp/wasm/racommons-llamacpp-webgpu.wasm` | 4.5 MB | `build.sh --webgpu` |
| `packages/onnx/wasm/sherpa/sherpa-onnx.wasm` | 12 MB | `build-sherpa-onnx.sh` |

### Sherpa Browser Patches (`patch-sherpa-glue.js`)

Seven patches applied to the Emscripten-generated glue JS:
1. Force `ENVIRONMENT_IS_NODE = false`
2. Replace `require("node:path")` with browser PATH shim
3. Remove NODERAWFS error throw
4. Skip NODERAWFS FS patching (preserve MEMFS)
5. Append `export default Module` for ESM
6. Fix `instantiateWasm` async race with `addRunDependency/removeRunDependency`
7. Export HEAP views on Module inside `updateMemoryViews`

---

## Tests

### Core Package Tests

- **Type tests** (`tsd`): `src/__tests__/types.test-d.ts` — compile-time assertions on `RunAnywhere`, `GenerateOptions`, `ChatMessage`, `ModelDescriptor`, etc.
- **Unit tests** (`vitest`):
  - `src/Adapters/__tests__/VoiceAgentStreamAdapter.fanout.test.ts` — fan-out invariant: one WASM trampoline for N subscribers
  - `src/runtime/EmscriptenModule.test.ts` — singleton set/clear lifecycle
- **Cross-repo streaming tests**: `../../../../tests/streaming/**/*.web.test.ts` (shared fixtures with RN SDK)

Run: `cd packages/core && npm test`

### No Tests in Backend Packages

`packages/llamacpp/` and `packages/onnx/` have no test files.

---

## Key Singletons

| Singleton | Location | Access |
|---|---|---|
| `RunAnywhere` | `Public/RunAnywhere.ts` | Direct import (object literal) |
| `EventBus.shared` | `Foundation/EventBus.ts` | `EventBus.shared` |
| `ModelManager` | `Infrastructure/ModelManager.ts` | `ModelManager` (module-level instance) |
| `ExtensionPoint` | `Infrastructure/ExtensionPoint.ts` | `ExtensionPoint` (module-level instance) |
| `ExtensionRegistry` | `Infrastructure/ExtensionRegistry.ts` | `ExtensionRegistry` (module-level instance) |
| `EmscriptenModule` | `runtime/EmscriptenModule.ts` | `runanywhereModule` Proxy |
| `LlamaCppBridge.shared` | `Foundation/LlamaCppBridge.ts` | `LlamaCppBridge.shared` |
| `SherpaONNXBridge.shared` | `Foundation/SherpaONNXBridge.ts` | `SherpaONNXBridge.shared` |
| `AnalyticsEmitter` | `services/AnalyticsEmitter.ts` | `AnalyticsEmitter` (module-level instance) |

---

## Dependency Graph

```
@runanywhere/proto-ts  (file:../../../runanywhere-proto-ts, v0.21.0)
         │
         └── @runanywhere/web (peer dep)
                  │
                  ├── @runanywhere/web-llamacpp (peer dep → @runanywhere/web)
                  │
                  └── @runanywhere/web-onnx     (peer dep → @runanywhere/web)
```

The shared C++ core lives at `../../runanywhere-commons` relative to the `wasm/` directory.

---

## Exported C ABI Surface (~150+ functions)

Organized by subsystem in `wasm/CMakeLists.txt:209-777`: memory management, core init, platform adapter, HTTP client/transport/download, struct layout helpers, module registry, events, model registry, lifecycle, LLM (generate/stream/thinking/component), tool calling, STT, TTS, VAD, voice agent, solutions, VLM, structured output, diffusion, embeddings, SDK config, telemetry, analytics, WASM helpers. Backend-conditional symbols appended for llama.cpp, VLM, whisper.cpp, sherpa-onnx.

---

## Prerequisites

- **Node.js** 18+
- **Emscripten SDK** 5.0.0+ (for WASM builds only; installed by `setup-emsdk.sh`)
- **CMake** 3.22+ (for WASM builds only)
- **TypeScript** 5.6+ (dev dependency)

---

## Component Interdependency Map

```
RunAnywhere (singleton)
  ├── EventBus.shared
  ├── SDKLogger
  ├── ModelManager (singleton)
  │    ├── ModelRegistry (catalog)
  │    ├── ModelDownloader
  │    │    ├── OPFSStorage / LocalFileStorage
  │    │    ├── HTTPAdapter.tryDefault()
  │    │    └── AnalyticsEmitter
  │    ├── ModelStateStore (runtime loaded state)
  │    └── Pluggable loaders (set by backend packages):
  │         LLMModelLoader, STTModelLoader, TTSModelLoader, VADModelLoader, VLMLoader
  ├── ExtensionRegistry (named extensions)
  ├── ExtensionPoint (capabilities + providers + services)
  │    ├── Provider 'llm' → from @runanywhere/web-llamacpp
  │    ├── Provider 'stt' → from @runanywhere/web-onnx
  │    ├── Provider 'tts' → from @runanywhere/web-onnx
  │    └── Provider 'vad' → from @runanywhere/web-onnx
  ├── Runtime (acceleration mode)
  ├── HTTPAdapter (WASM HTTP bridge)
  ├── ModelRegistryAdapter (WASM registry bridge)
  └── 20 namespace extensions (each delegating to providers above)
```
