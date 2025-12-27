# RunAnywhere Commons Implementation Plan

**⚠️ THIS FOLDER IS THE SINGLE SOURCE OF TRUTH FOR THE CORE MIGRATION IMPLEMENTATION**

This folder contains the detailed implementation plan for creating `runanywhere-commons` - a modular native layer that bridges `runanywhere-core` (private inference backends) with platform SDKs (iOS Swift, Android Kotlin, Flutter, React Native).

## Key Design Decisions

### 1. Header Namespace: `rac_*` Prefix
- `runanywhere-commons` uses `rac_*` prefix for all headers
- Avoids collision with existing `runanywhere-core` `ra_*` headers
- Swift SDK maps between both APIs internally

### 2. Swift as Orchestrator
- Swift SDK (`ModuleRegistry`, `ServiceRegistry`) remains the primary orchestrator
- C++ commons provides backend-level registration only
- Dual registration: backends register with both C++ and Swift registries

### 3. Split Core Build Strategy
- `runanywhere-core` produces **separate static libraries per backend**
- `RA_BUILD_MODULAR=ON` CMake flag enables this mode
- Each backend links only its dependencies (no monolithic library)

### 4. Error Code Ranges
- `runanywhere-core` (existing): `-1` to `-99` (`RA_ERROR_*`)
- `runanywhere-commons` (new): `-100` to `-999` (`RAC_ERROR_*`)
- Swift SDK maps between both systems

### 5. HTTP Stays in Swift
- Platform adapter does NOT implement HTTP operations
- Returns `RAC_ERROR_NOT_SUPPORTED` for HTTP callbacks
- Swift SDK's `DownloadService` handles all networking

---

## Documents

| Document | Description |
|----------|-------------|
| [00_IMPLEMENTATION_OVERVIEW.md](./00_IMPLEMENTATION_OVERVIEW.md) | Executive summary, architecture, **24 issues & resolutions** |
| [01_PHASE_0_FOUNDATION.md](./01_PHASE_0_FOUNDATION.md) | Phase 0: Directory structure, CMake setup, build scripts |
| [02_PHASE_1_COMMONS_CORE.md](./02_PHASE_1_COMMONS_CORE.md) | Phase 1: Module registry, service registry, events, lifecycle |
| [03_PHASE_2_BACKEND_MODULARIZATION.md](./03_PHASE_2_BACKEND_MODULARIZATION.md) | Phase 2: Split backends into separate XCFrameworks/AARs |
| [04_PHASE_3_SWIFT_INTEGRATION.md](./04_PHASE_3_SWIFT_INTEGRATION.md) | Phase 3: Refactor Swift SDK to use new modular XCFrameworks |
| [05_PHASE_4_TESTING.md](./05_PHASE_4_TESTING.md) | Phase 4: E2E testing, binary size tracking, documentation |
| [06_DIRECTORY_STRUCTURE.md](./06_DIRECTORY_STRUCTURE.md) | Complete directory layout after migration |

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           CONSUMER APPLICATIONS                                  │
│  (iOS App, Android App, Flutter App, React Native App)                          │
└─────────────────────────────┬───────────────────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────────────────┐
│                          THIN PLATFORM WRAPPERS                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  ┌──────────┐ │
│  │ runanywhere-swift│  │ runanywhere-kotlin│  │runanywhere-flutter│ │   RN SDK │ │
│  │   (Swift 6)      │  │    (KMP/JNI)     │  │     (dart:ffi)   │  │(Nitrogen)│ │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘  └────┬─────┘ │
└───────────┼─────────────────────┼─────────────────────┼─────────────────┼───────┘
            │                     │                     │                 │
            ▼                     ▼                     ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      runanywhere-commons (PUBLIC)                                │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                   C API Surface (rac_*.h headers)                          │ │
│  │  NEW orchestration APIs: rac_module_*, rac_event_*, rac_platform_*         │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────────┐│
│  │                     MODULAR BACKEND PACKAGES                                ││
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌───────────────────┐  ┌───────┐ ││
│  │  │ ra-backend-llama│  │ ra-backend-onnx │  │ra-backend-whisper │  │ra-mlx │ ││
│  │  │    (.xcfwk)     │  │    (.xcfwk)     │  │     (.xcfwk)      │  │(future)│ ││
│  │  │ LLM capability  │  │ STT/TTS/VAD     │  │  STT (native)     │  │        │ ││
│  │  └─────────────────┘  └─────────────────┘  └───────────────────┘  └───────┘ ││
│  └─────────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      runanywhere-core (PRIVATE)                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                        Backend Implementations                              │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │ │
│  │  │  llamacpp/      │  │     onnx/       │  │   whispercpp/   │  + future   │ │
│  │  │ text generation │  │ STT/TTS/VAD     │  │  native whisper │             │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘             │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │                         Third-Party Libraries                              │ │
│  │  llama.cpp │ onnxruntime │ whisper.cpp │ Metal │ CoreML │ NNAPI           │ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase Summary (13 Weeks Total)

```
Phase 0 (2 weeks)  ──► Phase 1 (3 weeks)  ──► Phase 2 (3 weeks)
   Foundation           Commons Core          Backend Modules
   - Create dirs        - Module registry     - Split XCFrameworks
   - CMake setup        - Service registry    - Backend registration
   - Build scripts      - Event publisher     - Symbol visibility
   - CI pipeline        - Platform adapter    - Android AARs
                                                    │
                                                    ▼
Phase 4 (2 weeks)  ◄── Phase 3 (3 weeks)
   Testing              Swift Integration
   - E2E tests          - Update Package.swift
   - Size tracking      - Create C bridges
   - Performance        - Platform adapter impl
   - Documentation      - Dual registration
```

---

## Binary Size Targets

| Package | Target | Max |
|---------|--------|-----|
| RACommons.xcframework | < 1.5 MB | 2 MB |
| RABackendLlamaCPP.xcframework | < 20 MB | 25 MB |
| RABackendONNX.xcframework | < 60 MB | 70 MB |

**Size Savings Example:**
- LLM only: ~20 MB (vs ~70 MB all-in-one)
- Voice only: ~60 MB (vs ~70 MB all-in-one)

---

## Getting Started

1. **Read Overview**: [00_IMPLEMENTATION_OVERVIEW.md](./00_IMPLEMENTATION_OVERVIEW.md)
2. **Check Prerequisites**: Ensure `runanywhere-core` can build modular (`RA_BUILD_MODULAR=ON`)
3. **Start Phase 0**: [01_PHASE_0_FOUNDATION.md](./01_PHASE_0_FOUNDATION.md)
4. **Execute Sequentially**: Each phase depends on the previous

---

## Reference Documents (Do NOT treat as source of truth)

- [../ALL_CORE_MIGRATION_DOCS.md](../ALL_CORE_MIGRATION_DOCS.md) - Historical analysis reference only
- [../CORE_MIGRATION_OVERVIEW.md](../CORE_MIGRATION_OVERVIEW.md) - Original assessment
- [../IOS_CORE_FEASIBILITY.md](../IOS_CORE_FEASIBILITY.md) - iOS SDK analysis

---

*Last Updated: December 2025*
*Status: Ready for Implementation*
