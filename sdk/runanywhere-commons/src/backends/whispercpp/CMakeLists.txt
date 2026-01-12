# =============================================================================
# WhisperCPP Backend - Speech-to-Text via whisper.cpp
# =============================================================================

message(STATUS "Configuring WhisperCPP backend...")

# =============================================================================
# Fetch whisper.cpp
# =============================================================================

include(FetchContent)
include(LoadVersions)

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
    ${whispercpp_SOURCE_DIR}/include
    ${whispercpp_SOURCE_DIR}/ggml/include
)

target_link_libraries(rac_backend_whispercpp PUBLIC
    rac_commons
    whisper
)

target_compile_features(rac_backend_whispercpp PUBLIC cxx_std_17)

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
    target_compile_options(rac_backend_whispercpp PRIVATE -O3 -fvisibility=hidden -ffunction-sections -fdata-sections)
    target_link_options(rac_backend_whispercpp PRIVATE -Wl,--gc-sections)

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
        target_link_options(rac_backend_whispercpp_jni PRIVATE -Wl,--gc-sections)
    endif()
endif()

# =============================================================================
# Summary
# =============================================================================

message(STATUS "WhisperCPP Backend Configuration:")
message(STATUS "  whisper.cpp version: ${WHISPER_CPP_VERSION}")
message(STATUS "  Platform: ${RAC_PLATFORM_NAME}")
