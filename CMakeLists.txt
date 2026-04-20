# RunAnywhere v2 — top-level CMake entry point.
#
# Build the core:
#   cmake --preset macos-debug
#   cmake --build --preset macos-debug
#
# Build the Swift XCFramework (Apple slices) for sdk/swift:
#   scripts/build-core-xcframework.sh --platforms=macos,ios-device,ios-sim
#
# See cmake/presets.json and docs/v2_build.md for the full matrix.

cmake_minimum_required(VERSION 3.22)

# Silence CMP0077 — option() honors normal vars. Required for vcpkg overlay.
if(POLICY CMP0077)
    cmake_policy(SET CMP0077 NEW)
endif()

project(RunAnywhereV2
    VERSION 2.0.0
    DESCRIPTION "RunAnywhere v2 — C++20 core + codegen'd frontends for on-device AI"
    LANGUAGES C CXX
)

# Enable Objective-C++ only on Apple platforms where we need CoreML/AVFoundation bridges.
if(APPLE)
    enable_language(OBJCXX)
endif()

# ---------------------------------------------------------------------------
# Global C++ settings
# ---------------------------------------------------------------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Default to Release if the user did not specify a build type.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
option(RA_BUILD_TESTS        "Build unit tests"                          ON)
option(RA_BUILD_TOOLS        "Build tools/benchmark and pipeline-validator" ON)
option(RA_BUILD_FRONTENDS    "Build frontends/*"                         OFF)
option(RA_BUILD_ENGINES      "Build engines/*"                           ON)
option(RA_BUILD_SOLUTIONS    "Build solutions/*"                         ON)
option(RA_ENABLE_SANITIZERS  "Enable ASan/UBSan (Debug only)"            ON)
option(RA_ENABLE_TSAN        "Enable TSan (separate from ASan/UBSan)"    OFF)
option(RA_ENABLE_LTO         "Enable Link-Time Optimization on Release"  OFF)

# ---------------------------------------------------------------------------
# Platform detection + compiler flags
# ---------------------------------------------------------------------------
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/platform.cmake)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/sanitizers.cmake)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/plugins.cmake)
include(${CMAKE_CURRENT_SOURCE_DIR}/cmake/protobuf.cmake)

# ---------------------------------------------------------------------------
# Subprojects
# ---------------------------------------------------------------------------
# idl/ is a pure code-generation step — ra_idl depends only on
# protobuf::libprotobuf and exposes the generated .pb.h to downstream
# consumers (the C ABI serialization bridge + any test that round-trips
# messages).
if(RA_HAVE_PROTOBUF)
    add_subdirectory(idl)
endif()

add_subdirectory(core)

if(RA_BUILD_ENGINES)
    add_subdirectory(engines/llamacpp)
    # sherpa-onnx also serves the wake_word primitive via its keyword
    # spotter, so we no longer build a separate stub wakeword engine.
    # Sherpa fetches a ~30 MB pre-built tarball from GitHub releases; it
    # can fail on flaky networks and is not mergeable into the Swift
    # xcframework (dynamic-only). Let callers opt out via RA_BUILD_SHERPA=OFF
    # so xcframework builds skip the fetch entirely.
    option(RA_BUILD_SHERPA "Build the sherpa-onnx engine plugin" ON)
    if(RA_BUILD_SHERPA)
        add_subdirectory(engines/sherpa)
    endif()
    # New Phase C engine plugins. Each ships as a metadata-only stub that
    # exports its RA_PLUGIN_ENTRY_DECL so frontend register() calls find
    # the plugin; real engine integrations land behind opt-in CMake gates
    # in the per-engine CMakeLists.txt.
    add_subdirectory(engines/onnx)
    add_subdirectory(engines/whisperkit)
    # whispercpp is opt-in — without a real whisper.cpp link it just
    # registers a placeholder that returns RA_ERR_CAPABILITY_UNSUPPORTED.
    # Skip it by default to keep the plugin list clean on default builds.
    option(RA_BUILD_WHISPERCPP "Include engines/whispercpp plugin" OFF)
    if(RA_BUILD_WHISPERCPP)
        add_subdirectory(engines/whispercpp)
    endif()
    add_subdirectory(engines/metalrt)
    add_subdirectory(engines/genie)
    add_subdirectory(engines/diffusion-coreml)
endif()

# Discover gtest BEFORE descending into subdirs whose CMakeLists may already
# reference GTest:: targets from their own add_subdirectory(tests).
if(RA_BUILD_TESTS AND NOT RA_PLATFORM STREQUAL "IOS" AND NOT RA_PLATFORM STREQUAL "WASM")
    enable_testing()
    find_package(GTest CONFIG QUIET)
    if(NOT GTest_FOUND)
        find_package(GTest QUIET)
    endif()
    if(NOT GTest_FOUND)
        message(STATUS "gtest not found via find_package — fetching via FetchContent")
        include(FetchContent)
        set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
        set(BUILD_GMOCK   OFF CACHE BOOL "" FORCE)
        FetchContent_Declare(googletest
            GIT_REPOSITORY https://github.com/google/googletest.git
            GIT_TAG        v1.14.0
            GIT_SHALLOW    TRUE
        )
        FetchContent_MakeAvailable(googletest)
    endif()
endif()

if(RA_BUILD_SOLUTIONS)
    add_subdirectory(solutions/voice-agent)
    add_subdirectory(solutions/rag)
    add_subdirectory(solutions/openai-server)
endif()

if(RA_BUILD_FRONTENDS)
    # Each frontend opts in via its own CMakeLists.txt — Swift uses XCFramework
    # packaging; Kotlin uses Gradle (not CMake); Dart/TS use npm/pub.
    if(RA_PLATFORM STREQUAL "IOS" OR RA_PLATFORM STREQUAL "MACOS")
        add_subdirectory(frontends/swift)
    endif()
    if(RA_PLATFORM STREQUAL "WASM")
        add_subdirectory(frontends/web/wasm)
    endif()
endif()

if(RA_BUILD_TOOLS)
    add_subdirectory(tools/benchmark)
    add_subdirectory(tools/pipeline-validator)
endif()

if(RA_BUILD_TESTS AND NOT RA_PLATFORM STREQUAL "IOS" AND NOT RA_PLATFORM STREQUAL "WASM")
    # gtest was discovered earlier in this file (before descending into
    # solutions/*). enable_testing() was also hoisted. All that remains is
    # to recurse into core/tests here.
    add_subdirectory(core/tests)
endif()

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
message(STATUS "")
message(STATUS "========================================================")
message(STATUS "  RunAnywhere v2 build configuration")
message(STATUS "========================================================")
message(STATUS "  Platform        : ${RA_PLATFORM}")
message(STATUS "  CXX             : ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "  Build type      : ${CMAKE_BUILD_TYPE}")
message(STATUS "  Sanitizers      : ASan=${RA_ENABLE_SANITIZERS} TSan=${RA_ENABLE_TSAN}")
message(STATUS "  Plugin mode     : ${RA_PLUGIN_MODE} (iOS=static, others=dlopen)")
message(STATUS "  Build engines   : ${RA_BUILD_ENGINES}")
message(STATUS "  Build solutions : ${RA_BUILD_SOLUTIONS}")
message(STATUS "  Build frontends : ${RA_BUILD_FRONTENDS}")
message(STATUS "  Build tests     : ${RA_BUILD_TESTS}")
message(STATUS "  Build tools     : ${RA_BUILD_TOOLS}")
message(STATUS "========================================================")
message(STATUS "")
