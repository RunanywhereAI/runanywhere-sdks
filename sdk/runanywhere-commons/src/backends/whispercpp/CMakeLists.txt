# =============================================================================
# WhisperCPP Backend - Speech-to-Text via whisper.cpp
# =============================================================================

message(STATUS "Configuring WhisperCPP backend...")

# =============================================================================
# Dependencies
# =============================================================================

include(FetchContent)
include(LoadVersions)

# Fetch nlohmann_json for JSON parsing (if not already available)
if(NOT TARGET nlohmann_json::nlohmann_json)
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
    FetchContent_MakeAvailable(nlohmann_json)
endif()

# =============================================================================
# Fetch whisper.cpp
# =============================================================================

if(NOT DEFINED WHISPERCPP_VERSION)
    set(WHISPERCPP_VERSION "v1.8.2")
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

set(WHISPERCPP_BACKEND_SOURCES
    whispercpp_backend.cpp
    rac_stt_whispercpp.cpp
    rac_backend_whispercpp_register.cpp
)

set(WHISPERCPP_BACKEND_HEADERS
    whispercpp_backend.h
)

if(RAC_BUILD_SHARED)
    add_library(rac_backend_whispercpp SHARED ${WHISPERCPP_BACKEND_SOURCES} ${WHISPERCPP_BACKEND_HEADERS})
else()
    add_library(rac_backend_whispercpp STATIC ${WHISPERCPP_BACKEND_SOURCES} ${WHISPERCPP_BACKEND_HEADERS})
endif()

target_include_directories(rac_backend_whispercpp PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_SOURCE_DIR}/include
    ${CMAKE_SOURCE_DIR}/include/rac/backends
    ${whispercpp_SOURCE_DIR}/include
    ${whispercpp_SOURCE_DIR}/ggml/include
)

# Define RAC_WHISPERCPP_BUILDING to export symbols with visibility("default")
target_compile_definitions(rac_backend_whispercpp PRIVATE RAC_WHISPERCPP_BUILDING)

target_link_libraries(rac_backend_whispercpp PUBLIC
    rac_commons
    whisper
    nlohmann_json::nlohmann_json
)



# =============================================================================
# Platform-specific configuration
# =============================================================================

if(RAC_PLATFORM_IOS)
    message(STATUS "Configuring WhisperCPP backend for iOS")
    target_link_libraries(rac_backend_whispercpp PUBLIC
        "-framework Foundation"
        "-framework Accelerate"
        "-framework Metal"
        "-framework MetalKit"
    )
    target_compile_definitions(rac_backend_whispercpp PRIVATE GGML_USE_METAL=1)

elseif(RAC_PLATFORM_ANDROID)
    message(STATUS "Configuring WhisperCPP backend for Android")
    target_link_libraries(rac_backend_whispercpp PRIVATE log)
    # Don't use -fvisibility=hidden here - JNI bridge needs these symbols
    target_compile_options(rac_backend_whispercpp PRIVATE -O3 -ffunction-sections -fdata-sections)
    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    target_link_options(rac_backend_whispercpp PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

elseif(RAC_PLATFORM_MACOS)
    message(STATUS "Configuring WhisperCPP backend for macOS")
    target_link_libraries(rac_backend_whispercpp PUBLIC
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
        message(STATUS "Building WhisperCPP JNI bridge for Android")

        add_library(rac_backend_whispercpp_jni SHARED
            jni/rac_backend_whispercpp_jni.cpp
        )

        target_include_directories(rac_backend_whispercpp_jni PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_SOURCE_DIR}/include
        )

        target_link_libraries(rac_backend_whispercpp_jni PRIVATE
            rac_backend_whispercpp
            log
        )

        target_compile_options(rac_backend_whispercpp_jni PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
        # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
        target_link_options(rac_backend_whispercpp_jni PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)
    endif()
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "WhisperCPP Backend Configuration:")
message(STATUS "  whisper.cpp version: ${WHISPER_CPP_VERSION}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
