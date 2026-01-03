# CMakeLists.txt for RunAnywhere Commons JNI Bridge
#
# This builds the CORE commons JNI layer that wraps the runanywhere-commons C API
# for Android/JVM platforms.
#
# The commons JNI library includes:
# - Core commons bindings (rac_init, rac_shutdown, etc.)
# - LLM/STT/TTS/VAD component bindings
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

# Find JNI
find_package(JNI REQUIRED)
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
