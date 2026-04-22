# =============================================================================
# RunAnywhere SDKs — Root CMake project
# =============================================================================
#
# GAP 07 Phase 1 — see v2_gap_specs/GAP_07_SINGLE_ROOT_CMAKE.md.
#
# This is the SINGLE entry point for native builds across the monorepo.
# Subdirectories:
#   - sdk/runanywhere-commons/ — the C++ runtime library (rac_commons)
#   - idl/                     — protobuf IDL + rac_idl static library
#   - engines/                 — engine plugins (after GAP 06; until then
#                                they live under sdk/runanywhere-commons/src/backends/)
#   - tools/plugin-loader-smoke/ — CLI smoke test for the GAP 03 loader
#
# Common builds:
#   cmake --preset macos-release && cmake --build --preset macos-release
#   cmake --preset linux-release-asan && cmake --build --preset linux-release-asan
#   cmake --preset android-arm64    && cmake --build --preset android-arm64
#   cmake --preset ios-device       && cmake --build --preset ios-device
#   cmake --preset wasm             && cmake --build --preset wasm
#
# Per-language SDKs (Swift / Kotlin / Flutter / RN / Web) consume the artifacts
# this build produces — they do NOT call this CMake directly. The wrapper
# scripts under scripts/build-core-{android,xcframework,wasm}.sh wire the
# preset output into the right SDK directory layout.
# =============================================================================

cmake_minimum_required(VERSION 3.22)

# Read version from the canonical VERSION file (kept under commons for
# historical reasons; treat as monorepo-wide).
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/VERSION" _RAC_VERSION_RAW)
string(STRIP "${_RAC_VERSION_RAW}" RAC_VERSION)

project(runanywhere
    VERSION ${RAC_VERSION}
    LANGUAGES CXX C
    DESCRIPTION "RunAnywhere SDKs — on-device AI runtime + per-language frontends"
    HOMEPAGE_URL "https://github.com/RunanywhereAI/runanywhere-sdks"
)

# =============================================================================
# Top-level options
#
# These are the *single source of truth* for build switches. Subdirectories
# (commons, engines/*, idl) inherit them via cache vars + the helper macros
# in cmake/plugins.cmake.
# =============================================================================

# Build mode
option(RAC_BUILD_SHARED       "Build rac_commons + plugins as shared libraries" OFF)
option(RAC_BUILD_TESTS        "Build CTest binaries" OFF)
option(RAC_BUILD_SERVER       "Build the OpenAI-compatible HTTP server (runanywhere-server)" OFF)
option(RAC_BUILD_PLATFORM     "Build the platform backend (Apple Foundation Models, System TTS) on Apple hosts" ON)
option(RAC_BUILD_JNI          "Build the JNI bridge for Android / JVM hosts" OFF)
option(RAC_BUILD_PLUGIN_SMOKE "Build tools/plugin-loader-smoke" OFF)

# Plugin loading mode (GAP 03)
# RAC_STATIC_PLUGINS:
#   ON  → engine TUs are linked into rac_commons; iOS/WASM force this.
#   OFF → engines build as standalone librunanywhere_<name>.so/.dylib/.dll
#         and the host loads them via rac_registry_load_plugin().
# Forcing for iOS/Emscripten happens inside sdk/runanywhere-commons/CMakeLists.txt
# so subdirectory consumers see the final value.
option(RAC_STATIC_PLUGINS "Link engine plugins statically into rac_commons (forced ON on iOS/WASM)" OFF)

# Sanitizers (GAP 07 Phase 3)
set(RAC_SANITIZER "" CACHE STRING "Enable a sanitizer: '', 'asan', 'tsan', 'ubsan'")
set_property(CACHE RAC_SANITIZER PROPERTY STRINGS "" asan tsan ubsan)

# =============================================================================
# Shared cmake/ helpers
# =============================================================================

list(APPEND CMAKE_MODULE_PATH
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake"
    "${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/cmake"  # LoadVersions, FetchONNXRuntime, ... — kept for engine subdirs after the GAP 06 reorg
)

# These four helpers ship in subsequent phases of GAP 07; the includes are
# tolerant so this CMakeLists works incrementally as the helpers land.
include(platform   OPTIONAL)   # rac_detect_platform()  — Phase 3
include(sanitizers OPTIONAL)   # rac_apply_sanitizer()  — Phase 3
include(plugins    OPTIONAL)   # rac_add_engine_plugin() / rac_force_load() — Phase 4
include(protobuf   OPTIONAL)   # rac_protobuf_generate() — Phase 5

# =============================================================================
# Compiler defaults
# =============================================================================

# C++20 is required because parts of the codebase use designated initializers
# (struct vtable registration) that MSVC doesn't accept under C++17.
set(CMAKE_CXX_STANDARD          20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS        OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# =============================================================================
# Subdirectories
# =============================================================================

# Commons — always built. Owns its own backend-toggle option block.
add_subdirectory(sdk/runanywhere-commons)

# IDL — built when Protobuf is available; commons skips the rac_idl target
# otherwise. The standalone subdirectory generates Swift/Kotlin/Dart/TS/Python
# bindings via the helper scripts in idl/codegen/, not via CMake.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/idl/CMakeLists.txt")
    add_subdirectory(idl)
endif()

# engines/ — top-level engine plugin directory. 5 migrated backends
# (llamacpp, onnx, whispercpp, whisperkit_coreml, metalrt) plus 3 stubs
# (sherpa, genie, diffusion-coreml) live here.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/engines/CMakeLists.txt")
    add_subdirectory(engines)
endif()

# Smoke test for the plugin loader (GAP 03). Only built when explicitly
# requested so headless CI nodes don't pay the build cost.
if(RAC_BUILD_PLUGIN_SMOKE
   AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/plugin-loader-smoke/CMakeLists.txt")
    add_subdirectory(tools/plugin-loader-smoke)
endif()

# Tests — wired through commons/tests for now. RAC_BUILD_TESTS is forwarded
# from this root option to the commons cache slot of the same name.
if(RAC_BUILD_TESTS)
    enable_testing()
    # GAP 09 / v2 close-out Phase 4 — cross-SDK parity test harness.
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/streaming/CMakeLists.txt")
        add_subdirectory(tests/streaming)
    endif()
endif()

# =============================================================================
# Configuration summary (matches the commons summary block for consistency)
# =============================================================================

message(STATUS "")
message(STATUS "============================================")
message(STATUS "RunAnywhere SDKs — root CMake configured")
message(STATUS "============================================")
message(STATUS "Version          : ${RAC_VERSION}")
message(STATUS "Build mode       : $<IF:$<BOOL:${RAC_BUILD_SHARED}>,SHARED,STATIC>")
message(STATUS "Plugin mode      : $<IF:$<BOOL:${RAC_STATIC_PLUGINS}>,STATIC (linked into commons),SHARED (dlopen-loaded)>")
message(STATUS "Sanitizer        : ${RAC_SANITIZER}")
message(STATUS "Tests            : ${RAC_BUILD_TESTS}")
message(STATUS "Server (HTTP)    : ${RAC_BUILD_SERVER}")
message(STATUS "Platform backend : ${RAC_BUILD_PLATFORM}")
message(STATUS "JNI bridge       : ${RAC_BUILD_JNI}")
message(STATUS "Plugin smoke CLI : ${RAC_BUILD_PLUGIN_SMOKE}")
message(STATUS "============================================")
message(STATUS "")
