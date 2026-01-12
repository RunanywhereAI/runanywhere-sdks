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
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
    set(ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES ON CACHE BOOL "" FORCE)
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
    llamacpp_backend.cpp
    rac_llm_llamacpp.cpp
    rac_backend_llamacpp_register.cpp
)

set(LLAMACPP_BACKEND_HEADERS
    llamacpp_backend.h
)

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

target_include_directories(rac_backend_llamacpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/rac/backends
    ${llamacpp_SOURCE_DIR}/include
    ${llamacpp_SOURCE_DIR}/common
    ${llamacpp_SOURCE_DIR}/ggml/include
    ${llamacpp_SOURCE_DIR}/vendor               # nlohmann/json.hpp
)

target_compile_definitions(rac_backend_llamacpp PRIVATE RAC_LLAMACPP_BUILDING)

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
    target_link_options(rac_backend_llamacpp PRIVATE -Wl,--gc-sections)

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
            ${CMAKE_SOURCE_DIR}/include
        )

        target_link_libraries(rac_backend_llamacpp_jni PRIVATE
            rac_backend_llamacpp
            log
        )

        target_compile_options(rac_backend_llamacpp_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
        target_link_options(rac_backend_llamacpp_jni PRIVATE -Wl,--gc-sections)
    endif()
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "LlamaCPP Backend Configuration:")
message(STATUS "  llama.cpp version: ${LLAMA_CPP_VERSION}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
