# CMakeLists.txt for RunAnywhere Commons JNI Bridge
#
# This builds the CORE commons JNI layer that wraps the runanywhere-commons C API
# for Android/JVM platforms.
#
# The commons JNI library includes:
# - Core commons bindings (rac_init, rac_shutdown, etc.)
# - LLM/STT/TTS/VAD/VLM component bindings
# - Model registry bindings
# - Platform adapter callbacks
#
# NOTE: Backend registration is handled by SEPARATE JNI libraries:
#   - backends/llamacpp/src/jni/ -> librac_backend_llamacpp_jni.so
#   - backends/onnx/src/jni/     -> librac_backend_onnx_jni.so
#
# This mirrors the Swift SDK architecture where each backend has its own
# XCFramework (RABackendLlamaCPP, RABackendONNX).

cmake_minimum_required(VERSION 3.14)
project(runanywhere_commons_jni)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)

# needed for string parsing
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

# Find JNI
# When cross-compiling for Android, we should use the NDK's JNI headers (jni.h)
# and NOT the host JDK's JVM/AWT libraries.
if(ANDROID)
    # NDK sysroot contains jni.h and android/jni_md.h
    # Detect NDK host tag dynamically instead of hardcoding
    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
        set(_NDK_HOST_TAG "darwin-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
        set(_NDK_HOST_TAG "linux-x86_64")
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
        set(_NDK_HOST_TAG "windows-x86_64")
    else()
        message(FATAL_ERROR "Unsupported host platform: ${CMAKE_HOST_SYSTEM_NAME}")
    endif()
    set(_NDK_PREBUILT "${CMAKE_ANDROID_NDK}/toolchains/llvm/prebuilt/${_NDK_HOST_TAG}")
    set(_NDK_SYSROOT_INCLUDE "${_NDK_PREBUILT}/sysroot/usr/include")

    if(NOT EXISTS "${_NDK_SYSROOT_INCLUDE}/jni.h")
        message(FATAL_ERROR "Could not locate NDK JNI headers at: ${_NDK_SYSROOT_INCLUDE}. Is CMAKE_ANDROID_NDK set correctly?")
    endif()

    set(JNI_INCLUDE_DIRS
        "${_NDK_SYSROOT_INCLUDE}"
        "${_NDK_SYSROOT_INCLUDE}/android"
    )
    set(JNI_LIBRARIES "")
else()
    find_package(JNI REQUIRED)
endif()

include_directories(${JNI_INCLUDE_DIRS})

# Include runanywhere-commons headers
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../../include)

# Source files
set(JNI_SOURCES
    runanywhere_commons_jni.cpp
)

# Create shared library
add_library(runanywhere_commons_jni SHARED ${JNI_SOURCES})

# Link against runanywhere-commons core ONLY
# Backend libraries are NOT linked here - they have their own JNI libraries
target_link_libraries(runanywhere_commons_jni
    rac_commons
    nlohmann_json::nlohmann_json
    ${JNI_LIBRARIES}
)

# Android-specific settings
if(ANDROID)
    find_library(log-lib log)
    target_link_libraries(runanywhere_commons_jni ${log-lib})

    # Symbol visibility
    set_target_properties(runanywhere_commons_jni PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN YES
    )

    # 16KB page alignment for Android 15+ (API 35) compliance - required Nov 2025
    target_link_options(runanywhere_commons_jni PRIVATE -Wl,-z,max-page-size=16384)
endif()

# Set output name to match what Kotlin expects
set_target_properties(runanywhere_commons_jni PROPERTIES
    OUTPUT_NAME "runanywhere_jni"
    VERSION 1.0.0
    SOVERSION 1
)

# Installation
install(TARGETS runanywhere_commons_jni
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)
