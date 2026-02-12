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
    set(LLAMACPP_VERSION "b7199")
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
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries for llama.cpp" FORCE)

FetchContent_MakeAvailable(llamacpp)

# =============================================================================
# LlamaCPP Backend Library
# =============================================================================

set(LLAMACPP_BACKEND_SOURCES
    # LLM Backend
    llamacpp_backend.cpp
    rac_llm_llamacpp.cpp
    rac_backend_llamacpp_register.cpp
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
    )
endif()

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

# Resolve the runanywhere-commons root (3 levels up from src/backends/llamacpp/)
get_filename_component(RAC_COMMONS_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

target_include_directories(rac_backend_llamacpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${RAC_COMMONS_ROOT_DIR}/include
    ${RAC_COMMONS_ROOT_DIR}/include/rac/backends
    ${llamacpp_SOURCE_DIR}/include
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

target_compile_features(rac_backend_llamacpp PUBLIC cxx_std_17)

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
