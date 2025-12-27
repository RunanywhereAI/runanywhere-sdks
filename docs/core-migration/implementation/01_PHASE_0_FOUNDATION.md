# Phase 0: Foundation & Setup

**Duration**: 2 weeks
**Objective**: Create the `runanywhere-commons` package structure and build infrastructure.

---

## ⚠️ Prerequisites: Required Changes to runanywhere-core

Before starting Phase 0, the following changes **MUST** be made to `runanywhere-core` to enable modular backend packaging.

### 1. Add `RA_BUILD_MODULAR` CMake Option

**Current Problem**: The CMakeLists.txt always links enabled backends into `runanywhere_bridge`:

```cmake
# Current behavior (unified build):
if(RA_BUILD_LLAMACPP)
    target_link_libraries(runanywhere_bridge PRIVATE runanywhere_llamacpp)
    target_compile_definitions(runanywhere_bridge PRIVATE RA_LLAMACPP_ENABLED=1)
endif()
```

**Required Change**: Add modular build option that **doesn't** link backends into the bridge:

```cmake
# runanywhere-core/CMakeLists.txt

# NEW: Option for modular builds (used by runanywhere-commons)
option(RA_BUILD_MODULAR "Build backends as separate libraries without linking into bridge" OFF)

# ... (after runanywhere_bridge is defined) ...

if(NOT RA_BUILD_MODULAR)
    # Current behavior: link backends into bridge
    if(RA_BUILD_LLAMACPP)
        target_link_libraries(runanywhere_bridge PRIVATE runanywhere_llamacpp)
        target_compile_definitions(runanywhere_bridge PRIVATE RA_LLAMACPP_ENABLED=1)
    endif()
    # ... other backends ...
else()
    # Modular mode: backends stay separate
    # - runanywhere_bridge.a contains only core functionality
    # - runanywhere_llamacpp.a contains llamacpp backend
    # - runanywhere_onnx.a contains onnx backend
    # - etc.
    message(STATUS "Modular build: Backends will NOT be linked into bridge")
endif()
```

### 2. Export Backend Create/Destroy Functions with C Linkage

**Current Problem**: Backend factories are C++ only (`runanywhere::create_llamacpp_backend()`):

```cpp
// Current: llamacpp_backend.h
namespace runanywhere {
    RA_LLAMACPP_EXPORT std::unique_ptr<Backend> create_llamacpp_backend();
    RA_LLAMACPP_EXPORT void register_llamacpp_backend();
}
```

**Required Change**: Add C-linkage wrappers in backend headers:

```cpp
// Updated: llamacpp_backend.h

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Create LlamaCpp backend instance (C-linkage wrapper)
 * @param out_backend Output: opaque handle to backend
 * @return 0 on success, negative error code on failure
 */
RA_LLAMACPP_EXPORT int ra_llamacpp_create(void** out_backend);

/**
 * Destroy LlamaCpp backend instance
 */
RA_LLAMACPP_EXPORT void ra_llamacpp_destroy(void* backend);

/**
 * Initialize with JSON config
 */
RA_LLAMACPP_EXPORT int ra_llamacpp_initialize(void* backend, const char* config_json);

#ifdef __cplusplus
}

// C++ API (existing)
namespace runanywhere {
    RA_LLAMACPP_EXPORT std::unique_ptr<Backend> create_llamacpp_backend();
}
#endif
```

### 3. Ensure Backend Static Libraries Are Self-Contained

Each backend `.a` must include all necessary symbols:

```cmake
# backends/llamacpp/CMakeLists.txt

add_library(runanywhere_llamacpp STATIC
    llamacpp_backend.cpp
    llamacpp_c_api.cpp  # NEW: C wrapper implementations
)

# Include all llama.cpp dependencies
target_link_libraries(runanywhere_llamacpp PRIVATE
    llama
    ggml
    # ... llama.cpp dependencies ...
)

# Ensure symbols are preserved
if(APPLE)
    set_target_properties(runanywhere_llamacpp PROPERTIES
        XCODE_ATTRIBUTE_STRIP_STYLE "non-global"
    )
endif()
```

### Prerequisites Checklist

Before proceeding to Task 0.1:

- [ ] `RA_BUILD_MODULAR` CMake option added to `runanywhere-core/CMakeLists.txt`
- [ ] C-linkage wrapper functions added to each backend header
- [ ] Verified separate `.a` files produced: `librunanywhere_bridge.a`, `librunanywhere_llamacpp.a`, etc.
- [ ] Build script updated: `runanywhere-core/scripts/build-ios.sh` supports `RA_BUILD_MODULAR=ON`
- [ ] Verified: linking only `librunanywhere_bridge.a` produces working (but backend-less) library

---

## Tasks Overview

| Task ID | Description | Effort | Dependencies |
|---------|-------------|--------|--------------|
| 0.1 | Create `runanywhere-commons` directory structure | 1 day | Prerequisites |
| 0.2 | Set up CMake build system with modular backends | 2 days | 0.1 |
| 0.3 | Define public C API headers (`rac_*.h`) | 2 days | 0.1 |
| 0.4 | Create iOS XCFramework build script | 2 days | 0.2, 0.3 |
| 0.5 | Create Android .so build script | 2 days | 0.2, 0.3 |
| 0.6 | Set up GitHub Actions CI | 2 days | 0.4, 0.5 |

---

## Task 0.1: Create Directory Structure

### Location

> **⚠️ IMPORTANT**: The commons package goes in `sdks/sdk/` directory, as a sibling to `runanywhere-swift/`.
> Worktrees are for parallel branch development, not new permanent packages.

```
sdks/sdk/runanywhere-commons/   # Sibling to runanywhere-swift/
```

### Structure

```
runanywhere-commons/
├── CMakeLists.txt                    # Root CMake configuration
├── README.md                         # Package documentation
├── VERSION                           # Version file (e.g., "1.0.0")
│
├── include/                          # Public C API headers (rac_* prefix!)
│   ├── rac_core.h                    # Core initialization
│   ├── rac_types.h                   # Common type definitions
│   ├── rac_error.h                   # Error codes (-100 to -999 range)
│   ├── rac_platform_adapter.h        # Platform adapter interface
│   ├── rac_events.h                  # Event system
│   ├── rac_llm.h                     # LLM capability API
│   ├── rac_stt.h                     # STT capability API
│   ├── rac_tts.h                     # TTS capability API
│   └── rac_vad.h                     # VAD capability API
│
├── src/                              # Commons implementation
│   ├── core/
│   │   ├── rac_core.cpp              # Core initialization
│   │   ├── rac_error.cpp             # Error handling
│   │   └── rac_time.cpp              # Time utilities (get_current_time_ms)
│   ├── registry/
│   │   ├── module_registry.cpp       # Module registration
│   │   └── service_registry.cpp      # Service factory registry
│   ├── events/
│   │   └── event_publisher.cpp       # Event routing
│   └── lifecycle/
│       └── model_lifecycle.cpp       # Model lifecycle management
│
├── backends/                         # Modular backend wrappers
│   ├── llamacpp/
│   │   ├── CMakeLists.txt
│   │   ├── include/
│   │   │   └── rac_llm_llamacpp.h
│   │   └── src/
│   │       └── rac_llm_llamacpp.cpp
│   │
│   ├── onnx/
│   │   ├── CMakeLists.txt
│   │   ├── include/
│   │   │   ├── rac_stt_onnx.h
│   │   │   ├── rac_tts_onnx.h
│   │   │   └── rac_vad_onnx.h
│   │   └── src/
│   │       ├── rac_stt_onnx.cpp
│   │       ├── rac_tts_onnx.cpp
│   │       └── rac_vad_onnx.cpp
│   │
│   ├── whispercpp/
│   │   ├── CMakeLists.txt
│   │   ├── include/
│   │   │   └── rac_stt_whispercpp.h
│   │   └── src/
│   │       └── rac_stt_whispercpp.cpp
│   │
│   └── mlx/                          # Future: Apple MLX
│       └── ...
│
├── scripts/
│   ├── build-ios.sh                  # iOS XCFramework builder
│   ├── build-android.sh              # Android .so builder
│   ├── build-all.sh                  # Build all platforms
│   └── package-release.sh            # Package for release
│
├── cmake/
│   ├── ios.toolchain.cmake           # iOS cross-compilation
│   └── FindRunAnywhereCore.cmake     # Find runanywhere-core
│
└── dist/                             # Build output (gitignored)
    ├── ios/
    │   ├── RACommons.xcframework/
    │   ├── RABackendLlamaCPP.xcframework/
    │   ├── RABackendONNX.xcframework/
    │   └── RABackendWhisperCPP.xcframework/
    └── android/
        ├── arm64-v8a/
        ├── armeabi-v7a/
        └── x86_64/
```

### Commands

```bash
# Create directory structure
cd sdks/sdk
mkdir -p runanywhere-commons/{include,src/{core,registry,events,lifecycle}}
mkdir -p runanywhere-commons/backends/{llamacpp,onnx,whispercpp,mlx}/{include,src}
mkdir -p runanywhere-commons/{scripts,cmake,dist/{ios,android}}
touch runanywhere-commons/{CMakeLists.txt,README.md,VERSION}
echo "1.0.0" > runanywhere-commons/VERSION
```

---

## Task 0.2: Set Up CMake Build System

### Root CMakeLists.txt

```cmake
# runanywhere-commons/CMakeLists.txt
cmake_minimum_required(VERSION 3.22)

# Read version from VERSION file
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" RAC_VERSION)
string(STRIP "${RAC_VERSION}" RAC_VERSION)

project(RunAnywhereCommons
    VERSION ${RAC_VERSION}
    LANGUAGES CXX C
    DESCRIPTION "RunAnywhere Commons: Shared layer for platform SDKs"
)

# =============================================================================
# OPTIONS - Each backend is independently toggleable
# =============================================================================
option(RAC_BUILD_LLAMACPP "Build LlamaCpp backend module" ON)
option(RAC_BUILD_ONNX "Build ONNX Runtime backend module" ON)
option(RAC_BUILD_WHISPERCPP "Build WhisperCpp backend module" ON)
option(RAC_BUILD_MLX "Build MLX backend module (Apple only)" OFF)
option(RAC_BUILD_SHARED "Build as shared library" OFF)
option(RAC_BUILD_TESTS "Build unit tests" OFF)

# =============================================================================
# C++ CONFIGURATION
# =============================================================================
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Add cmake modules path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# =============================================================================
# PLATFORM DETECTION
# =============================================================================
if(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RAC_PLATFORM_IOS TRUE)
    set(RAC_PLATFORM_NAME "iOS")
elseif(ANDROID)
    set(RAC_PLATFORM_ANDROID TRUE)
    set(RAC_PLATFORM_NAME "Android")
elseif(APPLE)
    set(RAC_PLATFORM_MACOS TRUE)
    set(RAC_PLATFORM_NAME "macOS")
elseif(UNIX)
    set(RAC_PLATFORM_LINUX TRUE)
    set(RAC_PLATFORM_NAME "Linux")
else()
    set(RAC_PLATFORM_NAME "Unknown")
endif()

message(STATUS "RunAnywhere Commons - Platform: ${RAC_PLATFORM_NAME}")

# =============================================================================
# FIND RUNANYWHERE-CORE (PRIVATE DEPENDENCY)
# =============================================================================
# Path to runanywhere-core (relative to sdks/sdk/runanywhere-commons/ in the monorepo)
# Layout: runanywhere-all/sdks/sdk/runanywhere-commons/ -> runanywhere-all/runanywhere-core/
set(RUNANYWHERE_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../runanywhere-core"
    CACHE PATH "Path to runanywhere-core")

if(NOT EXISTS "${RUNANYWHERE_CORE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "runanywhere-core not found at: ${RUNANYWHERE_CORE_DIR}")
endif()

message(STATUS "Found runanywhere-core at: ${RUNANYWHERE_CORE_DIR}")

# =============================================================================
# CRITICAL: Build runanywhere-core in MODULAR mode
# =============================================================================
# We build runanywhere-core with RA_BUILD_MODULAR=ON so that:
# - librunanywhere_bridge.a contains ONLY core functionality (~500KB)
# - librunanywhere_llamacpp.a contains ONLY LlamaCpp backend (~15MB)
# - librunanywhere_onnx.a contains ONLY ONNX backend (~50MB)
# - etc.
#
# This allows us to create separate XCFrameworks for each backend.
# =============================================================================

# Configure runanywhere-core for modular build
set(RA_BUILD_MODULAR ON CACHE BOOL "" FORCE)
set(RA_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(RA_BUILD_TESTS OFF CACHE BOOL "" FORCE)

# Enable only the backends we need
set(RA_BUILD_ONNX ${RAC_BUILD_ONNX} CACHE BOOL "" FORCE)
set(RA_BUILD_LLAMACPP ${RAC_BUILD_LLAMACPP} CACHE BOOL "" FORCE)
set(RA_BUILD_WHISPERCPP ${RAC_BUILD_WHISPERCPP} CACHE BOOL "" FORCE)
set(RA_BUILD_COREML OFF CACHE BOOL "" FORCE)
set(RA_BUILD_TFLITE OFF CACHE BOOL "" FORCE)

add_subdirectory(${RUNANYWHERE_CORE_DIR} ${CMAKE_BINARY_DIR}/runanywhere-core)

# =============================================================================
# COMMONS CORE LIBRARY (always built)
# =============================================================================
set(COMMONS_SOURCES
    src/core/rac_core.cpp
    src/core/rac_error.cpp
    src/core/rac_time.cpp
    src/registry/module_registry.cpp
    src/registry/service_registry.cpp
    src/events/event_publisher.cpp
    src/lifecycle/model_lifecycle.cpp
)

if(RAC_BUILD_SHARED)
    add_library(rac_commons SHARED ${COMMONS_SOURCES})
else()
    add_library(rac_commons STATIC ${COMMONS_SOURCES})
endif()

target_include_directories(rac_commons PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Link to runanywhere-core bridge (only the core, not backends)
target_link_libraries(rac_commons PRIVATE
    runanywhere_bridge
)

target_compile_features(rac_commons PUBLIC cxx_std_17)

# Symbol visibility for shared library
if(RAC_BUILD_SHARED)
    target_compile_definitions(rac_commons PRIVATE RAC_EXPORTS)
    set_target_properties(rac_commons PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
    )
endif()

# =============================================================================
# MODULAR BACKENDS (each produces separate library)
# =============================================================================
if(RAC_BUILD_LLAMACPP)
    message(STATUS "Building LlamaCpp backend module")
    add_subdirectory(backends/llamacpp)
endif()

if(RAC_BUILD_ONNX)
    message(STATUS "Building ONNX backend module")
    add_subdirectory(backends/onnx)
endif()

if(RAC_BUILD_WHISPERCPP)
    message(STATUS "Building WhisperCpp backend module")
    add_subdirectory(backends/whispercpp)
endif()

if(RAC_BUILD_MLX AND APPLE)
    message(STATUS "Building MLX backend module")
    add_subdirectory(backends/mlx)
elseif(RAC_BUILD_MLX)
    message(WARNING "MLX backend is only available on Apple platforms")
endif()

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================
message(STATUS "")
message(STATUS "========================================")
message(STATUS "RunAnywhere Commons v${PROJECT_VERSION}")
message(STATUS "========================================")
message(STATUS "Platform:        ${RAC_PLATFORM_NAME}")
message(STATUS "Build type:      ${CMAKE_BUILD_TYPE}")
message(STATUS "Shared library:  ${RAC_BUILD_SHARED}")
message(STATUS "")
message(STATUS "Backends:")
message(STATUS "  LlamaCpp:      ${RAC_BUILD_LLAMACPP}")
message(STATUS "  ONNX:          ${RAC_BUILD_ONNX}")
message(STATUS "  WhisperCpp:    ${RAC_BUILD_WHISPERCPP}")
message(STATUS "  MLX:           ${RAC_BUILD_MLX}")
message(STATUS "========================================")
message(STATUS "")
```

### Backend CMakeLists.txt (LlamaCpp Example)

```cmake
# backends/llamacpp/CMakeLists.txt

# LlamaCpp Backend Module
# Produces: librac_backend_llamacpp library

set(LLAMACPP_SOURCES
    src/rac_llm_llamacpp.cpp
)

if(RAC_BUILD_SHARED)
    add_library(rac_backend_llamacpp SHARED ${LLAMACPP_SOURCES})
else()
    add_library(rac_backend_llamacpp STATIC ${LLAMACPP_SOURCES})
endif()

target_include_directories(rac_backend_llamacpp PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Link to commons core and runanywhere-core llamacpp backend
target_link_libraries(rac_backend_llamacpp
    PUBLIC rac_commons
    PRIVATE runanywhere_llamacpp  # From runanywhere-core (modular build)
)

# Include runanywhere-core headers for backend access
target_include_directories(rac_backend_llamacpp PRIVATE
    ${RUNANYWHERE_CORE_DIR}/src
    ${RUNANYWHERE_CORE_DIR}/src/backends/llamacpp
    ${RUNANYWHERE_CORE_DIR}/src/capabilities
)

target_compile_definitions(rac_backend_llamacpp PRIVATE
    RAC_BACKEND_LLAMACPP_EXPORTS
)
```

---

## Task 0.3: Define Public C API Headers

> **⚠️ CRITICAL**: All headers use `rac_` prefix to avoid collision with `runanywhere-core` headers.

### rac_types.h

```c
// include/rac_types.h
#ifndef RAC_TYPES_H
#define RAC_TYPES_H

/**
 * RunAnywhere Commons - Type Definitions
 *
 * NOTE: These use RAC_ prefix to avoid collision with runanywhere-core types.
 * The capability values are ALIGNED with runanywhere-core for easy mapping.
 */

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// =============================================================================
// EXPORT MACROS
// =============================================================================

#if defined(_WIN32) || defined(__CYGWIN__)
    #ifdef RAC_EXPORTS
        #define RAC_API __declspec(dllexport)
    #else
        #define RAC_API __declspec(dllimport)
    #endif
#else
    #if __GNUC__ >= 4
        #define RAC_API __attribute__((visibility("default")))
    #else
        #define RAC_API
    #endif
#endif

// =============================================================================
// RESULT TYPE
// =============================================================================

typedef int32_t rac_result_t;

// =============================================================================
// CAPABILITY TYPES (ALIGNED with runanywhere-core RA_CAP_* values)
// =============================================================================

typedef enum {
    RAC_CAPABILITY_TEXT_GENERATION = 0,  // Matches RA_CAP_TEXT_GENERATION
    RAC_CAPABILITY_EMBEDDINGS = 1,       // Matches RA_CAP_EMBEDDINGS
    RAC_CAPABILITY_STT = 2,              // Matches RA_CAP_STT
    RAC_CAPABILITY_TTS = 3,              // Matches RA_CAP_TTS
    RAC_CAPABILITY_VAD = 4,              // Matches RA_CAP_VAD
    RAC_CAPABILITY_DIARIZATION = 5       // Matches RA_CAP_DIARIZATION
} rac_capability_type_t;

// =============================================================================
// HANDLE TYPES
// =============================================================================

typedef void* rac_handle_t;
typedef void* rac_llm_handle_t;
typedef void* rac_stt_handle_t;
typedef void* rac_tts_handle_t;
typedef void* rac_vad_handle_t;
typedef void* rac_stream_handle_t;

// =============================================================================
// COMMON STRUCTURES
// =============================================================================

/**
 * Audio buffer for STT/TTS/VAD operations
 */
typedef struct {
    const float* samples;     // PCM float32 samples [-1.0, 1.0]
    size_t count;             // Number of samples
    uint32_t sample_rate;     // Sample rate (typically 16000)
    uint8_t channels;         // Number of channels (typically 1)
} rac_audio_buffer_t;

/**
 * Memory info for resource management
 */
typedef struct {
    size_t total_bytes;       // Total available memory
    size_t available_bytes;   // Currently available memory
    size_t used_bytes;        // Memory used by SDK
} rac_memory_info_t;

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * Free memory allocated by commons APIs.
 * Use this for void* pointers returned by rac_* functions.
 */
RAC_API void rac_free(void* ptr);

/**
 * Duplicate a string (caller must free with rac_free).
 */
RAC_API char* rac_strdup(const char* str);

// =============================================================================
// TIME UTILITIES
// =============================================================================

/**
 * Get current time in milliseconds since epoch.
 * Used for event timestamps.
 */
RAC_API uint64_t rac_get_current_time_ms(void);

#endif // RAC_TYPES_H
```

### rac_error.h

```c
// include/rac_error.h
#ifndef RAC_ERROR_H
#define RAC_ERROR_H

/**
 * RunAnywhere Commons - Error Codes
 *
 * ERROR CODE RANGE: -100 to -999
 *
 * This avoids collision with runanywhere-core bridge errors (-1 to -99).
 * The Swift/Kotlin/Flutter wrappers map between these ranges at the boundary.
 */

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// ERROR CODES (-100 to -999 range)
// =============================================================================

// Success
#define RAC_SUCCESS                      0

// Initialization errors (-1xx)
#define RAC_ERROR_NOT_INITIALIZED       -100
#define RAC_ERROR_ALREADY_INITIALIZED   -101
#define RAC_ERROR_INVALID_CONFIG        -102
#define RAC_ERROR_PLATFORM_ADAPTER      -103

// Parameter errors (-2xx)
#define RAC_ERROR_INVALID_PARAM         -200
#define RAC_ERROR_NULL_POINTER          -201
#define RAC_ERROR_INVALID_HANDLE        -202
#define RAC_ERROR_BUFFER_TOO_SMALL      -203

// Model errors (-3xx)
#define RAC_ERROR_MODEL_NOT_FOUND       -300
#define RAC_ERROR_MODEL_NOT_LOADED      -301
#define RAC_ERROR_MODEL_LOAD_FAILED     -302
#define RAC_ERROR_MODEL_ALREADY_LOADED  -303
#define RAC_ERROR_MODEL_INCOMPATIBLE    -304

// Component errors (-4xx)
#define RAC_ERROR_COMPONENT_NOT_READY   -400
#define RAC_ERROR_COMPONENT_BUSY        -401
#define RAC_ERROR_COMPONENT_FAILED      -402
#define RAC_ERROR_NOT_SUPPORTED         -403  // e.g., HTTP in platform adapter

// Network errors (-5xx) - Reserved but NOT USED (SDK handles networking)
#define RAC_ERROR_NETWORK_UNAVAILABLE   -500
#define RAC_ERROR_NETWORK_TIMEOUT       -501
#define RAC_ERROR_NETWORK_FAILED        -502

// Memory errors (-6xx)
#define RAC_ERROR_OUT_OF_MEMORY         -600
#define RAC_ERROR_MEMORY_PRESSURE       -601

// File errors (-7xx)
#define RAC_ERROR_FILE_NOT_FOUND        -700
#define RAC_ERROR_FILE_READ_FAILED      -701
#define RAC_ERROR_FILE_WRITE_FAILED     -702
#define RAC_ERROR_CHECKSUM_MISMATCH     -703

// Backend errors (-8xx)
#define RAC_ERROR_BACKEND_NOT_FOUND     -800
#define RAC_ERROR_BACKEND_LOAD_FAILED   -801
#define RAC_ERROR_BACKEND_NOT_REGISTERED -802

// Cancellation (-9xx)
#define RAC_ERROR_CANCELLED             -900

// =============================================================================
// ERROR UTILITIES
// =============================================================================

/**
 * Get human-readable error message for an error code.
 * @param code Error code (RAC_SUCCESS or RAC_ERROR_*)
 * @return Static string describing the error (do not free)
 */
RAC_API const char* rac_error_message(rac_result_t code);

/**
 * Get detailed error information (thread-local).
 * @return Additional error details, or NULL if none
 */
RAC_API const char* rac_get_last_error_details(void);

/**
 * Set detailed error information (internal use).
 */
RAC_API void rac_set_last_error_details(const char* details);

#ifdef __cplusplus
}
#endif

#endif // RAC_ERROR_H
```

### rac_core.h

```c
// include/rac_core.h
#ifndef RAC_CORE_H
#define RAC_CORE_H

/**
 * RunAnywhere Commons - Core API
 *
 * This header provides initialization and module management APIs.
 * Platform SDKs call these in addition to the existing runanywhere_bridge.h APIs.
 */

#include "rac_types.h"
#include "rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// VERSION
// =============================================================================

#define RAC_API_VERSION_MAJOR 1
#define RAC_API_VERSION_MINOR 0
#define RAC_API_VERSION_PATCH 0

/**
 * Get the commons library version string (e.g., "1.0.0")
 */
RAC_API const char* rac_get_version(void);

/**
 * Get the API version as packed integer: (MAJOR << 16) | (MINOR << 8) | PATCH
 */
RAC_API uint32_t rac_get_api_version(void);

// =============================================================================
// COMMONS INITIALIZATION
// =============================================================================

/**
 * SDK environment (for telemetry routing)
 */
typedef enum {
    RAC_ENV_DEVELOPMENT = 0,
    RAC_ENV_STAGING = 1,
    RAC_ENV_PRODUCTION = 2
} rac_environment_t;

/**
 * Commons initialization configuration
 */
typedef struct {
    uint32_t struct_size;         // sizeof(rac_config_t) for versioning
    rac_environment_t environment; // SDK environment
    const char* device_id;        // Unique device identifier (optional)
    const char* app_id;           // Application bundle ID (optional)
    bool enable_telemetry;        // Enable event publishing
} rac_config_t;

/**
 * Initialize default configuration.
 * Always call this before modifying config fields.
 */
RAC_API void rac_config_init(rac_config_t* config);

/**
 * Initialize the commons layer.
 * Call this before using module registry or event APIs.
 *
 * @param config Commons configuration (can be NULL for defaults)
 * @return RAC_SUCCESS on success, error code otherwise
 */
RAC_API rac_result_t rac_init(const rac_config_t* config);

/**
 * Shutdown the commons layer.
 * Unregisters all modules and stops event publishing.
 */
RAC_API rac_result_t rac_shutdown(void);

/**
 * Check if commons layer is initialized.
 */
RAC_API bool rac_is_initialized(void);

// =============================================================================
// MODULE REGISTRATION
// =============================================================================

/**
 * Module information
 */
typedef struct {
    const char* module_id;        // Unique identifier (e.g., "llamacpp")
    const char* module_name;      // Display name (e.g., "LlamaCPP")
    const char* version;          // Module version
    uint32_t capabilities;        // Bitmask of rac_capability_type_t
    int32_t priority;             // Higher priority = preferred (default: 100)
} rac_module_info_t;

/**
 * Register a module with the commons.
 * Called by backend modules during initialization.
 *
 * @param module Module information
 * @return RAC_SUCCESS on success, RAC_ERROR_ALREADY_INITIALIZED if duplicate
 */
RAC_API rac_result_t rac_module_register(const rac_module_info_t* module);

/**
 * Unregister a module.
 *
 * @param module_id Module identifier
 * @return RAC_SUCCESS on success, RAC_ERROR_MODEL_NOT_FOUND if not registered
 */
RAC_API rac_result_t rac_module_unregister(const char* module_id);

/**
 * Check if a module is registered.
 *
 * @param module_id Module identifier
 * @return true if registered, false otherwise
 */
RAC_API bool rac_module_is_registered(const char* module_id);

/**
 * Get list of registered modules.
 *
 * @param modules Output: array of module info (caller must free with rac_module_list_free)
 * @param count Output: number of modules
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_module_list(
    rac_module_info_t** modules,
    size_t* count
);

/**
 * Free module list returned by rac_module_list.
 */
RAC_API void rac_module_list_free(rac_module_info_t* modules, size_t count);

/**
 * Get modules that support a specific capability.
 *
 * @param capability The capability to query
 * @param module_ids Output: array of module IDs (caller must free with rac_free)
 * @param count Output: number of modules
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_modules_for_capability(
    rac_capability_type_t capability,
    char*** module_ids,
    size_t* count
);

#ifdef __cplusplus
}
#endif

#endif // RAC_CORE_H
```

### rac_platform_adapter.h

```c
// include/rac_platform_adapter.h
#ifndef RAC_PLATFORM_ADAPTER_H
#define RAC_PLATFORM_ADAPTER_H

/**
 * RunAnywhere Commons - Platform Adapter Interface
 *
 * Platform SDKs implement these callbacks for platform-specific functionality.
 *
 * NOTE: HTTP operations return RAC_ERROR_NOT_SUPPORTED.
 * All networking is handled by the platform SDK (Swift, Kotlin, etc.).
 */

#include "rac_types.h"
#include "rac_error.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// LOG LEVELS
// =============================================================================

typedef enum {
    RAC_LOG_DEBUG = 0,
    RAC_LOG_INFO = 1,
    RAC_LOG_WARNING = 2,
    RAC_LOG_ERROR = 3,
    RAC_LOG_FAULT = 4
} rac_log_level_t;

// =============================================================================
// PLATFORM ADAPTER INTERFACE
// =============================================================================

typedef struct {
    // =================================================================
    // FILE SYSTEM
    // =================================================================

    rac_result_t (*file_exists)(const char* path, bool* exists, void* ctx);
    rac_result_t (*file_read)(const char* path, uint8_t** data, size_t* len, void* ctx);
    rac_result_t (*file_write)(const char* path, const uint8_t* data, size_t len, void* ctx);
    rac_result_t (*file_delete)(const char* path, void* ctx);
    rac_result_t (*file_size)(const char* path, size_t* size, void* ctx);
    rac_result_t (*dir_create)(const char* path, void* ctx);
    rac_result_t (*dir_list)(const char* path, char*** files, size_t* count, void* ctx);
    rac_result_t (*dir_delete)(const char* path, bool recursive, void* ctx);
    void (*dir_list_free)(char** files, size_t count, void* ctx);

    // =================================================================
    // HTTP - NOT IMPLEMENTED (return RAC_ERROR_NOT_SUPPORTED)
    // =================================================================
    // All networking handled by platform SDK.
    // These exist for potential future use on platforms without Swift networking.

    rac_result_t (*http_request)(void* req, void* resp, void* ctx);  // Returns RAC_ERROR_NOT_SUPPORTED
    rac_result_t (*http_download)(const char* url, const char* dest, void* progress, void* pctx, void* ctx);  // Returns RAC_ERROR_NOT_SUPPORTED

    // =================================================================
    // SECURE STORAGE
    // =================================================================

    rac_result_t (*secure_get)(const char* key, char* value, size_t* len, void* ctx);
    rac_result_t (*secure_set)(const char* key, const char* value, void* ctx);
    rac_result_t (*secure_delete)(const char* key, void* ctx);

    // =================================================================
    // LOGGING
    // =================================================================

    void (*log)(rac_log_level_t level, const char* tag, const char* message, void* ctx);

    // =================================================================
    // CLOCK
    // =================================================================

    uint64_t (*now_ms)(void* ctx);

    // =================================================================
    // MEMORY INFO
    // =================================================================

    rac_result_t (*memory_info)(rac_memory_info_t* info, void* ctx);

    // =================================================================
    // CONTEXT
    // =================================================================

    void* context;  // Passed to all callbacks

} rac_platform_adapter_t;

/**
 * Set the platform adapter.
 * Must be called before rac_init() if using platform-specific features.
 *
 * @param adapter Platform adapter (copied, caller retains ownership)
 * @return RAC_SUCCESS on success
 */
RAC_API rac_result_t rac_set_platform_adapter(const rac_platform_adapter_t* adapter);

/**
 * Get the current platform adapter.
 * @return Pointer to current adapter, or NULL if not set
 */
RAC_API const rac_platform_adapter_t* rac_get_platform_adapter(void);

#ifdef __cplusplus
}
#endif

#endif // RAC_PLATFORM_ADAPTER_H
```

---

## Task 0.4: iOS XCFramework Build Script

### scripts/build-ios.sh

```bash
#!/bin/bash
set -e

# =============================================================================
# iOS XCFramework Build Script
# Builds SEPARATE XCFrameworks for:
#   - RACommons.xcframework (core commons)
#   - RABackendLlamaCPP.xcframework (LlamaCpp backend)
#   - RABackendONNX.xcframework (ONNX backend)
#   - RABackendWhisperCPP.xcframework (WhisperCpp backend)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/ios"
DIST_DIR="$PROJECT_DIR/dist/ios"

# Configuration
BUILD_TYPE="${BUILD_TYPE:-Release}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-17.0}"

# Which backends to build (can be overridden)
BUILD_LLAMACPP="${BUILD_LLAMACPP:-ON}"
BUILD_ONNX="${BUILD_ONNX:-ON}"
BUILD_WHISPERCPP="${BUILD_WHISPERCPP:-ON}"

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{device,simulator}
mkdir -p "$DIST_DIR"

echo "=========================================="
echo "Building RunAnywhere Commons for iOS"
echo "Build Type: $BUILD_TYPE"
echo "iOS Deployment Target: $IOS_DEPLOYMENT_TARGET"
echo ""
echo "Backends:"
echo "  LlamaCPP:    $BUILD_LLAMACPP"
echo "  ONNX:        $BUILD_ONNX"
echo "  WhisperCPP:  $BUILD_WHISPERCPP"
echo "=========================================="

# -----------------------------------------------------------------------------
# Common CMake options
# -----------------------------------------------------------------------------
CMAKE_COMMON_OPTS=(
    -G Ninja
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DRAC_BUILD_SHARED=OFF
    -DRAC_BUILD_LLAMACPP=$BUILD_LLAMACPP
    -DRAC_BUILD_ONNX=$BUILD_ONNX
    -DRAC_BUILD_WHISPERCPP=$BUILD_WHISPERCPP
    -DRAC_BUILD_MLX=OFF
)

# -----------------------------------------------------------------------------
# Build for iOS Device (arm64)
# -----------------------------------------------------------------------------
echo ""
echo ">>> Building for iOS Device (arm64)..."

cmake -S "$PROJECT_DIR" -B "$BUILD_DIR/device" \
    "${CMAKE_COMMON_OPTS[@]}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
    -DCMAKE_OSX_SYSROOT=iphoneos

cmake --build "$BUILD_DIR/device" --config "$BUILD_TYPE" -- -j$(sysctl -n hw.ncpu)

# -----------------------------------------------------------------------------
# Build for iOS Simulator (arm64 + x86_64)
# -----------------------------------------------------------------------------
echo ""
echo ">>> Building for iOS Simulator (arm64 + x86_64)..."

cmake -S "$PROJECT_DIR" -B "$BUILD_DIR/simulator" \
    "${CMAKE_COMMON_OPTS[@]}" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
    -DCMAKE_OSX_SYSROOT=iphonesimulator

cmake --build "$BUILD_DIR/simulator" --config "$BUILD_TYPE" -- -j$(sysctl -n hw.ncpu)

# -----------------------------------------------------------------------------
# Create XCFrameworks
# -----------------------------------------------------------------------------
echo ""
echo ">>> Creating XCFrameworks..."

mkdir -p "$BUILD_DIR/frameworks"

# Function to create XCFramework from static library
create_xcframework() {
    local LIB_NAME=$1
    local FRAMEWORK_NAME=$2
    local HEADERS_DIR=$3

    echo "Creating $FRAMEWORK_NAME.xcframework..."

    # Check if library exists
    if [ ! -f "$BUILD_DIR/device/lib${LIB_NAME}.a" ]; then
        echo "  Skipping (library not built)"
        return
    fi

    # Create framework structure for device
    local DEVICE_FRAMEWORK="$BUILD_DIR/frameworks/$FRAMEWORK_NAME-device.framework"
    mkdir -p "$DEVICE_FRAMEWORK/Headers"
    cp "$BUILD_DIR/device/lib${LIB_NAME}.a" "$DEVICE_FRAMEWORK/$FRAMEWORK_NAME"
    cp -r "$HEADERS_DIR"/* "$DEVICE_FRAMEWORK/Headers/" 2>/dev/null || true

    # Create Info.plist
    cat > "$DEVICE_FRAMEWORK/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>ai.runanywhere.$FRAMEWORK_NAME</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleVersion</key>
    <string>$(cat "$PROJECT_DIR/VERSION")</string>
    <key>MinimumOSVersion</key>
    <string>$IOS_DEPLOYMENT_TARGET</string>
</dict>
</plist>
EOF

    # Create framework structure for simulator
    local SIM_FRAMEWORK="$BUILD_DIR/frameworks/$FRAMEWORK_NAME-simulator.framework"
    mkdir -p "$SIM_FRAMEWORK/Headers"
    cp "$BUILD_DIR/simulator/lib${LIB_NAME}.a" "$SIM_FRAMEWORK/$FRAMEWORK_NAME"
    cp -r "$HEADERS_DIR"/* "$SIM_FRAMEWORK/Headers/" 2>/dev/null || true
    cp "$DEVICE_FRAMEWORK/Info.plist" "$SIM_FRAMEWORK/Info.plist"

    # Create module map
    for FW in "$DEVICE_FRAMEWORK" "$SIM_FRAMEWORK"; do
        mkdir -p "$FW/Modules"
        cat > "$FW/Modules/module.modulemap" << EOF
module $FRAMEWORK_NAME {
    umbrella header "$FRAMEWORK_NAME.h"
    export *
    module * { export * }
    link "c++"
}
EOF
        # Create umbrella header
        cat > "$FW/Headers/$FRAMEWORK_NAME.h" << EOF
// Umbrella header for $FRAMEWORK_NAME
#ifndef ${FRAMEWORK_NAME}_H
#define ${FRAMEWORK_NAME}_H
EOF
        for header in "$FW/Headers"/rac_*.h; do
            if [ -f "$header" ]; then
                echo "#include \"$(basename "$header")\"" >> "$FW/Headers/$FRAMEWORK_NAME.h"
            fi
        done
        echo "#endif // ${FRAMEWORK_NAME}_H" >> "$FW/Headers/$FRAMEWORK_NAME.h"
    done

    # Create XCFramework
    xcodebuild -create-xcframework \
        -framework "$DEVICE_FRAMEWORK" \
        -framework "$SIM_FRAMEWORK" \
        -output "$DIST_DIR/$FRAMEWORK_NAME.xcframework"

    echo "  Created: $DIST_DIR/$FRAMEWORK_NAME.xcframework"
}

# Create each XCFramework
create_xcframework "rac_commons" "RACommons" "$PROJECT_DIR/include"

if [ "$BUILD_LLAMACPP" = "ON" ]; then
    create_xcframework "rac_backend_llamacpp" "RABackendLlamaCPP" "$PROJECT_DIR/backends/llamacpp/include"
fi

if [ "$BUILD_ONNX" = "ON" ]; then
    create_xcframework "rac_backend_onnx" "RABackendONNX" "$PROJECT_DIR/backends/onnx/include"
fi

if [ "$BUILD_WHISPERCPP" = "ON" ]; then
    create_xcframework "rac_backend_whispercpp" "RABackendWhisperCPP" "$PROJECT_DIR/backends/whispercpp/include"
fi

# -----------------------------------------------------------------------------
# Create ZIP archives with checksums
# -----------------------------------------------------------------------------
echo ""
echo ">>> Creating ZIP archives..."

cd "$DIST_DIR"
for xcframework in *.xcframework; do
    if [ -d "$xcframework" ]; then
        zip -r -q "${xcframework}.zip" "$xcframework"
        shasum -a 256 "${xcframework}.zip" > "${xcframework}.zip.sha256"
        echo "  Created: ${xcframework}.zip"
    fi
done

echo ""
echo "=========================================="
echo "Build Complete!"
echo "Output: $DIST_DIR"
echo "=========================================="
ls -la "$DIST_DIR"
```

---

## Task 0.5: Android Build Script

### scripts/build-android.sh

```bash
#!/bin/bash
set -e

# =============================================================================
# Android Native Library Build Script
# Builds .so files for each backend
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/android"
DIST_DIR="$PROJECT_DIR/dist/android"

# Configuration
BUILD_TYPE="${BUILD_TYPE:-Release}"
ANDROID_API_LEVEL="${ANDROID_API_LEVEL:-24}"
NDK_PATH="${ANDROID_NDK_HOME:-$NDK_HOME}"

if [ -z "$NDK_PATH" ]; then
    echo "Error: ANDROID_NDK_HOME or NDK_HOME must be set"
    exit 1
fi

# ABIs to build
ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")

# Which backends to build
BUILD_LLAMACPP="${BUILD_LLAMACPP:-ON}"
BUILD_ONNX="${BUILD_ONNX:-ON}"
BUILD_WHISPERCPP="${BUILD_WHISPERCPP:-ON}"

# Clean and prepare
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

echo "=========================================="
echo "Building RunAnywhere Commons for Android"
echo "Build Type: $BUILD_TYPE"
echo "API Level: $ANDROID_API_LEVEL"
echo "NDK: $NDK_PATH"
echo "=========================================="

for ABI in "${ABIS[@]}"; do
    echo ""
    echo ">>> Building for $ABI..."

    ABI_BUILD_DIR="$BUILD_DIR/$ABI"
    ABI_DIST_DIR="$DIST_DIR/$ABI"
    mkdir -p "$ABI_BUILD_DIR" "$ABI_DIST_DIR"

    cmake -S "$PROJECT_DIR" -B "$ABI_BUILD_DIR" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$ABI" \
        -DANDROID_PLATFORM="android-$ANDROID_API_LEVEL" \
        -DANDROID_STL=c++_shared \
        -DRAC_BUILD_SHARED=ON \
        -DRAC_BUILD_LLAMACPP=$BUILD_LLAMACPP \
        -DRAC_BUILD_ONNX=$BUILD_ONNX \
        -DRAC_BUILD_WHISPERCPP=$BUILD_WHISPERCPP

    cmake --build "$ABI_BUILD_DIR" --config "$BUILD_TYPE"

    # Copy .so files
    cp "$ABI_BUILD_DIR"/*.so "$ABI_DIST_DIR/" 2>/dev/null || true

    # Strip debug symbols for release
    if [ "$BUILD_TYPE" = "Release" ]; then
        STRIP=$(find "$NDK_PATH/toolchains/llvm/prebuilt" -name "llvm-strip" | head -1)
        if [ -n "$STRIP" ]; then
            for so in "$ABI_DIST_DIR"/*.so; do
                $STRIP --strip-debug "$so"
            done
        fi
    fi

    echo "Built: $ABI_DIST_DIR"
    ls -la "$ABI_DIST_DIR"
done

echo ""
echo "=========================================="
echo "Build Complete!"
echo "Output: $DIST_DIR"
echo "=========================================="
```

---

## Task 0.6: GitHub Actions CI

### .github/workflows/build-commons.yml

```yaml
name: Build RunAnywhere Commons

on:
  push:
    branches: [main]
    paths:
      - 'sdks/sdk/runanywhere-commons/**'
  pull_request:
    branches: [main]
    paths:
      - 'sdks/sdk/runanywhere-commons/**'
  workflow_dispatch:

jobs:
  build-ios:
    name: Build iOS XCFrameworks
    runs-on: macos-14  # Apple Silicon
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install Ninja
        run: brew install ninja

      - name: Build iOS XCFrameworks
        working-directory: sdks/sdk/runanywhere-commons
        run: ./scripts/build-ios.sh

      - name: Upload iOS Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: ios-xcframeworks
          path: |
            sdks/sdk/runanywhere-commons/dist/ios/*.xcframework.zip
            sdks/sdk/runanywhere-commons/dist/ios/*.sha256

  build-android:
    name: Build Android Libraries
    runs-on: ubuntu-latest
    strategy:
      matrix:
        abi: [arm64-v8a, armeabi-v7a, x86_64]
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Set up NDK
        uses: nttld/setup-ndk@v1
        with:
          ndk-version: r25c

      - name: Install Ninja
        run: sudo apt-get install -y ninja-build

      - name: Build for ${{ matrix.abi }}
        working-directory: sdks/sdk/runanywhere-commons
        env:
          ABIS: ${{ matrix.abi }}
        run: |
          # Build single ABI
          export BUILD_DIR="build/android/${{ matrix.abi }}"
          ./scripts/build-android.sh

      - name: Upload Android Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: android-${{ matrix.abi }}
          path: sdks/sdk/runanywhere-commons/dist/android/${{ matrix.abi }}/*.so
```

---

## Definition of Done

- [ ] Prerequisites complete in `runanywhere-core`:
  - [ ] `RA_BUILD_MODULAR` option added
  - [ ] C-linkage wrappers added to backend headers
  - [ ] Separate `.a` files verified
- [ ] `runanywhere-commons` directory structure created
- [ ] CMakeLists.txt compiles successfully with modular core
- [ ] All public C headers defined (`rac_*.h` prefix)
- [ ] iOS build script produces separate XCFrameworks
- [ ] Android build script produces .so files for all ABIs
- [ ] CI workflow passes on push
- [ ] VERSION file created with "1.0.0"

---

## Rollback Strategy

- Phase 0 is additive only
- No changes to existing `runanywhere-swift` until Phase 3
- Changes to `runanywhere-core` are backward-compatible (new option only)
- Can be deleted without impact if needed

---

*Phase 0 Duration: 2 weeks*
