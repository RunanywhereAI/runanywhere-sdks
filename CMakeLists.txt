# RunAnywhere v2 — top-level CMake entry point.
#
# This file is the entry point for the v2 monorepo build. It does NOT replace
# the legacy `sdk/runanywhere-commons/CMakeLists.txt` during the migration — v1
# and v2 coexist until Phase 3 flips the default.
#
# Build the v2 core only:
#   cmake --preset macos-debug
#   cmake --build --preset macos-debug
#
# Build a specific frontend (e.g. Swift XCFramework):
#   cmake --preset ios-release
#   cmake --build --preset ios-release --target RunAnywhereCore
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

# Plugin discovery mode — mutually exclusive with the legacy commons tree.
option(RA_USE_LEGACY_COMMONS "Fall back to sdk/runanywhere-commons for engines" OFF)

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
    add_subdirectory(engines/sherpa)
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
