# =============================================================================
# ONNX Backend - generic ONNX Runtime services
# =============================================================================

# T5.4: per-engine build toggle owned locally. Emscripten has no in-tree
# ONNX Runtime WASM binary (FetchONNXRuntime expects third_party/onnxruntime-wasm);
# WASM ONNX ships via onnxruntime-web from the frontend. Force off there.
# TODO(v0.21): wire a real ONNX Runtime WASM binary and flip back to default ON.
option(RAC_BACKEND_ONNX "Build ONNX backend" ON)
if(EMSCRIPTEN)
    set(RAC_BACKEND_ONNX OFF CACHE BOOL "" FORCE)
endif()
if(NOT RAC_BACKEND_ONNX)
    return()
endif()

message(STATUS "Configuring ONNX backend...")

# =============================================================================
# Dependencies
# =============================================================================

include(FetchContent)
include(LoadVersions)

# Fetch nlohmann_json for JSON parsing
if(NOT DEFINED NLOHMANN_JSON_VERSION)
    set(NLOHMANN_JSON_VERSION "3.11.3")
endif()

FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG        v${NLOHMANN_JSON_VERSION}
    GIT_SHALLOW    TRUE
)
set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
set(JSON_Install OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nlohmann_json)

# Workaround: nlohmann_json may use target_compile_features which fails with Xcode generator
# Override to use set_target_properties instead
if(TARGET nlohmann_json AND RAC_PLATFORM_IOS)
    set_target_properties(nlohmann_json PROPERTIES
        CXX_STANDARD 11
        CXX_STANDARD_REQUIRED YES
        CXX_EXTENSIONS NO
    )
endif()

# =============================================================================
# ONNX Backend Library (generic ONNX Runtime + RAG embeddings)
# =============================================================================
# Diffusion is Apple CoreML-only; no ONNX diffusion in this backend.
# v3.1.2: target declaration migrated to rac_add_engine_plugin() macro
# (cmake/plugins.cmake).

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

# Resolve the runanywhere-commons root for include paths.
get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

set(ONNX_BACKEND_SOURCES
    rac_onnx.cpp
    rac_backend_onnx_register.cpp
    rac_plugin_entry_onnx.cpp
)

# ONNX embedding provider lives in commons under src/features/rag/ but is
# compiled HERE (into rac_backend_onnx) to avoid a shared-library cycle:
# rac_commons -> rac_backend_rag -> rac_backend_onnx -> rac_commons.
#
# Phase 1 / B1 fix: previously this pointed at engines/onnx/../../features/rag
# which resolves to features/rag at the repo root (does not exist), so the
# EXISTS check below silently SKIPPED both files and the embeddings provider
# never compiled — leaving rac_backend_onnx_embeddings_register and
# g_onnx_embeddings_ops as unresolved externals at every final link site
# that touched the ONNX plugin entry. Path now points at the real location.
set(RAG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons/src/features/rag")
set(ONNX_EXTRA_INCLUDES "")
if(RAC_BACKEND_RAG AND EXISTS "${RAG_DIR}/onnx_embedding_provider.cpp")
    list(APPEND ONNX_BACKEND_SOURCES
        ${RAG_DIR}/onnx_embedding_provider.cpp
        ${RAG_DIR}/rac_onnx_embeddings_register.cpp
    )
    list(APPEND ONNX_EXTRA_INCLUDES ${RAG_DIR})
    message(STATUS "  ONNX embedding provider: Compiled into rac_backend_onnx (from RAG dir)")
endif()

# Compose link libs + compile defs. ORT C API ownership lives in
# runtimes/onnxrt; this engine uses only its thin session wrapper.
set(ONNX_LINK_LIBS rac_runtime_onnxrt nlohmann_json::nlohmann_json)
set(ONNX_COMPILE_DEFS RAC_ONNX_BUILDING RAC_HAS_ONNX)
if(NOT TARGET rac_runtime_onnxrt)
    message(FATAL_ERROR "RAC_BACKEND_ONNX requires rac_runtime_onnxrt. Enable RAC_RUNTIME_ONNXRT or disable RAC_BACKEND_ONNX.")
endif()
set(RAC_ONNX_SHERPA_COMPAT_AVAILABLE OFF)
if(TARGET rac_backend_sherpa)
    list(APPEND ONNX_LINK_LIBS rac_backend_sherpa)
    list(APPEND ONNX_COMPILE_DEFS RAC_ONNX_SHERPA_COMPAT=1)
    list(APPEND ONNX_EXTRA_INCLUDES ${CMAKE_CURRENT_SOURCE_DIR}/../sherpa)
    set(RAC_ONNX_SHERPA_COMPAT_AVAILABLE ON)
endif()

# v3.1.2: TARGET_NAME=rac_backend_onnx preserves the historical CMake
# target name so the 52 existing references across tests + sample apps +
# RN Android linker config + WASM exports keep working without renaming.
# CXX_STANDARD=20 because the ONNX backend uses std::span / concepts.
# SHARED_ONLY → always a standalone library target (never folded into
# rac_commons). Required because:
#   * the platform-specific `target_link_libraries(rac_backend_onnx ...)`
#     blocks below assume the target exists, and
#   * the Swift xcframework layout distributes the ONNX backend as a
#     SEPARATE xcframework (RABackendONNX) from RACommons.
# Default linkage is STATIC unless RAC_BUILD_SHARED=ON, which matches the
# pre-v3.1.2 hand-rolled CMakeLists exactly and produces the .a archive
# the xcframework packager consumes on iOS.
rac_add_engine_plugin(onnx
    TARGET_NAME         rac_backend_onnx
    CXX_STANDARD        20
    SHARED_ONLY
    SOURCES             ${ONNX_BACKEND_SOURCES}
    LINK_LIBRARIES      ${ONNX_LINK_LIBS}
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
                        ${RAC_COMMONS_ROOT_DIR}/src
                        ${ONNX_EXTRA_INCLUDES}
    COMPILE_DEFINITIONS ${ONNX_COMPILE_DEFS}
    RUNTIMES            ONNXRT
    FORMATS             ONNX
)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RAC_PLATFORM_WASM)
    # WASM: CPU-only, no platform acceleration
    target_compile_definitions(rac_backend_onnx PRIVATE RAC_PLATFORM_WASM=1)
    message(STATUS "ONNX Backend: CPU-only EP for WASM")

elseif(RAC_PLATFORM_IOS)
    target_link_libraries(rac_backend_onnx PUBLIC
        "-framework Foundation"
        "-framework CoreML"
        "-framework Accelerate"
    )
    # CoreML Execution Provider is available in ONNX Runtime iOS package
    target_compile_definitions(rac_backend_onnx PRIVATE ORT_USE_COREML=1)
    message(STATUS "ONNX Backend: CoreML EP enabled for iOS")

elseif(RAC_PLATFORM_ANDROID)
    target_link_libraries(rac_backend_onnx PRIVATE log)
    # Don't use -fvisibility=hidden here - JNI bridge needs these symbols
    target_compile_options(rac_backend_onnx PRIVATE -O3 -ffunction-sections -fdata-sections)
        # Ensure ORT_API_VERSION matches bundled libonnxruntime (1.17.x -> API 17)
        target_compile_definitions(rac_backend_onnx PRIVATE ORT_API_VERSION=17)
    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    target_link_options(rac_backend_onnx PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
    # NNAPI Execution Provider for Android NPU acceleration
    target_compile_definitions(rac_backend_onnx PRIVATE ORT_USE_NNAPI=1)
    message(STATUS "ONNX Backend: NNAPI EP enabled for Android")

elseif(RAC_PLATFORM_MACOS)
    target_link_libraries(rac_backend_onnx PUBLIC
        "-framework Foundation"
        "-framework CoreML"
        "-framework Accelerate"
    )
    # CoreML Execution Provider is available in ONNX Runtime macOS package
    target_compile_definitions(rac_backend_onnx PRIVATE ORT_USE_COREML=1)
    message(STATUS "ONNX Backend: CoreML EP enabled for macOS")

elseif(RAC_PLATFORM_LINUX)
    target_link_libraries(rac_backend_onnx PUBLIC pthread dl)

elseif(RAC_PLATFORM_WINDOWS)
    # No extra link libraries needed on Windows
    message(STATUS "ONNX Backend: CPU EP for Windows")
endif()

# =============================================================================
# JNI TARGET (Android)
# =============================================================================

if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED AND RAC_BUILD_JNI)
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
        set(_RAC_ANDROID_NDK_HOST_TAG "darwin-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
        set(_RAC_ANDROID_NDK_HOST_TAG "linux-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
        set(_RAC_ANDROID_NDK_HOST_TAG "windows-x86_64")
    else()
        message(FATAL_ERROR "Unsupported host platform for Android JNI bridge: ${CMAKE_HOST_SYSTEM_NAME}")
    endif()

    set(_RAC_ANDROID_NDK_SYSROOT_INCLUDE
        "${CMAKE_ANDROID_NDK}/toolchains/llvm/prebuilt/${_RAC_ANDROID_NDK_HOST_TAG}/sysroot/usr/include")
    if(NOT EXISTS "${_RAC_ANDROID_NDK_SYSROOT_INCLUDE}/jni.h")
        message(FATAL_ERROR "Could not locate Android NDK JNI headers at ${_RAC_ANDROID_NDK_SYSROOT_INCLUDE}")
    endif()

    message(STATUS "Building ONNX JNI bridge for Android")

    add_library(rac_backend_onnx_jni SHARED jni/rac_backend_onnx_jni.cpp)

    target_include_directories(rac_backend_onnx_jni PRIVATE
        ${_RAC_ANDROID_NDK_SYSROOT_INCLUDE}
        ${_RAC_ANDROID_NDK_SYSROOT_INCLUDE}/android
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )

    target_link_libraries(rac_backend_onnx_jni PRIVATE
        rac_backend_onnx
        log
    )

    target_compile_options(rac_backend_onnx_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    target_link_options(rac_backend_onnx_jni PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "ONNX Backend Configuration:")
message(STATUS "  ONNX Runtime: Enabled")
message(STATUS "  Speech compatibility shims: ${RAC_ONNX_SHERPA_COMPAT_AVAILABLE}")
message(STATUS "  Diffusion:    Not in ONNX backend (Apple CoreML only)")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
