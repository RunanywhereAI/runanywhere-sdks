# =============================================================================
# WhisperCPP Backend - Speech-to-Text via whisper.cpp
# =============================================================================
#
# This backend provides:
# - STT: Via whisper.cpp for GGML Whisper models (transcription, translation, language detection)
# =============================================================================

message(STATUS "Configuring WhisperCPP backend...")

# =============================================================================
# Fetch whisper.cpp
# =============================================================================

include(FetchContent)

# Load centralized versions
include(LoadVersions)

# Use version from VERSIONS file (with fallback for backward compatibility)
# Note: Repository moved from ggerganov/whisper.cpp to ggml-org/whisper.cpp
if(NOT DEFINED WHISPERCPP_VERSION)
    set(WHISPERCPP_VERSION "v1.8.2")  # Fallback if VERSIONS file not loaded
endif()
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
set(WHISPER_COREML OFF CACHE BOOL "" FORCE)  # Disabled for simplicity - Metal provides good performance
set(WHISPER_OPENVINO OFF CACHE BOOL "" FORCE)

# =============================================================================
# GGML Symbol Conflict Resolution
# =============================================================================
# When both whisper.cpp and llama.cpp are enabled, they both include GGML.
# We need to handle this to avoid duplicate symbol errors.
#
# whisper.cpp supports WHISPER_USE_SYSTEM_GGML to use an external GGML.
# However, the integration is complex. For now, we build whisper.cpp's GGML
# separately and handle any conflicts at link time.
# =============================================================================

if(RA_BUILD_LLAMACPP)
    message(STATUS "LlamaCPP is also enabled - whisper.cpp will use its own GGML (may have conflicts)")
    # Note: In practice, static linking with --allow-multiple-definition or
    # careful library ordering usually resolves this.
    # If issues arise, we can explore WHISPER_USE_SYSTEM_GGML option.
endif()

# Platform-specific optimizations
if(RA_PLATFORM_IOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
elseif(RA_PLATFORM_ANDROID)
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_NEON ON CACHE BOOL "" FORCE)
elseif(RA_PLATFORM_MACOS)
    set(GGML_METAL ON CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
    set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
endif()

# CRITICAL: Force whisper.cpp to build as STATIC libraries for iOS/Android xcframeworks
# Without this, whisper.cpp builds as .dylib which can't be combined into static xcframeworks
set(BUILD_SHARED_LIBS OFF CACHE BOOL "Force static libraries for whisper.cpp" FORCE)

FetchContent_MakeAvailable(whispercpp)

# =============================================================================
# WhisperCPP Backend Library
# =============================================================================

set(WHISPERCPP_BACKEND_SOURCES
    whispercpp_backend.cpp
)

set(WHISPERCPP_BACKEND_HEADERS
    whispercpp_backend.h
)

# Choose library type based on parent's RA_BUILD_SHARED option
if(RA_BUILD_SHARED)
    add_library(runanywhere_whispercpp SHARED
        ${WHISPERCPP_BACKEND_SOURCES}
        ${WHISPERCPP_BACKEND_HEADERS}
    )
else()
    add_library(runanywhere_whispercpp STATIC
        ${WHISPERCPP_BACKEND_SOURCES}
        ${WHISPERCPP_BACKEND_HEADERS}
    )
endif()

target_include_directories(runanywhere_whispercpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/capabilities            # Capabilities headers
    ${CMAKE_SOURCE_DIR}                         # Backend source root
    ${CMAKE_SOURCE_DIR}/../include              # Public headers
    ${CMAKE_SOURCE_DIR}/../include/backends     # Backend public headers
    ${RAC_INCLUDE_DIR}                          # Commons headers (rac/core/*)
    ${whispercpp_SOURCE_DIR}/include
    ${whispercpp_SOURCE_DIR}/ggml/include
)

# Link whisper.cpp libraries
target_link_libraries(runanywhere_whispercpp PUBLIC
    runanywhere_capabilities
    whisper
)

target_compile_features(runanywhere_whispercpp PUBLIC cxx_std_17)

# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RA_PLATFORM_IOS)
    message(STATUS "Configuring WhisperCPP backend for iOS")

    target_link_libraries(runanywhere_whispercpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )

    target_compile_definitions(runanywhere_whispercpp PRIVATE
        GGML_USE_METAL=1
    )

elseif(RA_PLATFORM_ANDROID)
    message(STATUS "Configuring WhisperCPP backend for Android")
    target_link_libraries(runanywhere_whispercpp PRIVATE log)

    # Optimization flags for Android
    target_compile_options(runanywhere_whispercpp PRIVATE
        -O3
        -fvisibility=hidden
        -ffunction-sections
        -fdata-sections
    )

    target_link_options(runanywhere_whispercpp PRIVATE
        -Wl,--gc-sections
    )

elseif(RA_PLATFORM_MACOS)
    message(STATUS "Configuring WhisperCPP backend for macOS")
    target_link_libraries(runanywhere_whispercpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
endif()

# =============================================================================
# RAC API LIBRARY (directly exports rac_* C APIs)
# =============================================================================

set(RAC_WHISPERCPP_SOURCES
    rac_stt_whispercpp.cpp
    rac_backend_whispercpp_register.cpp
)

add_library(rac_backend_whispercpp STATIC ${RAC_WHISPERCPP_SOURCES})

target_include_directories(rac_backend_whispercpp
    PUBLIC
        ${CMAKE_SOURCE_DIR}/../include            # Public RAC headers (rac_stt_whispercpp.h)
        ${CMAKE_SOURCE_DIR}/../include/backends   # Backend public headers
        ${RAC_INCLUDE_DIR}                        # Commons headers
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}               # Internal headers
        ${CMAKE_SOURCE_DIR}/capabilities          # Capabilities headers
)

target_link_libraries(rac_backend_whispercpp
    PRIVATE
        runanywhere_whispercpp
)

target_compile_features(rac_backend_whispercpp PUBLIC cxx_std_17)

# =============================================================================
# JNI TARGET (Android)
# =============================================================================

if(RA_PLATFORM_ANDROID AND RAC_BUILD_JNI)
    find_package(JNI REQUIRED)

    add_library(rac_backend_whispercpp_jni SHARED
        jni/rac_backend_whispercpp_jni.cpp
    )

    target_include_directories(rac_backend_whispercpp_jni PRIVATE
        ${JNI_INCLUDE_DIRS}
        ${CMAKE_SOURCE_DIR}/../include
        ${CMAKE_SOURCE_DIR}/../include/backends
        ${RAC_INCLUDE_DIR}                        # Commons headers
    )

    target_link_libraries(rac_backend_whispercpp_jni
        PRIVATE
            rac_backend_whispercpp
            ${JNI_LIBRARIES}
            log
    )

    install(TARGETS rac_backend_whispercpp_jni
        LIBRARY DESTINATION lib/${ANDROID_ABI}
        ARCHIVE DESTINATION lib/${ANDROID_ABI}
    )
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "WhisperCPP Backend Configuration:")
message(STATUS "  whisper.cpp version: ${WHISPER_CPP_VERSION}")
message(STATUS "  Repository: ggml-org/whisper.cpp")
message(STATUS "  Platform: ${RA_PLATFORM_NAME}")
message(STATUS "  CoreML: OFF (using Metal)")
