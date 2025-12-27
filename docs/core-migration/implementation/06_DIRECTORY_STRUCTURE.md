# Directory Structure

## Complete Repository Layout After Migration

> **⚠️ KEY DECISION**: `runanywhere-commons` is placed in `sdks/sdk/` folder,
> as a sibling to `runanywhere-swift/`. Worktrees are for parallel branch development,
> while `runanywhere-commons` is a permanent package that all branches will use.

> **⚠️ SPLIT CORE STRATEGY**: `runanywhere-core` produces **separate static libraries**
> per backend. This is critical for achieving real binary size savings.

> **⚠️ HEADER PREFIX**: `runanywhere-commons` uses `rac_*` prefix for all headers
> to avoid namespace collision with existing `runanywhere-core` `ra_*` headers.

```
runanywhere-all/
│
├── runanywhere-core/                          # PRIVATE - C++ Inference Backends
│   ├── CMakeLists.txt                         # Supports RA_BUILD_MODULAR option
│   ├── README.md
│   ├── CLAUDE.md
│   │
│   ├── src/
│   │   ├── backends/                          # Raw backend implementations
│   │   │   ├── llamacpp/                      # → librunanywhere_llamacpp.a (~15MB)
│   │   │   │   ├── CMakeLists.txt
│   │   │   │   ├── llamacpp_backend.cpp
│   │   │   │   └── llamacpp_backend.h
│   │   │   │
│   │   │   ├── onnx/                          # → librunanywhere_onnx.a (~50MB)
│   │   │   │   ├── CMakeLists.txt
│   │   │   │   ├── onnx_backend.cpp
│   │   │   │   └── onnx_backend.h
│   │   │   │
│   │   │   └── whispercpp/                    # → librunanywhere_whispercpp.a (~8MB)
│   │   │       ├── CMakeLists.txt
│   │   │       ├── whispercpp_backend.cpp
│   │   │       └── whispercpp_backend.h
│   │   │
│   │   ├── bridge/                            # → librunanywhere_bridge.a (~500KB)
│   │   │   ├── runanywhere_bridge.cpp         # Existing C API (ra_*)
│   │   │   ├── runanywhere_bridge.h
│   │   │   └── jni/                           # Android JNI (existing)
│   │   │       ├── runanywhere_jni.cpp
│   │   │       └── runanywhere_loader.cpp
│   │   │
│   │   └── capabilities/                      # Capability interfaces
│   │       ├── backend.h                      # BackendRegistry singleton
│   │       ├── capability.h
│   │       ├── types.h                        # ra_result_code, ra_capability_type
│   │       ├── stt.h
│   │       ├── text_generation.h
│   │       ├── tts.h
│   │       └── vad.h
│   │
│   ├── third_party/                           # Submodules
│   │   ├── llama.cpp/
│   │   ├── onnxruntime/
│   │   └── whisper.cpp/
│   │
│   ├── cmake/
│   │   ├── ios.toolchain.cmake
│   │   └── ModularBuild.cmake                 # NEW: Defines per-backend targets
│   │
│   └── scripts/
│       ├── build-ios.sh
│       ├── build-android.sh
│       └── build-modular.sh                   # NEW: Builds separate .a files
│
│
├── sdks/                                      # MAIN SDK FOLDER (not worktree)
│   │
│   └── sdk/
│       │
│       ├── runanywhere-commons/               # NEW - Public Commons Layer
│       │   ├── CMakeLists.txt
│       │   ├── README.md
│       │   ├── VERSION                        # e.g., "1.0.0"
│       │   │
│       │   ├── include/                       # Public C API headers (rac_* prefix)
│       │   │   ├── rac_core.h                 # Initialization, shutdown
│       │   │   ├── rac_types.h                # Common type definitions
│       │   │   ├── rac_error.h                # Error codes (-100 to -999 range)
│       │   │   ├── rac_platform_adapter.h     # Platform adapter interface
│       │   │   ├── rac_events.h               # Event system
│       │   │   ├── rac_llm.h                  # Generic LLM API
│       │   │   ├── rac_stt.h                  # Generic STT API
│       │   │   ├── rac_tts.h                  # Generic TTS API
│       │   │   └── rac_vad.h                  # Generic VAD API
│       │   │
│       │   ├── src/                           # Commons implementation
│       │   │   ├── core/
│       │   │   │   ├── rac_core.cpp           # Initialization
│       │   │   │   └── rac_error.cpp          # Error handling
│       │   │   │
│       │   │   ├── registry/
│       │   │   │   ├── module_registry.cpp    # Module registration
│       │   │   │   └── service_registry.cpp   # Service factory registry
│       │   │   │
│       │   │   ├── events/
│       │   │   │   └── event_publisher.cpp    # Event publishing
│       │   │   │
│       │   │   └── lifecycle/
│       │   │       └── model_lifecycle.cpp    # Model lifecycle management
│       │   │
│       │   ├── backends/                      # Modular backend wrappers
│       │   │   │
│       │   │   ├── llamacpp/                  # LlamaCpp backend module
│       │   │   │   ├── CMakeLists.txt
│       │   │   │   ├── include/
│       │   │   │   │   └── rac_llm_llamacpp.h # LlamaCpp-specific API
│       │   │   │   └── src/
│       │   │   │       ├── rac_llm_llamacpp.cpp
│       │   │   │       └── llamacpp_registration.cpp
│       │   │   │
│       │   │   ├── onnx/                      # ONNX backend module
│       │   │   │   ├── CMakeLists.txt
│       │   │   │   ├── include/
│       │   │   │   │   ├── rac_stt_onnx.h
│       │   │   │   │   ├── rac_tts_onnx.h
│       │   │   │   │   └── rac_vad_onnx.h
│       │   │   │   └── src/
│       │   │   │       ├── rac_stt_onnx.cpp
│       │   │   │       ├── rac_tts_onnx.cpp
│       │   │   │       ├── rac_vad_onnx.cpp
│       │   │   │       └── onnx_registration.cpp
│       │   │   │
│       │   │   ├── whispercpp/                # WhisperCpp backend (native STT)
│       │   │   │   ├── CMakeLists.txt
│       │   │   │   ├── include/
│       │   │   │   │   └── rac_stt_whispercpp.h
│       │   │   │   └── src/
│       │   │   │       ├── rac_stt_whispercpp.cpp
│       │   │   │       └── whispercpp_registration.cpp
│       │   │   │
│       │   │   └── mlx/                       # Future: MLX backend (Apple Silicon)
│       │   │       ├── CMakeLists.txt
│       │   │       ├── include/
│       │   │       │   └── rac_llm_mlx.h
│       │   │       └── src/
│       │   │           └── rac_llm_mlx.cpp
│       │   │
│       │   ├── tests/                         # C++ unit tests
│       │   │   ├── CMakeLists.txt
│       │   │   ├── test_module_registry.cpp
│       │   │   ├── test_service_registry.cpp
│       │   │   ├── test_event_publisher.cpp
│       │   │   └── test_error_codes.cpp
│       │   │
│       │   ├── cmake/
│       │   │   ├── ios.toolchain.cmake
│       │   │   ├── android.toolchain.cmake
│       │   │   └── FindRunAnywhereCore.cmake
│       │   │
│       │   ├── scripts/
│       │   │   ├── build-xcframeworks.sh      # Build iOS XCFrameworks
│       │   │   ├── build-android.sh           # Build Android .so files
│       │   │   ├── build-all.sh               # Build all platforms
│       │   │   ├── package-release.sh         # Create release artifacts
│       │   │   ├── analyze-binary-size.sh     # Size analysis
│       │   │   └── strip-symbols.sh           # Symbol stripping
│       │   │
│       │   └── dist/                          # Build output (gitignored)
│       │       ├── apple/
│       │       │   ├── RACommons.xcframework/
│       │       │   ├── RABackendLlamaCPP.xcframework/
│       │       │   ├── RABackendONNX.xcframework/
│       │       │   └── RABackendWhisperCPP.xcframework/
│       │       │
│       │       └── android/
│       │           ├── arm64-v8a/
│       │           │   ├── libracommons.so
│       │           │   ├── librabackend_llamacpp.so
│       │           │   ├── librabackend_onnx.so
│       │           │   └── librabackend_whispercpp.so
│       │           ├── armeabi-v7a/
│       │           └── x86_64/
│       │
│       │
│       ├── runanywhere-swift/                 # iOS/macOS Swift SDK
│       │   ├── Package.swift                  # Updated with modular targets
│       │   ├── README.md
│       │   ├── ARCHITECTURE.md
│       │   ├── MIGRATION.md                   # NEW - Migration guide v1→v2
│       │   │
│       │   ├── Binaries/                      # Local XCFrameworks for dev
│       │   │   ├── README.md
│       │   │   ├── RACommons.xcframework/     # Optional - for local dev
│       │   │   ├── RABackendLlamaCPP.xcframework/
│       │   │   └── RABackendONNX.xcframework/
│       │   │
│       │   └── Sources/
│       │       ├── RunAnywhere/               # Core SDK
│       │       │   ├── Public/
│       │       │   │   └── RunAnywhere.swift  # Updated with reset() method
│       │       │   ├── Core/
│       │       │   │   ├── Module/
│       │       │   │   │   └── ModuleRegistry.swift
│       │       │   │   └── ServiceRegistry.swift
│       │       │   ├── Features/
│       │       │   ├── Infrastructure/
│       │       │   ├── Foundation/
│       │       │   │   ├── Platform/          # NEW
│       │       │   │   │   └── SwiftPlatformAdapter.swift
│       │       │   │   └── Errors/
│       │       │   │       └── CommonsErrorMapping.swift  # NEW
│       │       │   └── Data/
│       │       │
│       │       ├── CRACommons/                # NEW - C Bridge for Commons
│       │       │   ├── include/
│       │       │   │   ├── CRACommons.h       # Umbrella header
│       │       │   │   ├── rac_core.h         # Copied from commons
│       │       │   │   ├── rac_types.h
│       │       │   │   ├── rac_error.h
│       │       │   │   ├── rac_events.h
│       │       │   │   ├── rac_platform_adapter.h
│       │       │   │   ├── rac_llm.h
│       │       │   │   ├── rac_stt.h
│       │       │   │   ├── rac_tts.h
│       │       │   │   ├── rac_vad.h
│       │       │   │   └── module.modulemap
│       │       │   └── dummy.c
│       │       │
│       │       ├── CRABackendLlamaCPP/        # NEW - C Bridge for LlamaCpp
│       │       │   ├── include/
│       │       │   │   ├── CRABackendLlamaCPP.h
│       │       │   │   ├── rac_llm_llamacpp.h
│       │       │   │   └── module.modulemap
│       │       │   └── dummy.c
│       │       │
│       │       ├── CRABackendONNX/            # NEW - C Bridge for ONNX
│       │       │   ├── include/
│       │       │   │   ├── CRABackendONNX.h
│       │       │   │   ├── rac_stt_onnx.h
│       │       │   │   ├── rac_tts_onnx.h
│       │       │   │   ├── rac_vad_onnx.h
│       │       │   │   └── module.modulemap
│       │       │   └── dummy.c
│       │       │
│       │       ├── LlamaCPPRuntime/           # Updated to use new XCFramework
│       │       │   ├── LlamaCPPRuntime.swift  # Dual registration (C++ + Swift)
│       │       │   ├── LlamaCPPService.swift  # Uses rac_llm_llamacpp_* APIs
│       │       │   └── LlamaCPPServiceProvider.swift
│       │       │
│       │       ├── ONNXRuntime/               # Updated to use new XCFramework
│       │       │   ├── ONNXRuntime.swift
│       │       │   ├── ONNXSTTService.swift
│       │       │   ├── ONNXTTSService.swift
│       │       │   └── ONNXServiceProvider.swift
│       │       │
│       │       └── FoundationModelsAdapter/   # Apple AI (unchanged)
│       │           └── ...
│       │
│       ├── runanywhere-kotlin/                # Android KMP SDK (future)
│       ├── runanywhere-flutter/               # Flutter SDK (future)
│       └── runanywhere-react-native/          # React Native SDK (future)
│
│
└── docs/
    └── core-migration/
        ├── implementation/                    # This folder - SOURCE OF TRUTH
        │   ├── 00_IMPLEMENTATION_OVERVIEW.md
        │   ├── 01_PHASE_0_FOUNDATION.md
        │   ├── 02_PHASE_1_COMMONS_CORE.md
        │   ├── 03_PHASE_2_BACKEND_MODULARIZATION.md
        │   ├── 04_PHASE_3_SWIFT_INTEGRATION.md
        │   ├── 05_PHASE_4_TESTING.md
        │   ├── 06_DIRECTORY_STRUCTURE.md
        │   └── README.md
        │
        ├── ALL_CORE_MIGRATION_DOCS.md         # Reference only
        ├── CORE_MIGRATION_OVERVIEW.md
        └── ... (other migration docs)
```

---

## Key New Directories

| Directory | Purpose |
|-----------|---------|
| `runanywhere-commons/` | New public C/C++ layer with `rac_*` API |
| `runanywhere-commons/include/` | Public C API headers (`rac_*.h`) |
| `runanywhere-commons/backends/` | Modular backend modules |
| `runanywhere-commons/dist/` | Built artifacts (XCFrameworks, .so) |
| `Sources/CRACommons/` | Swift bridge to commons |
| `Sources/CRABackendLlamaCPP/` | Swift bridge to LlamaCpp |
| `Sources/CRABackendONNX/` | Swift bridge to ONNX |

---

## Header Namespace Strategy

### runanywhere-core (existing, unchanged)
- Prefix: `ra_*`
- Headers: `ra_types.h`, `runanywhere_bridge.h`
- Error codes: `RA_SUCCESS`, `RA_ERROR_*` (-1 to -99)
- Capabilities: `RA_CAP_*`

### runanywhere-commons (new)
- Prefix: `rac_*`
- Headers: `rac_core.h`, `rac_types.h`, `rac_error.h`, etc.
- Error codes: `RAC_SUCCESS`, `RAC_ERROR_*` (-100 to -999)
- Capabilities: `RAC_CAPABILITY_*`

### Swift SDK Mapping
The Swift SDK maps between both APIs:
- Calls `runanywhere-commons` (`rac_*`) for orchestration
- Error codes mapped via `rac_result_t.toSDKError()`
- Capabilities mapped internally

---

## Binary Artifacts

### iOS/macOS/tvOS/watchOS XCFrameworks

> **Note**: The Swift SDK (`runanywhere-swift/Package.swift`) supports multiple Apple platforms:
> - iOS 17+ / iOS Simulator
> - macOS 14+
> - tvOS 17+ / tvOS Simulator
> - watchOS 10+ / watchOS Simulator
>
> All XCFrameworks must include slices for each supported platform to maintain compatibility.

```
dist/apple/
├── RACommons.xcframework              # Core commons (~1.5 MB per slice)
│   ├── ios-arm64/                     # iPhone, iPad
│   ├── ios-arm64_x86_64-simulator/    # iOS Simulator (Universal)
│   ├── macos-arm64_x86_64/            # macOS (Universal Binary)
│   ├── tvos-arm64/                    # Apple TV
│   ├── tvos-arm64_x86_64-simulator/   # tvOS Simulator
│   ├── watchos-arm64_32_armv7k/       # Apple Watch
│   └── watchos-arm64_x86_64-simulator/# watchOS Simulator
│
├── RABackendLlamaCPP.xcframework      # LlamaCpp backend (~20 MB per slice)
│   ├── ios-arm64/
│   ├── ios-arm64_x86_64-simulator/
│   ├── macos-arm64_x86_64/
│   ├── tvos-arm64/                    # If Metal support available
│   └── tvos-arm64_x86_64-simulator/
│   # Note: watchOS excluded due to model size constraints
│
└── RABackendONNX.xcframework          # ONNX backend (~60 MB per slice)
    ├── ios-arm64/
    ├── ios-arm64_x86_64-simulator/
    ├── macos-arm64_x86_64/
    ├── tvos-arm64/
    └── tvos-arm64_x86_64-simulator/
    # Note: watchOS excluded - ONNX Runtime too large
```

### Size Targets

| Framework | Target | Max Allowed |
|-----------|--------|-------------|
| RACommons.xcframework | < 1.5 MB | 2 MB |
| RABackendLlamaCPP.xcframework | < 20 MB | 25 MB |
| RABackendONNX.xcframework | < 60 MB | 70 MB |

### Platform-Specific Build Notes

| Platform | LlamaCpp Support | ONNX Support | Notes |
|----------|-----------------|--------------|-------|
| iOS | ✅ Full | ✅ Full | Primary target |
| iOS Simulator | ✅ Full | ✅ Full | Required for development |
| macOS | ✅ Full | ✅ Full | Universal binary (arm64 + x86_64) |
| tvOS | ⚠️ Limited | ✅ Full | Metal available, but large models impractical |
| watchOS | ❌ Excluded | ❌ Excluded | Too constrained for ML models |

### Android Native Libraries

```
dist/android/
├── arm64-v8a/
│   ├── libracommons.so                # Core commons (owns singleton registry)
│   ├── librabackend_llamacpp.so       # Dynamically loaded
│   ├── librabackend_onnx.so           # Dynamically loaded
│   └── librabackend_whispercpp.so     # Dynamically loaded
├── armeabi-v7a/
│   └── ...
└── x86_64/                            # For emulators
    └── ...
```

### Android Singleton Strategy

On Android, `libracommons.so` owns the singleton registries. Backend `.so` files are loaded dynamically using `dlopen()` to avoid multiple registry instances across shared libraries.

---

## Dependency Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         App Layer                                │
│  (imports RunAnywhere + RunAnywhereLlamaCPP/ONNX as needed)     │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                    Swift SDK Layer                               │
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────────┐    │
│  │  RunAnywhere │  │ LlamaCPPRuntime │  │   ONNXRuntime    │    │
│  │   (Core)     │  │   (Backend)     │  │    (Backend)     │    │
│  └──────┬───────┘  └────────┬────────┘  └────────┬─────────┘    │
│         │                   │                    │               │
│  ┌──────▼───────┐  ┌────────▼────────┐  ┌───────▼──────────┐    │
│  │  CRACommons  │  │CRABackendLlamaCPP│ │  CRABackendONNX  │    │
│  │ (C Bridge)   │  │   (C Bridge)    │  │    (C Bridge)    │    │
│  └──────┬───────┘  └────────┬────────┘  └───────┬──────────┘    │
└─────────┼───────────────────┼───────────────────┼───────────────┘
          │                   │                   │
┌─────────▼───────────────────▼───────────────────▼───────────────┐
│                   XCFramework Layer                              │
│  ┌──────────────┐  ┌───────────────────┐  ┌─────────────────┐   │
│  │ RACommons    │  │RABackendLlamaCPP  │  │  RABackendONNX  │   │
│  │ .xcframework │  │   .xcframework    │  │   .xcframework  │   │
│  │ (rac_* API)  │  │ (rac_llm_llamacpp)│  │(rac_stt/tts_onnx)│  │
│  └──────┬───────┘  └────────┬──────────┘  └────────┬────────┘   │
└─────────┼───────────────────┼─────────────────────┼─────────────┘
          │                   │                     │
┌─────────▼───────────────────▼─────────────────────▼─────────────┐
│                  runanywhere-commons                             │
│  (C/C++ orchestration layer, links to runanywhere-core)         │
│  - Module Registry (C++)                                         │
│  - Service Registry (C++)                                        │
│  - Event Publisher (C++)                                         │
│  - Platform Adapter calls                                        │
└─────────────────────────────┬───────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────┐
│                     runanywhere-core                             │
│  (Private C++ backends: llama.cpp, onnxruntime, whisper.cpp)    │
│  - Produces separate .a files when RA_BUILD_MODULAR=ON          │
│  - Existing ra_* C API unchanged                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Package.swift Target Mapping

```swift
// Swift targets and their corresponding C bridges + XCFrameworks

// RunAnywhere (core)
//   └── CRACommons (C bridge)
//       └── RACommonsBinary (XCFramework)

// LlamaCPPRuntime (backend)
//   ├── RunAnywhere
//   ├── CRABackendLlamaCPP (C bridge)
//   │   └── CRACommons
//   └── RABackendLlamaCPPBinary (XCFramework)

// ONNXRuntime (backend)
//   ├── RunAnywhere
//   ├── CRABackendONNX (C bridge)
//   │   └── CRACommons
//   └── RABackendONNXBinary (XCFramework)
```

---

*Document generated: December 2025*
