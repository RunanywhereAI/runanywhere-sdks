# =============================================================================
# LlamaCPP Backend - Text Generation via llama.cpp
# =============================================================================
#
# This backend provides:
# - TEXT_GENERATION: Via llama.cpp for GGUF/GGML models
# =============================================================================

message(STATUS "Configuring LlamaCPP backend...")

# =============================================================================
# Fetch llama.cpp
# =============================================================================

include(FetchContent)

# Load centralized versions
include(LoadVersions)

# Use version from VERSIONS file (with fallback for backward compatibility)
if(NOT DEFINED LLAMACPP_VERSION)
    set(LLAMACPP_VERSION "b7199")  # Fallback if VERSIONS file not loaded
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
set(LLAMA_HTTPLIB OFF CACHE BOOL "" FORCE)  # Disable httplib (download.o) for iOS/Android
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)

# Platform-specific optimizations
if(RA_PLATFORM_IOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
elseif(RA_PLATFORM_ANDROID)
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
    set(ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES ON CACHE BOOL "" FORCE)
elseif(RA_PLATFORM_MACOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
endif()

# CRITICAL: Force llama.cpp to build as STATIC libraries for iOS/Android xcframeworks
# Without this, llama.cpp builds as .dylib which can't be combined into static xcframeworks
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries for llama.cpp" FORCE)

FetchContent_MakeAvailable(llamacpp)

# =============================================================================
# LlamaCPP Backend Library
# =============================================================================

# C++ implementation (no legacy ra_* layer)
set(LLAMACPP_BACKEND_SOURCES
    llamacpp_backend.cpp
)

# RAC API implementation (moved from commons - calls C++ directly)
set(RAC_API_SOURCES
    rac_llm_llamacpp.cpp
)

# Registration code - included for all platforms
# For Android, we link against rac_commons to get the real implementations
list(APPEND RAC_API_SOURCES rac_backend_llamacpp_register.cpp)

set(LLAMACPP_BACKEND_HEADERS
    llamacpp_backend.h
)

# Choose library type based on parent's RA_BUILD_SHARED option
if(RA_BUILD_SHARED)
    add_library(runanywhere_llamacpp SHARED
        ${LLAMACPP_BACKEND_SOURCES}
        ${RAC_API_SOURCES}
        ${LLAMACPP_BACKEND_HEADERS}
    )
else()
    add_library(runanywhere_llamacpp STATIC
        ${LLAMACPP_BACKEND_SOURCES}
        ${RAC_API_SOURCES}
        ${LLAMACPP_BACKEND_HEADERS}
    )
endif()

target_include_directories(runanywhere_llamacpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/capabilities            # Capabilities headers (capabilities/backend.h)
    ${CMAKE_SOURCE_DIR}                         # Backend source root
    ${CMAKE_SOURCE_DIR}/../include              # Public headers (include/backends/rac_llm_llamacpp.h)
    ${CMAKE_SOURCE_DIR}/../include/backends     # Backend public headers
    ${RAC_INCLUDE_DIR}                          # Commons headers (rac/core/*)
    ${llamacpp_SOURCE_DIR}/include
    ${llamacpp_SOURCE_DIR}/common
    ${llamacpp_SOURCE_DIR}/ggml/include
)

# Add RAC headers include path if available
if(RAC_INCLUDE_DIR AND EXISTS "${RAC_INCLUDE_DIR}")
    target_include_directories(runanywhere_llamacpp PUBLIC
        ${RAC_INCLUDE_DIR}                     # RAC type headers from commons
    )
endif()

# Export symbols for RAC API
target_compile_definitions(runanywhere_llamacpp PRIVATE RAC_LLAMACPP_BUILDING)

# Link llama.cpp libraries
target_link_libraries(runanywhere_llamacpp PUBLIC
    runanywhere_capabilities
    llama
    common
)

target_compile_features(runanywhere_llamacpp PUBLIC cxx_std_17)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RA_PLATFORM_IOS)
    message(STATUS "Configuring LlamaCPP backend for iOS")

    target_link_libraries(runanywhere_llamacpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )

    target_compile_definitions(runanywhere_llamacpp PRIVATE
        GGML_USE_METAL=1
    )

elseif(RA_PLATFORM_ANDROID)
    message(STATUS "Configuring LlamaCPP backend for Android")
    target_link_libraries(runanywhere_llamacpp PRIVATE log)

    # Link against rac_commons for error handling, logging, events, and service registry
    if(RAC_COMMONS_LIBRARY_AVAILABLE)
        target_link_libraries(runanywhere_llamacpp PUBLIC rac_commons)
        message(STATUS "  Linked against rac_commons")
    endif()

    # Optimization flags for Android
    target_compile_options(runanywhere_llamacpp PRIVATE
        -O3
        -fvisibility=hidden
        -ffunction-sections
        -fdata-sections
    )

    target_link_options(runanywhere_llamacpp PRIVATE
        -Wl,--gc-sections
    )

elseif(RA_PLATFORM_MACOS)
    message(STATUS "Configuring LlamaCPP backend for macOS")
    target_link_libraries(runanywhere_llamacpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
endif()

# =============================================================================
# JNI TARGET (Android)
# =============================================================================

if(RA_PLATFORM_ANDROID AND RA_BUILD_SHARED)
    find_package(JNI QUIET)
    
    if(JNI_FOUND OR ANDROID)
        message(STATUS "Building LlamaCPP JNI bridge for Android")
        
        add_library(rac_backend_llamacpp_jni SHARED
            jni/rac_backend_llamacpp_jni.cpp
        )
        
        target_include_directories(rac_backend_llamacpp_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_SOURCE_DIR}/include
        )
        
        # Add RAC headers include path if available
        if(RAC_INCLUDE_DIR AND EXISTS "${RAC_INCLUDE_DIR}")
            target_include_directories(rac_backend_llamacpp_jni PRIVATE
                ${RAC_INCLUDE_DIR}
            )
        endif()
        
        target_link_libraries(rac_backend_llamacpp_jni
            PRIVATE
                runanywhere_llamacpp
                log
        )
        
        target_compile_definitions(rac_backend_llamacpp_jni PRIVATE RAC_LLAMACPP_BUILDING)
        
        target_compile_options(rac_backend_llamacpp_jni PRIVATE
            -O3
            -fvisibility=hidden
            -ffunction-sections
            -fdata-sections
        )
        
        target_link_options(rac_backend_llamacpp_jni PRIVATE
            -Wl,--gc-sections
        )
    endif()
endif()

# =============================================================================
# INSTALLATION
# =============================================================================

install(TARGETS runanywhere_llamacpp
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
)

install(FILES ${CMAKE_SOURCE_DIR}/include/rac_llm_llamacpp.h
    DESTINATION include/rac
)

# =============================================================================
# Summary
# =============================================================================

message(STATUS "LlamaCPP Backend Configuration:")
message(STATUS "  llama.cpp version: ${LLAMA_CPP_VERSION}")
message(STATUS "  Platform: ${RA_PLATFORM_NAME}")
message(STATUS "  RAC API: Enabled (direct C++ calls)")
if(RAC_INCLUDE_DIR)
    message(STATUS "  RAC headers: ${RAC_INCLUDE_DIR}")
endif()
