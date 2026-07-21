# =============================================================================
# LlamaCPP Backend - Text Generation via llama.cpp
# =============================================================================

# Per-engine build toggle owned locally. Self-gating via return() keeps
# this decision out of commons and out of engines/CMakeLists.txt.
option(RAC_BACKEND_LLAMACPP "Build LlamaCPP backend" ON)
if(NOT RAC_BACKEND_LLAMACPP)
    return()
endif()

message(STATUS "Configuring LlamaCPP backend...")

# =============================================================================
# Fetch llama.cpp
# =============================================================================

include(FetchContent)
include(LoadVersions)

# Propagate llama.cpp upstream tag through to the JNI bridge so
# nativeGetVersion() doesn't drift from the actual linked llama.cpp build.
add_compile_definitions(RAC_LLAMACPP_VERSION="${RAC_LLAMACPP_VERSION}")

# Repo + tag both come from sdk/runanywhere-commons/VERSIONS (via LoadVersions)
# so a fork swap (e.g. the PrismML Bonsai fork) is a VERSIONS-only change.
# Fall back to upstream when the key is absent (older VERSIONS files).
if(NOT RAC_LLAMACPP_GIT_REPOSITORY)
    set(RAC_LLAMACPP_GIT_REPOSITORY "https://github.com/ggerganov/llama.cpp.git")
endif()
message(STATUS "llama.cpp source: ${RAC_LLAMACPP_GIT_REPOSITORY} @ ${RAC_LLAMACPP_VERSION}")

FetchContent_Declare(
    llamacpp
    GIT_REPOSITORY ${RAC_LLAMACPP_GIT_REPOSITORY}
    GIT_TAG        ${RAC_LLAMACPP_VERSION}
    GIT_SHALLOW    TRUE
    GIT_PROGRESS   TRUE
    # Fix the ggml arch/arm/quants.c armv7 build break (raw AArch64-only vqtbl1q_u8 -> portable wrapper).
    # Idempotent + no-op when the pattern/file is absent, so it is safe on every arch and future llama.cpp bump.
    PATCH_COMMAND ${CMAKE_COMMAND} -P "${CMAKE_CURRENT_LIST_DIR}/patch_ggml_armv7.cmake"
)

# Configure llama.cpp build options
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(LLAMA_HTTPLIB OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

# Platform-specific optimizations
if(RAC_PLATFORM_IOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)  # Embed precompiled Metal shaders
elseif(RAC_PLATFORM_ANDROID)
    # Disable features not available on Android
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
    set(GGML_CUDA OFF CACHE BOOL "" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
    set(GGML_HIPBLAS OFF CACHE BOOL "" FORCE)
    set(GGML_SYCL OFF CACHE BOOL "" FORCE)
    set(GGML_KOMPUTE OFF CACHE BOOL "" FORCE)
    set(GGML_RPC OFF CACHE BOOL "" FORCE)

    # CRITICAL: Disable native CPU detection (fails during cross-compilation)
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)

    # Enable ARM NEON only for ARM architectures (not x86/x86_64). armeabi-v7a keeps
    # NEON on; the ggml arch/arm/quants.c armv7 build break (raw AArch64-only
    # vqtbl1q_u8) is fixed by the FetchContent PATCH_COMMAND above, not by dropping NEON.
    if(ANDROID_ABI MATCHES "arm64-v8a|armeabi-v7a")
        set(GGML_NEON ON CACHE BOOL "" FORCE)
        message(STATUS "Enabling NEON for ARM ABI: ${ANDROID_ABI}")
    else()
        set(GGML_NEON OFF CACHE BOOL "" FORCE)
        # x86/x86_64 will use SSE/AVX automatically
        message(STATUS "Disabling NEON for non-ARM ABI: ${ANDROID_ABI}")
    endif()

    # Android-specific settings
    set(ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES ON CACHE BOOL "" FORCE)
    set(GGML_CPU_HBM OFF CACHE BOOL "" FORCE)

    # Disable openmp to avoid Android threading issues
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
elseif(RAC_PLATFORM_MACOS)
    # Allow upstream callers (CI test preset, command-line) to opt out of
    # GGML_METAL by setting it OFF before the project() call. Recent
    # Xcode / Apple Clang strict-ARC errors in ggml-metal-device.m make
    # the Metal build unusable for headless CMake test jobs; the CPU
    # path is enough for unit tests.
    if(NOT DEFINED CACHE{GGML_METAL})
        set(GGML_METAL ON CACHE BOOL "" FORCE)
    endif()
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    if(GGML_METAL)
        set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)  # Embed precompiled Metal shaders
    endif()
    # llama.cpp's vendored cpp-httplib auto-enables CPPHTTPLIB_OPENSSL_SUPPORT
    # whenever find_package(OpenSSL) succeeds (LLAMA_OPENSSL defaults ON). On a
    # native macOS release host Homebrew OpenSSL is discoverable, so
    # httplib.cpp.o compiles in the TLS path and drags ~100 unresolved
    # SSL_/EVP_/ASN1_/BIO_ symbols into the static slice with no provider. A
    # full-backend macOS app links that slice with -all_load, which force-loads
    # this dead httplib path (SDK downloads go through the platform adapter, not
    # cpp-httplib) and fails the link on the undefined OpenSSL symbols. iOS never
    # hits this because the OpenSSL find fails under cross-compilation, so disable
    # it here to make the macOS slice match iOS. Apple/macOS-scoped —
    # Linux/Android keep their existing behavior.
    set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
elseif(RAC_PLATFORM_LINUX)
    # Disable GPU backends not typically available on Linux ARM
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_CUDA OFF CACHE BOOL "" FORCE)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
    set(GGML_HIPBLAS OFF CACHE BOOL "" FORCE)
    set(GGML_SYCL OFF CACHE BOOL "" FORCE)

    # Enable ARM NEON for aarch64 (Raspberry Pi 5)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64")
        set(GGML_NEON ON CACHE BOOL "" FORCE)
        message(STATUS "Enabling NEON for Linux aarch64")
    endif()
elseif(RAC_PLATFORM_WINDOWS)
    # Windows: CPU-only by default. Opt into the CUDA (NVIDIA) GPU backend with
    # -DRAC_GPU_CUDA=ON (requires the CUDA toolkit + MSVC). llama.cpp's common_fit
    # then auto-offloads layers to fit VRAM; nothing else changes.
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
    set(GGML_HIPBLAS OFF CACHE BOOL "" FORCE)
    set(GGML_SYCL OFF CACHE BOOL "" FORCE)
    set(GGML_KOMPUTE OFF CACHE BOOL "" FORCE)
    set(GGML_RPC OFF CACHE BOOL "" FORCE)
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    if(RAC_GPU_CUDA)
        set(GGML_CUDA ON CACHE BOOL "" FORCE)
        if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
            set(CMAKE_CUDA_ARCHITECTURES 86 CACHE STRING "" FORCE) # Ampere (RTX 30-series)
        endif()
        message(STATUS "Configuring llama.cpp for Windows (CUDA / GPU, arch ${CMAKE_CUDA_ARCHITECTURES})")
    else()
        set(GGML_CUDA OFF CACHE BOOL "" FORCE)
        message(STATUS "Configuring llama.cpp for Windows (CPU-only)")
    endif()
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries for llama.cpp" FORCE)

FetchContent_MakeAvailable(llamacpp)

# Android: map POSIX_MADV_* to MADV_* to avoid missing constants
if(RAC_PLATFORM_ANDROID)
    if(TARGET llama)
        target_compile_definitions(llama PRIVATE
            POSIX_MADV_WILLNEED=MADV_WILLNEED
            POSIX_MADV_RANDOM=MADV_RANDOM
            posix_madvise=madvise
        )
    endif()
endif()

# Windows/MSVC: this repo forces C++20, under which llama.cpp's u8"" string
# literals become char8_t[] and no longer convert to const char* (llama-chat.cpp,
# llama-model.cpp, ...). Restore char-typed u8 literals for the llama.cpp targets.
if(MSVC)
    foreach(_llama_tgt IN ITEMS llama ggml ggml-base ggml-cpu common)
        if(TARGET ${_llama_tgt})
            target_compile_options(${_llama_tgt} PRIVATE /Zc:char8_t-)
        endif()
    endforeach()
endif()

# =============================================================================
# LlamaCPP Backend Library
# =============================================================================

set(LLAMACPP_BACKEND_SOURCES
    # LLM Backend
    llamacpp_backend.cpp
    rac_llm_llamacpp.cpp
    rac_embeddings_llamacpp.cpp
    rac_backend_llamacpp_register.cpp
    # Unified ABI plugin entry — fills both llm_ops and vlm_ops slots.
    rac_plugin_entry_llamacpp.cpp
    # VLM Backend (vision-language as a modality of the same engine).
    rac_vlm_llamacpp.cpp
    # VLM ops vtable (the g_llamacpp_vlm_ops struct consumed by the unified
    # plugin entry). Extracted from the (now-deleted) VLM register file when
    # the two plugin entries were unified.
    rac_llamacpp_vlm_ops.cpp
)

set(LLAMACPP_BACKEND_HEADERS
    llamacpp_backend.h
    llamacpp_stop_helpers.h
)

# VLM multimodal support is always compiled in — llama.cpp is one engine
# that supports both LLM and VLM modalities. The two are exposed through
# a single unified plugin vtable, not two separate plugins.
#
# Add mtmd sources from llama.cpp tools directory. mtmd-image.cpp carries
# the `mtmd_image_preprocessor_*` vtables that mtmd.cpp references during
# `mtmd_context::init_vision()`; without it ld.lld on Linux/Android complains:
#   ld.lld: error: undefined symbol: vtable for
#     mtmd_image_preprocessor_{llava_uhd,step3vl,idefics3,internvl}
list(APPEND LLAMACPP_BACKEND_SOURCES
    ${llamacpp_SOURCE_DIR}/tools/mtmd/mtmd.cpp
    ${llamacpp_SOURCE_DIR}/tools/mtmd/mtmd-helper.cpp
    ${llamacpp_SOURCE_DIR}/tools/mtmd/mtmd-audio.cpp
    ${llamacpp_SOURCE_DIR}/tools/mtmd/mtmd-image.cpp
    ${llamacpp_SOURCE_DIR}/tools/mtmd/clip.cpp
)

# Glob every mtmd model implementation upstream ships. The hand-curated list
# drifts each llama.cpp bump (b9180 adds deepseekocr / dotsocr / gemma4a /
# gemma4v / granite-speech / hunyuanocr / mimovl / qwen3a / step3vl / yasa2
# etc.). On Linux/Android the resulting clip_image_build_graph references
# unconditionally need every clip_graph_<name>::* vtable to be present at
# link time, otherwise ld.lld bails with
#   ld.lld: error: undefined symbol: vtable for clip_graph_<name>
# `CONFIGURE_DEPENDS` re-globs when the directory changes; it is best-effort
# on Visual Studio / Xcode generators but reliable on Ninja (which RAC's
# CMakePresets use). Developers running an Xcode-driven CMake build for
# on-device profiling MUST `cmake --reconfigure` after an upstream llama.cpp
# bump that adds a new tools/mtmd/models/*.cpp file.
file(GLOB _RAC_MTMD_MODEL_SOURCES CONFIGURE_DEPENDS
    "${llamacpp_SOURCE_DIR}/tools/mtmd/models/*.cpp"
)
list(LENGTH _RAC_MTMD_MODEL_SOURCES _RAC_MTMD_MODEL_COUNT)
message(STATUS "VLM mtmd model implementations discovered: ${_RAC_MTMD_MODEL_COUNT} (llama.cpp ${RAC_LLAMACPP_VERSION})")
list(APPEND LLAMACPP_BACKEND_SOURCES ${_RAC_MTMD_MODEL_SOURCES})

# Migrated to rac_add_engine_plugin().
#
# Two distinct outputs share the same source list:
#
#   * `rac_backend_llamacpp`  — the engine implementation (op-structs,
#     plugin entry, optional VLM mtmd sources). Produced via the macro
#     with SHARED_ONLY so it stays a separate library regardless of
#     RAC_STATIC_PLUGINS (the JNI bridge + per-platform link blocks
#     reference the target by name and need default visibility).
#
#   * `runanywhere_llamacpp`  — the thin self-registration carrier built
#     from `rac_static_register_llamacpp.cpp`. Two modes:
#       - RAC_STATIC_PLUGINS=ON:  the .cpp is added directly to rac_commons
#                                 so the file-scope ctor schedules
#                                 RAC_STATIC_PLUGIN_REGISTER(llamacpp)
#                                 before main() (iOS / WASM hosts).
#       - RAC_STATIC_PLUGINS=OFF: the .cpp is the entry-symbol carrier of
#                                 a SHARED library loaded at runtime via
#                                 rac_registry_load_plugin().
#
# Resolve the runanywhere-commons root before the macro call so the
# include path list below references it. Was sdk/runanywhere-commons/
# src/backends/<name>/ → ../../.. = commons; now engines/<name>/ →
# ../../sdk/runanywhere-commons.
get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../sdk/runanywhere-commons" ABSOLUTE)

include(${CMAKE_SOURCE_DIR}/cmake/plugins.cmake)

rac_add_engine_plugin(llamacpp
    TARGET_NAME         rac_backend_llamacpp
    CXX_STANDARD        20
    SHARED_ONLY                          # always a standalone target — matches onnx
    SOURCES             ${LLAMACPP_BACKEND_SOURCES}
                        ${LLAMACPP_BACKEND_HEADERS}
    # llama.cpp b9180 renamed the `common` static library target to
    # `llama-common` (see _deps/llamacpp-src/common/CMakeLists.txt) — the old
    # bare `common` symbol is no longer exported, so linking macOS jobs
    # bailed with `ld: library 'common' not found`.
    LINK_LIBRARIES      llama llama-common
    INCLUDE_DIRECTORIES ${RAC_COMMONS_ROOT_DIR}/include
                        ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
                        ${RAC_COMMONS_ROOT_DIR}/src   # core/internal/platform_compat.h (POSIX dirent/stat shim on MSVC)
                        ${CMAKE_CURRENT_SOURCE_DIR}/..  # engines/ — for engines/common/*.h
                        ${llamacpp_SOURCE_DIR}/include
                        ${llamacpp_SOURCE_DIR}/src    # llama-adapter.h for LoRA introspection
                        ${llamacpp_SOURCE_DIR}/common
                        ${llamacpp_SOURCE_DIR}/ggml/include
                        ${llamacpp_SOURCE_DIR}/vendor # nlohmann/json.hpp
    COMPILE_DEFINITIONS RAC_LLAMACPP_BUILDING
    AVAILABILITY        PUBLIC
    PACKAGE_OWNER       runanywhere
    PACKAGE_NAME        runanywhere_llamacpp
)

# VLM multimodal mtmd includes — engine-specific, applied after the macro.
# mtmd is always compiled in (one engine, two modalities).
target_include_directories(rac_backend_llamacpp PRIVATE
    ${llamacpp_SOURCE_DIR}/tools/mtmd
    ${llamacpp_SOURCE_DIR}/tools/mtmd/models
)

# Self-registration carrier: thin shim that wraps RAC_STATIC_PLUGIN_REGISTER.
# Since llama.cpp is one engine with both LLM and VLM modalities exposed by
# the same plugin vtable, there is a single static-register shim and a single
# SHARED carrier (no separate _vlm variants).
if(RAC_STATIC_PLUGINS)
    # Static path: ctor lands inside rac_commons so it runs before main().
    # rac_commons PUBLIC-links rac_backend_llamacpp below so the entry
    # symbol resolves at link time.
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_llamacpp.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    # Shared-plugin path: SHARED library whose only export is the entry
    # symbol; the actual op functions live in rac_backend_llamacpp.
    add_library(runanywhere_llamacpp SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_llamacpp.cpp
    )
    set_target_properties(runanywhere_llamacpp PROPERTIES
        OUTPUT_NAME           runanywhere_llamacpp
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_link_libraries(runanywhere_llamacpp PUBLIC
        rac_backend_llamacpp
        rac_commons
    )
    rac_apply_android_page_alignment(runanywhere_llamacpp)
    install(TARGETS runanywhere_llamacpp LIBRARY DESTINATION lib)
endif()

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RAC_PLATFORM_IOS)
    message(STATUS "Configuring LlamaCPP backend for iOS")
    target_link_libraries(rac_backend_llamacpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
    target_compile_definitions(rac_backend_llamacpp PRIVATE GGML_USE_METAL=1)

elseif(RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring LlamaCPP backend for Android")
    target_link_libraries(rac_backend_llamacpp PRIVATE log)
    # Don't use -fvisibility=hidden here - JNI bridge needs these symbols
    target_compile_options(rac_backend_llamacpp PRIVATE -O3 -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    rac_apply_android_page_alignment(rac_backend_llamacpp)

elseif(RAC_PLATFORM_MACOS)
    message(STATUS "Configuring LlamaCPP backend for macOS")
    target_link_libraries(rac_backend_llamacpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )

elseif(RAC_PLATFORM_LINUX)
    message(STATUS "Configuring LlamaCPP backend for Linux")
    # Linux-specific link libraries
    target_link_libraries(rac_backend_llamacpp PUBLIC pthread dl)

elseif(RAC_PLATFORM_WINDOWS)
    message(STATUS "Configuring LlamaCPP backend for Windows")
    # No extra link libraries needed on Windows (threading is built-in)
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

    message(STATUS "Building LlamaCPP JNI bridge for Android")

    add_library(rac_backend_llamacpp_jni SHARED
        jni/rac_backend_llamacpp_jni.cpp
    )

    target_include_directories(rac_backend_llamacpp_jni PRIVATE
        ${_RAC_ANDROID_NDK_SYSROOT_INCLUDE}
        ${_RAC_ANDROID_NDK_SYSROOT_INCLUDE}/android
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )

    target_link_libraries(rac_backend_llamacpp_jni PRIVATE
        rac_backend_llamacpp
        log
    )

    target_compile_options(rac_backend_llamacpp_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    rac_apply_android_page_alignment(rac_backend_llamacpp_jni)
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "LlamaCPP Backend Configuration:")
message(STATUS "  llama.cpp version: ${RAC_LLAMACPP_VERSION}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
