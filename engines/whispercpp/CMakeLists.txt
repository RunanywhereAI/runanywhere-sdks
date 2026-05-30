# =============================================================================
# WhisperCPP Backend - Speech-to-Text via whisper.cpp
# =============================================================================

# Per-engine build toggle owned locally.
# Opt-in fallback for Whisper-family models; use sherpa for all other STT.
option(RAC_BACKEND_WHISPERCPP "Build WhisperCPP backend" OFF)
if(NOT RAC_BACKEND_WHISPERCPP)
    return()
endif()

message(STATUS "Configuring WhisperCPP backend...")

# =============================================================================
# Dependencies
# =============================================================================

include(FetchContent)
include(LoadVersions)

# Fetch nlohmann_json for JSON parsing (if not already available).
# Version comes from sdk/runanywhere-commons/VERSIONS via LoadVersions above.
if(NOT TARGET nlohmann_json::nlohmann_json)
    FetchContent_Declare(
        nlohmann_json
        GIT_REPOSITORY https://github.com/nlohmann/json.git
        GIT_TAG        v${NLOHMANN_JSON_VERSION}
        GIT_SHALLOW    TRUE
    )
    set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(nlohmann_json)
endif()

# =============================================================================
# Fetch whisper.cpp — pin from VERSIONS::WHISPERCPP_VERSION (no local fallback).
# =============================================================================

set(WHISPER_CPP_VERSION "${WHISPERCPP_VERSION}")

FetchContent_Declare(
    whispercpp
    GIT_REPOSITORY https://github.com/ggml-org/whisper.cpp.git
    GIT_TAG        ${WHISPER_CPP_VERSION}
    GIT_SHALLOW    TRUE
    GIT_PROGRESS   TRUE
)

# Configure whisper.cpp build options
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_CURL OFF CACHE BOOL "" FORCE)
set(WHISPER_SDL2 OFF CACHE BOOL "" FORCE)
set(WHISPER_FFMPEG OFF CACHE BOOL "" FORCE)
set(WHISPER_COREML OFF CACHE BOOL "" FORCE)
set(WHISPER_OPENVINO OFF CACHE BOOL "" FORCE)

if(RAC_BACKEND_LLAMACPP)
    message(STATUS "LlamaCPP is also enabled - whisper.cpp will use its own GGML")
endif()

# Platform-specific optimizations
if(RAC_PLATFORM_IOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
elseif(RAC_PLATFORM_ANDROID)
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
elseif(RAC_PLATFORM_MACOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
elseif(RAC_PLATFORM_WINDOWS)
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_CUDA OFF CACHE BOOL "" FORCE)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    message(STATUS "Configuring whisper.cpp for Windows (CPU-only)")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries for whisper.cpp" FORCE)

FetchContent_MakeAvailable(whispercpp)

# Fix: Ensure whisper.cpp uses its own ggml headers, not LlamaCPP's
# This prevents GGML_KQ_MASK_PAD undefined errors when both backends are built
if(TARGET whisper)
    target_include_directories(whisper BEFORE PRIVATE
        ${whispercpp_SOURCE_DIR}/ggml/include
        ${whispercpp_SOURCE_DIR}/include
    )
endif()

# =============================================================================
# WhisperCPP Backend Library
# =============================================================================
# Target declaration migrated to rac_add_engine_plugin() macro.
# whisper.cpp FetchContent + GGML_* platform option setup above stays
# inline — engine-specific.

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

# pass3-syn-134: canonical include path lives under sdk/runanywhere-commons/include.
# The repo root has no top-level include/ directory; references to
# ${CMAKE_SOURCE_DIR}/include resolve to a nonexistent path when this engine is
# built from the monorepo root (CMAKE_SOURCE_DIR = repo root), so the bare
# `#include "rac_stt_whispercpp.h"` (header lives in include/rac/backends/) fails
# to resolve. Aligned with engines/whisperkit_coreml + engines/sherpa convention.
get_filename_component(RAC_COMMONS_ROOT_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

set(WHISPERCPP_BACKEND_SOURCES
    whispercpp_backend.cpp
    rac_stt_whispercpp.cpp
    rac_backend_whispercpp_register.cpp
    rac_plugin_entry_whispercpp.cpp
)

# Compose platform-specific link libs + compile defs.
set(WHISPERCPP_LINK_LIBS whisper nlohmann_json::nlohmann_json)
set(WHISPERCPP_COMPILE_DEFS RAC_WHISPERCPP_BUILDING)
set(WHISPERCPP_COMPILE_OPTS "")
set(WHISPERCPP_LINK_OPTS "")

if(RAC_PLATFORM_IOS)
    message(STATUS "Configuring WhisperCPP backend for iOS")
    list(APPEND WHISPERCPP_LINK_LIBS
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
    list(APPEND WHISPERCPP_COMPILE_DEFS GGML_USE_METAL=1)
elseif(RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring WhisperCPP backend for Android")
    list(APPEND WHISPERCPP_LINK_LIBS log)
    # Don't use -fvisibility=hidden here - JNI bridge needs these symbols
    list(APPEND WHISPERCPP_COMPILE_OPTS -O3 -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance.
    list(APPEND WHISPERCPP_LINK_OPTS
        -Wl,--gc-sections
        -Wl,-z,max-page-size=16384
        -Wl,-z,common-page-size=16384)
elseif(RAC_PLATFORM_MACOS)
    message(STATUS "Configuring WhisperCPP backend for macOS")
    list(APPEND WHISPERCPP_LINK_LIBS
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
elseif(RAC_PLATFORM_WINDOWS)
    message(STATUS "Configuring WhisperCPP backend for Windows")
endif()

# TARGET_NAME=rac_backend_whispercpp preserves the historical
# CMake target name; CXX_STANDARD=20 matches the original.
rac_add_engine_plugin(whispercpp
    TARGET_NAME         rac_backend_whispercpp
    CXX_STANDARD        20
    SOURCES             ${WHISPERCPP_BACKEND_SOURCES}
    LINK_LIBRARIES      ${WHISPERCPP_LINK_LIBS}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
                        ${CMAKE_CURRENT_SOURCE_DIR}/..  # engines/ — for engines/common/*.h
                        ${whispercpp_SOURCE_DIR}/include
                        ${whispercpp_SOURCE_DIR}/ggml/include
    COMPILE_DEFINITIONS ${WHISPERCPP_COMPILE_DEFS}
    COMPILE_OPTIONS     ${WHISPERCPP_COMPILE_OPTS}
    LINK_OPTIONS        ${WHISPERCPP_LINK_OPTS}
    RUNTIMES            CPU METAL
    FORMATS             GGML
)

# =============================================================================
# JNI TARGET (Android)
# =============================================================================

if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED)
    if(ANDROID)
        message(STATUS "Building WhisperCPP JNI bridge for Android")

        add_library(rac_backend_whispercpp_jni SHARED
            jni/rac_backend_whispercpp_jni.cpp
        )

        target_include_directories(rac_backend_whispercpp_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${RAC_COMMONS_ROOT_DIR}/include
        )

        target_link_libraries(rac_backend_whispercpp_jni PRIVATE
            rac_backend_whispercpp
            log
        )

        target_compile_options(rac_backend_whispercpp_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
        # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
        target_link_options(rac_backend_whispercpp_jni PRIVATE
            -Wl,--gc-sections
            -Wl,-z,max-page-size=16384
            -Wl,-z,common-page-size=16384)
    endif()
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "WhisperCPP Backend Configuration:")
message(STATUS "  whisper.cpp version: ${WHISPER_CPP_VERSION}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
