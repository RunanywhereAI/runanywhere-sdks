# =============================================================================
# LlamaCPP Backend - Text Generation via llama.cpp
# =============================================================================

message(STATUS "Configuring LlamaCPP backend...")

# =============================================================================
# Fetch llama.cpp
# =============================================================================

include(FetchContent)
include(LoadVersions)

if(NOT DEFINED LLAMACPP_VERSION)
    set(LLAMACPP_VERSION "b8011")
endif()
set(LLAMA_CPP_VERSION "${LLAMACPP_VERSION}")

FetchContent_Declare(
    llamacpp
    GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
    GIT_TAG        ${LLAMA_CPP_VERSION}
    GIT_SHALLOW    TRUE
    GIT_PROGRESS   TRUE
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

    # Enable ARM NEON only for ARM architectures (not x86/x86_64)
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
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)  # Embed precompiled Metal shaders
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
    # Windows: CPU-only by default, no Metal/CUDA/Vulkan
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_CUDA OFF CACHE BOOL "" FORCE)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
    set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
    set(GGML_HIPBLAS OFF CACHE BOOL "" FORCE)
    set(GGML_SYCL OFF CACHE BOOL "" FORCE)
    set(GGML_KOMPUTE OFF CACHE BOOL "" FORCE)
    set(GGML_RPC OFF CACHE BOOL "" FORCE)
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    message(STATUS "Configuring llama.cpp for Windows (CPU-only)")
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

# =============================================================================
# LlamaCPP Backend Library
# =============================================================================

set(LLAMACPP_BACKEND_SOURCES
    # LLM Backend
    llamacpp_backend.cpp
    rac_llm_llamacpp.cpp
    rac_backend_llamacpp_register.cpp
    # GAP 02 Phase 8: unified engine plugin entry point. Coexists with the
    # legacy rac_backend_llamacpp_register() bootstrap; both wrap the same
    # ops-struct. See docs/engine_plugin_authoring.md.
    rac_plugin_entry_llamacpp.cpp
)

set(LLAMACPP_BACKEND_HEADERS
    llamacpp_backend.h
)

# Option to enable VLM multimodal support (requires mtmd from llama.cpp)
option(RAC_VLM_USE_MTMD "Enable VLM multimodal support via llama.cpp mtmd" ON)
if(RAC_VLM_USE_MTMD)
    message(STATUS "VLM multimodal support enabled")
    # Add VLM Backend sources (Vision Language Model)
    list(APPEND LLAMACPP_BACKEND_SOURCES
        rac_vlm_llamacpp.cpp
        rac_backend_llamacpp_vlm_register.cpp
        # GAP 02 Phase 8: unified engine plugin entry point for VLM.
        rac_plugin_entry_llamacpp_vlm.cpp
    )
    # Add mtmd sources from llama.cpp tools directory
    list(APPEND LLAMACPP_BACKEND_SOURCES
        ${llamacpp_SOURCE_DIR}/tools/mtmd/mtmd.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/mtmd-helper.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/mtmd-audio.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/clip.cpp
    )
    # Add mtmd model implementations (clip_graph_* classes)
    list(APPEND LLAMACPP_BACKEND_SOURCES
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/llava.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/qwen2vl.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/qwen3vl.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/minicpmv.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/glm4v.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/cogvlm.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/internvl.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/kimivl.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/llama4.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/siglip.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/pixtral.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/youtuvl.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/conformer.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/whisper-enc.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/kimik25.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/mobilenetv5.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/paddleocr.cpp
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models/nemotron-v2-vl.cpp
    )
endif()

# GAP 03 Phase 5: dual-mode build of the llama.cpp backend.
#
# Two distinct outputs share the same source list:
#
#   * `rac_backend_llamacpp`  (existing, legacy) — the per-domain
#     `rac_service_register_provider()` path, linked PUBLIC against
#     `rac_commons`. Always built; nothing changes for legacy callers.
#
#   * `runanywhere_llamacpp`  (new, GAP 03)      — the same TUs PLUS one
#     extra .cpp that calls `RAC_STATIC_PLUGIN_REGISTER(llamacpp)` so the
#     plugin self-registers when (a) statically linked into the host on
#     iOS / WASM, or (b) loaded as a SHARED library at runtime via
#     `rac_registry_load_plugin("librunanywhere_llamacpp.so")` on Android /
#     Linux / macOS / Windows.
#
# Build modes:
#   - RAC_STATIC_PLUGINS=ON:  runanywhere_llamacpp is OBJECT — its sources
#                             land directly in rac_commons via the `engine`
#                             target_link path.
#   - RAC_STATIC_PLUGINS=OFF (default off-iOS): runanywhere_llamacpp is
#                             SHARED. Installed under the conventional
#                             librunanywhere_llamacpp.so name so the loader's
#                             `entry_symbol_from_path()` heuristic resolves
#                             `rac_plugin_entry_llamacpp`.
if(RAC_BUILD_SHARED)
    add_library(rac_backend_llamacpp SHARED
        ${LLAMACPP_BACKEND_SOURCES}
        ${LLAMACPP_BACKEND_HEADERS}
    )
else()
    add_library(rac_backend_llamacpp STATIC
        ${LLAMACPP_BACKEND_SOURCES}
        ${LLAMACPP_BACKEND_HEADERS}
    )
endif()

if(RAC_STATIC_PLUGINS)
    # Static-plugins path: add the static-register TU directly to rac_commons.
    # rac_commons already PUBLIC-links rac_backend_llamacpp (further down this
    # file) so the static-register symbol resolves at link time.
    target_sources(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_llamacpp.cpp
    )
    target_include_directories(rac_commons PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${RAC_COMMONS_ROOT_DIR}/include
    )
else()
    # Shared-plugin path: ship a thin SHARED library whose only job is to
    # carry the rac_plugin_entry_llamacpp symbol + the static-register stub.
    # The actual op functions live in rac_backend_llamacpp.
    add_library(runanywhere_llamacpp SHARED
        ${CMAKE_CURRENT_SOURCE_DIR}/rac_static_register_llamacpp.cpp
    )
    set_target_properties(runanywhere_llamacpp PROPERTIES
        OUTPUT_NAME      runanywhere_llamacpp
        # Default-visibility on the entry symbol; everything else hidden.
        C_VISIBILITY_PRESET   hidden
        CXX_VISIBILITY_PRESET hidden
    )
    target_link_libraries(runanywhere_llamacpp PUBLIC
        rac_backend_llamacpp
        rac_commons
    )
    install(TARGETS runanywhere_llamacpp LIBRARY DESTINATION lib)
endif()

# Resolve the runanywhere-commons root (3 levels up from src/backends/llamacpp/)
get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

target_include_directories(rac_backend_llamacpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${RAC_COMMONS_ROOT_DIR}/include
    ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
    ${llamacpp_SOURCE_DIR}/include
    ${llamacpp_SOURCE_DIR}/src                  # Internal headers (llama-adapter.h for LoRA introspection)
    ${llamacpp_SOURCE_DIR}/common
    ${llamacpp_SOURCE_DIR}/ggml/include
    ${llamacpp_SOURCE_DIR}/vendor               # nlohmann/json.hpp
)

# VLM multimodal includes (mtmd)
if(RAC_VLM_USE_MTMD)
    target_include_directories(rac_backend_llamacpp PRIVATE
        ${llamacpp_SOURCE_DIR}/tools/mtmd
        ${llamacpp_SOURCE_DIR}/tools/mtmd/models
    )
endif()

target_compile_definitions(rac_backend_llamacpp PRIVATE RAC_LLAMACPP_BUILDING)

# VLM multimodal compile definition
if(RAC_VLM_USE_MTMD)
    target_compile_definitions(rac_backend_llamacpp PRIVATE RAC_VLM_USE_MTMD=1)
endif()

target_link_libraries(rac_backend_llamacpp PUBLIC
    rac_commons
    llama
    common
)

set_target_properties(rac_backend_llamacpp PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

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
    target_link_options(rac_backend_llamacpp PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

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

if(RAC_PLATFORM_ANDROID AND RAC_BUILD_SHARED)
    if(ANDROID)
        message(STATUS "Building LlamaCPP JNI bridge for Android")

        add_library(rac_backend_llamacpp_jni SHARED
            jni/rac_backend_llamacpp_jni.cpp
        )

        target_include_directories(rac_backend_llamacpp_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${RAC_COMMONS_ROOT_DIR}/include
        )

        target_link_libraries(rac_backend_llamacpp_jni PRIVATE
            rac_backend_llamacpp
            log
        )

        target_compile_options(rac_backend_llamacpp_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
        # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
        target_link_options(rac_backend_llamacpp_jni PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
    endif()
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "LlamaCPP Backend Configuration:")
message(STATUS "  llama.cpp version: ${LLAMA_CPP_VERSION}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
