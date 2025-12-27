# RunAnywhere Commons: Implementation Overview

## Goal

Create `runanywhere-commons`, a public C/C++ layer that enables **modular backend packaging** for platform SDKs.

**Key Benefits:**
1. **Binary size optimization** - Include only backends you need
2. **Separate XCFrameworks per backend** - LlamaCpp (~15MB), ONNX (~50MB), WhisperCpp (~8MB)
3. **Shared orchestration logic** - Module registry, events, lifecycle in C++
4. **Thin platform wrappers** - Swift/Kotlin SDKs become lightweight wrappers

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CONSUMER APPS                                │
│  (iOS, Android, Flutter, React Native)                              │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────┐
│                    PLATFORM SDK WRAPPERS                             │
│  runanywhere-swift │ runanywhere-kotlin │ flutter │ react-native    │
│  - Async APIs, idiomatic bindings                                    │
│  - ModuleRegistry, ServiceRegistry (Swift orchestrates)              │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────┐
│                    runanywhere-commons (NEW)                         │
│  C API: rac_core.h, rac_events.h, rac_llm.h, rac_stt.h, etc.        │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                 MODULAR BACKEND PACKAGES                        │ │
│  │  RACommons.xcframework    (~1MB)  - Core only                   │ │
│  │  RABackendLlamaCPP.xcframework (~15MB) - LLM                    │ │
│  │  RABackendONNX.xcframework (~50MB)  - STT/TTS/VAD               │ │
│  │  RABackendWhisperCPP.xcframework (~8MB) - Native STT            │ │
│  └────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────────────┐
│                    runanywhere-core (PRIVATE)                        │
│  C++ backends: llamacpp, onnx, whispercpp                           │
│  Built with RA_BUILD_MODULAR=ON → separate .a per backend           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Current State

| Component | Status | Notes |
|-----------|--------|-------|
| `runanywhere-core` | Exists | Backends linked into single library |
| `runanywhere-swift` | Exists | Uses monolithic `RunAnywhereCoreBinary` |
| `runanywhere-commons` | **Not started** | This plan creates it |
| Modular build | **Not implemented** | Need to add `RA_BUILD_MODULAR` option |

---

## Design Decisions

### 1. API Prefix: `rac_*` for Commons

Commons uses `rac_` prefix to avoid collision with existing `ra_*` APIs in runanywhere-core.

| Layer | Prefix | Example |
|-------|--------|---------|
| runanywhere-core | `ra_*` | `ra_create_backend()`, `RA_SUCCESS` |
| runanywhere-commons | `rac_*` | `rac_module_register()`, `RAC_SUCCESS` |

### 2. Error Code Ranges

| Layer | Range | Examples |
|-------|-------|----------|
| runanywhere-core | `0` to `-99` | `RA_SUCCESS=0`, `RA_ERROR_INIT_FAILED=-1` |
| runanywhere-commons | `-100` to `-999` | `RAC_ERROR_NOT_INITIALIZED=-100` |

### 3. Swift as Orchestrator

Swift SDK remains the primary orchestrator. Commons provides **backend-level registration** only.

| Layer | Registry Purpose |
|-------|------------------|
| Swift `ModuleRegistry` | High-level module discovery |
| Swift `ServiceRegistry` | Service factory management |
| C++ `rac_module_*` | Backend self-registration when XCFramework loads |

### 4. Capability Alignment

Commons capability values align with existing runanywhere-core values:

```c
typedef enum {
    RAC_CAPABILITY_TEXT_GENERATION = 0,  // = RA_CAP_TEXT_GENERATION
    RAC_CAPABILITY_EMBEDDINGS = 1,       // = RA_CAP_EMBEDDINGS
    RAC_CAPABILITY_STT = 2,              // = RA_CAP_STT
    RAC_CAPABILITY_TTS = 3,              // = RA_CAP_TTS
    RAC_CAPABILITY_VAD = 4,              // = RA_CAP_VAD
    RAC_CAPABILITY_DIARIZATION = 5       // = RA_CAP_DIARIZATION
} rac_capability_type_t;
```

### 5. Backend Capability Matrix

| Backend | TEXT_GEN | STT | TTS | VAD |
|---------|----------|-----|-----|-----|
| LlamaCpp | ✅ | ❌ | ❌ | ❌ |
| ONNX | ❌ | ✅ | ✅ | ✅ |
| WhisperCpp | ❌ | ✅ | ❌ | ❌ |

---

## Package Composition Examples

| Use Case | Packages | Size (est.) |
|----------|----------|-------------|
| LLM only | RACommons + RABackendLlamaCPP | ~16MB |
| Voice only (ONNX) | RACommons + RABackendONNX | ~51MB |
| Voice only (native) | RACommons + RABackendWhisperCPP | ~9MB |
| Full voice agent | All backends | ~66MB |

---

## Migration Phases

| Phase | Duration | Focus |
|-------|----------|-------|
| **Phase 0** | 2 weeks | Foundation - directory structure, CMake, build scripts |
| **Phase 1** | 3 weeks | Commons Core - registry, events, lifecycle in C++ |
| **Phase 2** | 3 weeks | Backend Modularization - separate XCFrameworks |
| **Phase 3** | 3 weeks | Swift Integration - refactor SDK to use commons |
| **Phase 4** | 2 weeks | Testing & Polish - E2E tests, documentation |

**Total: ~13 weeks**

---

## Repository Structure After Migration

```
runanywhere-all/
├── runanywhere-core/                 # PRIVATE - C++ backends
│   ├── CMakeLists.txt                # + RA_BUILD_MODULAR option
│   └── src/backends/{llamacpp,onnx,whispercpp}/
│
└── sdks/sdk/
    ├── runanywhere-commons/          # NEW - Public C/C++ layer
    │   ├── include/rac_*.h           # Public C API headers
    │   ├── src/                      # Commons implementation
    │   ├── backends/                 # Backend wrappers
    │   └── dist/                     # Built XCFrameworks
    │
    └── runanywhere-swift/            # Updated to use modular commons
        ├── Package.swift             # Modular binary targets
        └── Sources/
            ├── CRACommons/           # C bridge to RACommons
            ├── CRABackendLlamaCPP/   # C bridge to LlamaCpp
            └── ...
```

---

## Related Documents

| Document | Description |
|----------|-------------|
| [01_PHASE_0_FOUNDATION.md](./01_PHASE_0_FOUNDATION.md) | Directory structure, CMake, build scripts |
| [02_PHASE_1_COMMONS_CORE.md](./02_PHASE_1_COMMONS_CORE.md) | Registry, events, lifecycle implementation |
| [03_PHASE_2_BACKEND_MODULARIZATION.md](./03_PHASE_2_BACKEND_MODULARIZATION.md) | Backend modules, XCFrameworks |
| [04_PHASE_3_SWIFT_INTEGRATION.md](./04_PHASE_3_SWIFT_INTEGRATION.md) | Swift SDK refactor |
| [05_PHASE_4_TESTING.md](./05_PHASE_4_TESTING.md) | Testing, docs, optimization |
| [06_DIRECTORY_STRUCTURE.md](./06_DIRECTORY_STRUCTURE.md) | Complete directory layout |

---

*Last Updated: December 2025*
