# RunAnywhere Commons: Implementation Overview

## Executive Summary

This document outlines the implementation plan for creating `runanywhere-commons`, a public C/C++ layer that sits between the private `runanywhere-core` (native inference backends) and the platform SDK wrappers (iOS Swift, Android Kotlin, Flutter, React Native).

**Key Goals:**
1. Create modular backend architecture (LlamaCpp, ONNX, WhisperCpp, MLX can be independently included/excluded)
2. Produce separate XCFrameworks/JNILibs per backend for flexible packaging
3. Enable consumers to choose only the backends they need → **Binary size optimization**
4. Move orchestration logic to C++ (commons layer)
5. Keep platform SDKs as thin wrappers providing idiomatic APIs
6. Maintain backward compatibility with existing Swift SDK public APIs

---

## ⚠️ Critical Design Decisions (Addressing Identified Inconsistencies)

### Decision 1: C API Strategy — WRAP, EXTEND, NOT REPLACE

**Problem Identified:** Three competing C API "truths" existed across documentation.

**Resolution:** We adopt a **single, unified C API strategy**:

| API Category | Source | Status | Used By |
|--------------|--------|--------|---------|
| `ra_create_backend()`, `ra_text_*`, `ra_stt_*`, etc. | `runanywhere_bridge.h` (existing) | **PRESERVED** | All platform SDKs |
| `rac_module_*`, `rac_service_*`, `rac_event_*` | `runanywhere-commons` (new) | **NEW** | Commons internal + SDKs |

**Key Points:**
- Existing `runanywhere_bridge.h` APIs are **preserved unchanged**
- New commons APIs use `rac_` prefix (NOT `ra_`) to avoid symbol collisions
- Platform SDKs continue calling existing `ra_*` APIs for inference
- New `rac_*` APIs provide module registry, events, lifecycle management

### Decision 2: Header Namespace — `rac_` Prefix for Commons

**Problem Identified:** Header collision between `runanywhere-core` and `runanywhere-commons`.

**Resolution:** All commons headers use `rac_` prefix:

```
runanywhere-core (private, internal):     runanywhere-commons (public):
├── types.h                               ├── rac_types.h
├── runanywhere_bridge.h                  ├── rac_core.h
└── (capability headers)                  ├── rac_events.h
                                          └── rac_platform_adapter.h
```

**Include Guard Strategy:**
```c
// runanywhere-core (private)
#ifndef RUNANYWHERE_TYPES_H
#define RUNANYWHERE_TYPES_H
// ...

// runanywhere-commons (public)
#ifndef RAC_TYPES_H
#define RAC_TYPES_H
// ...
```

### Decision 3: Error Code Ranges — Strict Separation

**Problem Identified:** Error code overlap between layers.

**Resolution:** Non-overlapping error code ranges:

| Layer | Range | Examples |
|-------|-------|----------|
| `runanywhere-core` bridge | `0` to `-99` | `RA_SUCCESS=0`, `RA_ERROR_INIT_FAILED=-1` |
| `runanywhere-commons` | `-100` to `-999` | `RAC_ERROR_NOT_INITIALIZED=-100` |
| Backend-specific | `-1000` to `-1999` | (future expansion) |

**Mapping:** The Swift SDK maps commons errors to bridge errors at the boundary:
```swift
func mapCommonsError(_ commonsError: rac_result_t) -> ra_result_code {
    switch commonsError {
    case RAC_SUCCESS: return RA_SUCCESS
    case RAC_ERROR_NOT_INITIALIZED: return RA_ERROR_INIT_FAILED
    case RAC_ERROR_MODEL_NOT_LOADED: return RA_ERROR_MODEL_LOAD_FAILED
    default: return RA_ERROR_UNKNOWN
    }
}
```

### Decision 4: Capability Enum Alignment

**Problem Identified:** Capability enum values misaligned between layers.

**Resolution:** Commons capability values **align exactly** with existing bridge values:

```c
// rac_types.h (commons) - ALIGNED with types.h (core)
typedef enum {
    RAC_CAPABILITY_TEXT_GENERATION = 0,  // Matches RA_CAP_TEXT_GENERATION
    RAC_CAPABILITY_EMBEDDINGS = 1,       // Matches RA_CAP_EMBEDDINGS
    RAC_CAPABILITY_STT = 2,              // Matches RA_CAP_STT
    RAC_CAPABILITY_TTS = 3,              // Matches RA_CAP_TTS
    RAC_CAPABILITY_VAD = 4,              // Matches RA_CAP_VAD
    RAC_CAPABILITY_DIARIZATION = 5       // Matches RA_CAP_DIARIZATION
} rac_capability_type_t;
```

### Decision 5: Singleton/Registry Strategy — PROCESS-GLOBAL via Symbol Export

**Problem Identified:** `BackendRegistry::instance()` is function-local static, breaks across DSOs.

**Resolution:** Use **symbol visibility + weak symbol pattern**:

```cpp
// In runanywhere-commons (exported with default visibility)
namespace runanywhere {
namespace commons {

// Single global instance via exported symbol
__attribute__((visibility("default")))
ModuleRegistry& get_module_registry() {
    static ModuleRegistry instance;
    return instance;
}

} // namespace commons
} // namespace runanywhere
```

**For Android (multiple .so files):**
- `libracommons.so` owns the registry singleton (exported symbol)
- Backend libraries call `rac_module_register()` which calls the commons registry
- Load order enforced: commons first, then backends

### Decision 6: Backend Factory Pattern — C-Callable Wrappers

**Problem Identified:** `runanywhere-core` exports C++ factories (`runanywhere::create_llamacpp_backend()`) but plan assumed C exports.

**Resolution:** Commons provides C-callable wrapper functions that internally call C++ factories:

```cpp
// In runanywhere-commons/backends/llamacpp/src/rac_llm_llamacpp.cpp

#include "llamacpp_backend.h"  // runanywhere-core C++ header

extern "C" {

rac_result_t rac_llm_llamacpp_create(
    rac_llm_handle_t* out_handle,
    const rac_llamacpp_config_t* config
) {
    // Call C++ factory
    auto backend = runanywhere::create_llamacpp_backend();

    // Configure and initialize
    nlohmann::json cfg;
    cfg["context_length"] = config->context_length;
    cfg["gpu_layers"] = config->gpu_layers;
    // ...

    if (!backend->initialize(cfg)) {
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Store in handle map
    *out_handle = store_backend(std::move(backend));
    return RAC_SUCCESS;
}

} // extern "C"
```

### Decision 7: Modular Build Strategy — Separate Static Libraries

**Problem Identified:** Current iOS build produces single unified `.a` and XCFramework.

**Resolution:** `runanywhere-core` CMake produces **separate static libraries per backend**:

```cmake
# runanywhere-core/CMakeLists.txt additions

# Option for modular builds (used by runanywhere-commons)
option(RA_BUILD_MODULAR "Build backends as separate libraries" OFF)

if(RA_BUILD_MODULAR)
    # DON'T link backends into bridge
    # Each backend target produces its own .a
    add_library(runanywhere_bridge STATIC src/bridge/runanywhere_bridge.cpp)
    # No: target_link_libraries(runanywhere_bridge PRIVATE runanywhere_llamacpp)
else()
    # Current behavior for unified builds
    # ...
endif()
```

**Build Output:**
```
runanywhere-core/build/
├── librunanywhere_bridge.a        # Core bridge only (~500KB)
├── librunanywhere_llamacpp.a      # LlamaCpp only (~15MB)
├── librunanywhere_onnx.a          # ONNX only (~50MB)
└── librunanywhere_whispercpp.a    # WhisperCpp only (~8MB)
```

### Decision 8: Streaming Callback Compatibility

**Problem Identified:** New commons streaming callback has different signature than existing bridge.

**Resolution:** Commons provides **adapter wrappers** that bridge between old and new signatures:

```c
// Existing bridge callback (ra_types.h in core):
typedef bool (*ra_text_stream_callback)(const char* token, void* user_data);

// Commons callback (rac_llm.h) - more feature-rich:
typedef void (*rac_llm_stream_callback_t)(
    const char* token,
    bool is_complete,
    const rac_llm_result_t* result,
    void* context
);
```

**Adapter pattern in Swift:**
```swift
// Bridge old-style callback to new commons callback
let legacyCallback: ra_text_stream_callback = { token, userData in
    // Call new commons callback
    guard let token = token else { return true }
    let ctx = Unmanaged<StreamContext>.fromOpaque(userData!).takeUnretainedValue()
    ctx.newCallback(token, false, nil, ctx.userContext)
    return !ctx.cancelled
}
```

### Decision 9: Two Registry Systems — Swift as Orchestrator

**Problem Identified:** Swift SDK has `ModuleRegistry.swift` + `ServiceRegistry.swift`, plan adds C++ versions.

**Resolution:** **Swift SDK remains the orchestrator**, C++ commons provides backend-level registration only:

| Layer | Registry Purpose | When Used |
|-------|------------------|-----------|
| Swift `ModuleRegistry` | High-level module discovery, capabilities | App startup, service routing |
| Swift `ServiceRegistry` | Service factory management | Creating STT/LLM/TTS services |
| C++ `rac_module_*` | Backend self-registration | When XCFramework loads |

**Flow:**
1. App imports backend modules (e.g., `import LlamaCPPRuntime`)
2. Swift module calls `rac_backend_llamacpp_register()` → registers with C++ commons
3. Swift `ModuleRegistry.register(LlamaCPP.self)` → registers Swift-side factory
4. Service creation goes through Swift `ServiceRegistry` → calls C++ backend

### Decision 10: Linker Settings — Remove `-all_load` for Modular Builds

**Problem Identified:** `-all_load` defeats dead-stripping, nullifying size savings.

**Resolution:** Use selective linking in `Package.swift`:

```swift
// For backends that need full symbol export (ONNX with CoreML):
.unsafeFlags(["-ObjC"]), // Only ObjC categories, not -all_load

// For backends without ObjC:
// No special linker flags needed - dead stripping works

// Ensure backend registration symbols are preserved:
.unsafeFlags(["-Wl,-u,_rac_backend_llamacpp_register"])
```

### Decision 11: HTTP Operations — NOT in Platform Adapter

**Problem Identified:** `ra_platform_adapter.h` includes HTTP callbacks but plan says don't use them.

**Resolution:** Remove HTTP from platform adapter, document clearly:

```c
// rac_platform_adapter.h
typedef struct {
    // File system - IMPLEMENTED
    rac_result_t (*file_exists)(const char* path, bool* exists, void* ctx);
    // ...

    // HTTP - NOT IMPLEMENTED (returns RAC_ERROR_NOT_SUPPORTED)
    // All downloads handled by Swift SDK's DownloadService
    // These callbacks exist for future Android/Flutter use only
    rac_result_t (*http_request)(/* ... */);  // Returns RAC_ERROR_NOT_SUPPORTED
    rac_result_t (*http_download)(/* ... */); // Returns RAC_ERROR_NOT_SUPPORTED

    // Secure storage, logging, clock - IMPLEMENTED
    // ...
} rac_platform_adapter_t;
```

### Decision 12: Backend Capability Matrix — Verified Against Code

**Problem Identified:** Documentation claimed ONNX has diarization but code shows TODO.

**Resolution:** Verified capability matrix matching actual `runanywhere-core` implementation:

| Backend | TEXT_GEN | EMBEDDINGS | STT | TTS | VAD | DIARIZATION |
|---------|----------|------------|-----|-----|-----|-------------|
| **LlamaCpp** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **ONNX** | ❌ | ❌ | ✅ | ✅ | ✅ | ⚠️ TODO |
| **WhisperCpp** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |

**Note:** ONNX diarization is scaffolded but not implemented. Remove from advertised capabilities until complete.

### Decision 13: Platform Support — Explicit Exclusions

**Problem Identified:** watchOS mentioned as excluded but not formalized.

**Resolution:** Explicit platform support matrix:

| Platform | RACommons | RABackendLlamaCPP | RABackendONNX | Notes |
|----------|-----------|-------------------|---------------|-------|
| iOS 17+ | ✅ | ✅ | ✅ | Primary target |
| iOS Simulator | ✅ | ✅ | ✅ | arm64 + x86_64 |
| macOS 14+ | ✅ | ✅ | ✅* | *ONNX needs dylib |
| tvOS 17+ | ✅ | ❌ | ✅ | Limited use case |
| watchOS 10+ | ✅ | ❌ | ❌ | Too constrained |

---

## Architecture Overview

### High-Level Dependency Graph

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           CONSUMER APPLICATIONS                                  │
│  (iOS App, Android App, Flutter App, React Native App)                          │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          THIN PLATFORM WRAPPERS                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌─────────────────┐  ┌───────────┐ │
│  │ runanywhere-swift│  │ runanywhere-kotlin│  │runanywhere-flutter│ │   RN SDK  │ │
│  │   (Swift 6)      │  │    (KMP/JNI)     │  │     (dart:ffi)    │ │ (Nitrogen)│ │
│  │ - ModuleRegistry │  │                  │  │                   │ │           │ │
│  │ - ServiceRegistry│  │                  │  │                   │ │           │ │
│  │ - Async APIs     │  │                  │  │                   │ │           │ │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  └─────┬─────┘ │
└───────────┼─────────────────────┼─────────────────────┼─────────────────┼───────┘
            │                     │                     │                 │
            ▼                     ▼                     ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      runanywhere-commons (PUBLIC)                                │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                    C API Surface (rac_*.h headers)                          │ │
│  │  NEW APIs: rac_module_*, rac_event_* for registration/telemetry            │ │
│  │  PRESERVED: Uses ra_* APIs from bridge internally                           │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                     MODULAR BACKEND PACKAGES                                ││
│  │  Each produces SEPARATE XCFramework/JNILib                                  ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────┐ ││
│  │  │rac-backend-llama│  │rac-backend-onnx │  │rac-backend-whisper│ │rac-mlx │ ││
│  │  │    (.xcfwk)     │  │    (.xcfwk)     │  │    (.xcfwk)      │ │(.xcfwk) │ ││
│  │  │ TEXT_GENERATION │  │ STT/TTS/VAD     │  │ STT (native)     │ │(future) │ ││
│  │  │     ~15MB       │  │     ~50MB       │  │     ~8MB         │ │  ~20MB  │ ││
│  │  └────────┬────────┘  └────────┬────────┘  └────────┬─────────┘ └────┬────┘ ││
│  └───────────┼──────────────────────────────────────────┼──────────────┼───────┘│
└──────────────┼──────────────────────────────────────────┼──────────────┼────────┘
               │                     │                     │              │
               ▼                     ▼                     ▼              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      runanywhere-core (PRIVATE)                                  │
│  Built with RA_BUILD_MODULAR=ON → Separate .a per backend                       │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                        Backend Implementations                              │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │ │
│  │  │  llamacpp/      │  │     onnx/       │  │   whispercpp/   │  + future   │ │
│  │  │  ~15MB .a       │  │   ~50MB .a      │  │    ~8MB .a      │             │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘             │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                         Third-Party Libraries                              │ │
│  │  llama.cpp │ onnxruntime │ whisper.cpp │ Metal │ CoreML │ NNAPI           │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Visibility | Responsibility |
|-------|------------|----------------|
| **runanywhere-core** | Private | Raw inference backends, third-party library integration, produces separate `.a` per backend |
| **runanywhere-commons** | Public | C API wrappers (`rac_*`), module registry, event system, backend C wrappers |
| **Platform SDKs** | Public | **Thin wrappers** providing idiomatic APIs (Swift async/await, Kotlin coroutines), service orchestration |

---

## Package Composition Examples

Consumers can choose their backend combinations:

| Use Case | Packages Required | Binary Size (est.) |
|----------|-------------------|-------------------|
| LLM only (GGUF) | `RACommons` + `RABackendLlamaCPP` | ~16MB |
| STT only (ONNX) | `RACommons` + `RABackendONNX` | ~51MB |
| STT only (native) | `RACommons` + `RABackendWhisperCPP` | ~9MB |
| Full voice agent | `RACommons` + `RABackendLlamaCPP` + `RABackendONNX` | ~66MB |
| Apple Silicon LLM | `RACommons` + `RABackendMLX` | ~21MB (future) |

---

## ⚠️ Resolved Issues Summary

| # | Issue | Resolution | Phase |
|---|-------|------------|-------|
| 1 | Modular Build Not Implementable | Add `RA_BUILD_MODULAR` CMake option | Phase 0 |
| 2 | "Wrap Don't Replace" Contradicts Plan | Swift orchestrates, commons wraps existing APIs | Phase 3 |
| 3 | Three Competing C API Truths | Single truth: preserve `ra_*`, add `rac_*` | Phase 0/1 |
| 4 | Header Namespace Collision | Use `rac_` prefix for all commons headers | Phase 0 |
| 5 | ABI-Level Name Collisions | `rac_` prefix, separate error ranges | Phase 0 |
| 6 | Singleton Strategy Unsolved | Symbol visibility + process-global registry | Phase 1 |
| 7 | Backend Factory Mismatch | C wrappers call C++ factories | Phase 2 |
| 8 | Backend Combination Issues | Document GGML conflicts, test combos | Phase 4 |
| 9 | Two Parallel Orchestration Systems | Swift orchestrates, C++ provides backend registration | Phase 3 |
| 10 | Linker Defeats Size Savings | Remove `-all_load`, use selective linking | Phase 3 |
| 11 | Capability Enum Mismatch | Align values exactly: TEXT_GEN=0, STT=2, etc. | Phase 1 |
| 12 | ONNX Diarization TODO | Remove from advertised capabilities | Phase 2 |
| 13 | Platform Support Mismatch | Explicit matrix, exclude watchOS backends | Phase 0 |
| 14 | WhisperCpp Missing | Add WhisperCpp backend module | Phase 2 |
| 15 | Error Code Duplication | Strict range separation (`-100` to `-999`) | Phase 1 |
| 16 | Streaming Callback Breaking | Adapter pattern, both signatures supported | Phase 3 |
| 17 | HTTP in Platform Adapter | Return `RAC_ERROR_NOT_SUPPORTED` | Phase 1 |
| 18 | Worktree Path Confusion | Commons in `sdks/sdk/`, not worktree | Phase 0 |
| 19 | Missing `get_current_time_ms()` | Implement in commons core | Phase 1 |
| 20 | Version Sync Strategy | Single `VERSION` file, documented sync | Phase 0 |
| 21 | Binary Target Naming | Document migration path | Phase 4 |
| 22 | `ra_free()` vs Typed Free | Commons uses `rac_free()`, bridge keeps typed | Phase 1 |
| 23 | Test Helpers Non-Existent | Add `RunAnywhere.reset()` to public API | Phase 4 |
| 24 | BackendRegistry Comment Misleading | Fix comment, use process-global pattern | Phase 1 |

---

## Migration Phases Summary

| Phase | Duration | Focus | Key Deliverables |
|-------|----------|-------|------------------|
| **Phase 0** | 2 weeks | Foundation & Setup | `runanywhere-commons` skeleton, build system, CI |
| **Phase 1** | 3 weeks | Commons Core | Events, Registry, Lifecycle in C++ with `rac_` prefix |
| **Phase 2** | 3 weeks | Backend Modularization | Separate XCFrameworks per backend |
| **Phase 3** | 3 weeks | Swift SDK Integration | Refactor `runanywhere-swift` to use commons |
| **Phase 4** | 2 weeks | Testing & Polish | E2E testing, documentation, optimization |

**Total Duration**: ~13 weeks

---

## Repository Structure After Migration

```
runanywhere-all/
├── runanywhere-core/                    # PRIVATE - C++ backends (existing)
│   ├── CMakeLists.txt                   # + RA_BUILD_MODULAR option
│   ├── src/
│   │   ├── backends/
│   │   │   ├── llamacpp/                # → librunanywhere_llamacpp.a
│   │   │   ├── onnx/                    # → librunanywhere_onnx.a
│   │   │   └── whispercpp/              # → librunanywhere_whispercpp.a
│   │   ├── bridge/                      # → librunanywhere_bridge.a (core only)
│   │   └── capabilities/
│   └── third_party/
│
├── sdks/
│   └── sdk/
│       ├── runanywhere-commons/         # NEW - Public commons layer
│       │   ├── CMakeLists.txt
│       │   ├── VERSION                  # Single source of version truth
│       │   ├── include/                 # Public C API headers (rac_*.h)
│       │   │   ├── rac_core.h
│       │   │   ├── rac_types.h
│       │   │   ├── rac_error.h
│       │   │   └── ...
│       │   ├── backends/                # Modular backend wrappers
│       │   │   ├── llamacpp/            # Links to librunanywhere_llamacpp.a
│       │   │   ├── onnx/                # Links to librunanywhere_onnx.a
│       │   │   ├── whispercpp/          # Links to librunanywhere_whispercpp.a
│       │   │   └── mlx/                 # Future
│       │   ├── src/                     # Commons implementation
│       │   ├── scripts/
│       │   └── dist/                    # Output XCFrameworks
│       │
│       ├── runanywhere-swift/           # Updated to use commons
│       │   ├── Package.swift            # Modular binary targets
│       │   ├── Sources/
│       │   │   ├── CRACommons/          # Bridge to RACommons.xcframework
│       │   │   ├── CRABackendLlamaCPP/  # Bridge to RABackendLlamaCPP.xcframework
│       │   │   ├── CRABackendONNX/      # Bridge to RABackendONNX.xcframework
│       │   │   ├── RunAnywhere/         # Core SDK (Swift orchestration)
│       │   │   ├── LlamaCPPRuntime/     # LLM module
│       │   │   ├── ONNXRuntime/         # STT/TTS/VAD module
│       │   │   └── FoundationModelsAdapter/
│       │   └── Binaries/                # Local XCFrameworks for dev
│       │
│       ├── runanywhere-kotlin/          # Future: Use same commons
│       ├── runanywhere-flutter/
│       └── runanywhere-react-native/
```

---

## Related Documents

- `01_PHASE_0_FOUNDATION.md` - Phase 0: Directory structure, CMake, headers
- `02_PHASE_1_COMMONS_CORE.md` - Phase 1: Registry, events, lifecycle
- `03_PHASE_2_BACKEND_MODULARIZATION.md` - Phase 2: Backend modules
- `04_PHASE_3_SWIFT_INTEGRATION.md` - Phase 3: Swift SDK refactor
- `05_PHASE_4_TESTING.md` - Phase 4: Testing, docs, polish
- `06_DIRECTORY_STRUCTURE.md` - Complete directory layout

---

*Document updated: December 2025*
*Status: Planning (Addressing 24 identified inconsistencies)*
