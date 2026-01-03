# =============================================================================
# RABackendONNX - STT/TTS/VAD backend using ONNX Runtime
# =============================================================================
#
# This module wraps runanywhere-core's ONNX backend for use with
# the runanywhere-commons module/service registry system.
#
# Capabilities: STT, TTS, VAD
#

cmake_minimum_required(VERSION 3.16)

# Use version from parent project (loaded from VERSIONS file)
if(NOT DEFINED RAC_PROJECT_VERSION)
    set(RAC_PROJECT_VERSION "1.0.0")
endif()

project(RABackendONNX VERSION ${RAC_PROJECT_VERSION} LANGUAGES CXX)

# =============================================================================
# OPTIONS
# =============================================================================

option(RAC_ONNX_BUILD_SHARED "Build as shared library" OFF)
option(RAC_ONNX_ENABLE_COREML "Enable CoreML EP (Apple)" ON)

# =============================================================================
# SOURCES
# =============================================================================

set(ONNX_SOURCES
    src/rac_stt_onnx.cpp
    src/rac_tts_onnx.cpp
    src/rac_vad_onnx.cpp
    src/rac_vad_service_impl.cpp
    # Registration includes vtable implementations for STT and TTS
    src/rac_backend_onnx_register.cpp
)

set(ONNX_HEADERS
    include/rac_stt_onnx.h
    include/rac_tts_onnx.h
    include/rac_vad_onnx.h
)

# =============================================================================
# LIBRARY TARGET
# =============================================================================

if(RAC_ONNX_BUILD_SHARED)
    add_library(rac_backend_onnx SHARED ${ONNX_SOURCES})
else()
    add_library(rac_backend_onnx STATIC ${ONNX_SOURCES})
endif()

# Public headers
target_include_directories(rac_backend_onnx
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# C++17 standard
target_compile_features(rac_backend_onnx PUBLIC cxx_std_17)

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Link against rac_commons (parent project provides this)
if(TARGET rac_commons)
    target_link_libraries(rac_backend_onnx PUBLIC rac_commons)
endif()

# Include runanywhere-commons public headers
target_include_directories(rac_backend_onnx PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

# Link against runanywhere-core's onnx backend
# Note: runanywhere_onnx includes standalone ra_* functions (ra_create_backend, ra_stt_*, etc.)
# Do NOT link against runanywhere_bridge as it has conflicting symbols
if(TARGET runanywhere_onnx)
    target_link_libraries(rac_backend_onnx PRIVATE runanywhere_onnx)
    # Include runanywhere-core headers for backend APIs
    target_include_directories(rac_backend_onnx PRIVATE
        ${RUNANYWHERE_CORE_DIR}/src
        ${RUNANYWHERE_CORE_DIR}/src/capabilities
        ${RUNANYWHERE_CORE_DIR}/src/backends/onnx
    )
elseif(DEFINED RUNANYWHERE_CORE_ONNX_LIB)
    target_link_libraries(rac_backend_onnx PRIVATE ${RUNANYWHERE_CORE_ONNX_LIB})
endif()

# =============================================================================
# PLATFORM-SPECIFIC
# =============================================================================

if(APPLE)
    # CoreML for ONNX acceleration
    if(RAC_ONNX_ENABLE_COREML)
        find_library(COREML_FRAMEWORK CoreML)
        if(COREML_FRAMEWORK)
            target_link_libraries(rac_backend_onnx PRIVATE ${COREML_FRAMEWORK})
            target_compile_definitions(rac_backend_onnx PRIVATE USE_COREML=1)
        endif()
    endif()

    # Accelerate framework
    find_library(ACCELERATE_FRAMEWORK Accelerate)
    if(ACCELERATE_FRAMEWORK)
        target_link_libraries(rac_backend_onnx PRIVATE ${ACCELERATE_FRAMEWORK})
    endif()
endif()

# =============================================================================
# SYMBOL VISIBILITY
# =============================================================================

set_target_properties(rac_backend_onnx PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)

target_compile_definitions(rac_backend_onnx PRIVATE RAC_ONNX_BUILDING)

# =============================================================================
# JNI TARGET (Android/JVM)
# =============================================================================
#
# Matches iOS architecture where RABackendONNX.xcframework combines:
#   - librac_backend_onnx.a (this module)
#   - librunanywhere_onnx.a (from runanywhere-core)
#   - libsherpa-onnx.a (Sherpa-ONNX for STT/TTS/VAD)
#
# For Android, we statically link these into librac_backend_onnx_jni.so
# using --whole-archive to ensure all symbols are included.
#
# ONNX Runtime (libonnxruntime.so) remains a separate runtime dependency.

# Only build JNI if we have JNI and building for Android
if(RAC_BUILD_JNI AND ANDROID)
    # Find JNI
    find_package(JNI)

    if(JNI_FOUND)
        set(ONNX_JNI_SOURCES
            src/jni/rac_backend_onnx_jni.cpp
        )

        add_library(rac_backend_onnx_jni SHARED ${ONNX_JNI_SOURCES})

        target_include_directories(rac_backend_onnx_jni PRIVATE
            ${JNI_INCLUDE_DIRS}
            ${CMAKE_CURRENT_SOURCE_DIR}/include
            ${CMAKE_SOURCE_DIR}/include
            ${RUNANYWHERE_CORE_DIR}/src
            ${RUNANYWHERE_CORE_DIR}/src/capabilities
            ${RUNANYWHERE_CORE_DIR}/src/backends/onnx
        )

        # Use --whole-archive to statically link all symbols from static libraries
        # This matches iOS's libtool approach that combines all .a files
        if(TARGET runanywhere_onnx)
            # Get the static library file path
            target_link_libraries(rac_backend_onnx_jni PRIVATE
                -Wl,--whole-archive
                rac_backend_onnx
                runanywhere_onnx
                -Wl,--no-whole-archive
                rac_commons
                ${JNI_LIBRARIES}
            )
        else()
            target_link_libraries(rac_backend_onnx_jni PRIVATE
                -Wl,--whole-archive
                rac_backend_onnx
                -Wl,--no-whole-archive
                rac_commons
                ${JNI_LIBRARIES}
            )
        endif()

        # Link against ONNX Runtime and Sherpa-ONNX shared libraries
        # These are runtime dependencies (not statically linked)
        if(DEFINED ONNXRUNTIME_LIB)
            target_link_libraries(rac_backend_onnx_jni PRIVATE ${ONNXRUNTIME_LIB})
        endif()
        if(DEFINED SHERPA_ONNX_LIB)
            target_link_libraries(rac_backend_onnx_jni PRIVATE ${SHERPA_ONNX_LIB})
        endif()

        # Android-specific logging
        target_link_libraries(rac_backend_onnx_jni PRIVATE log)

        # Install JNI library
        install(TARGETS rac_backend_onnx_jni
            LIBRARY DESTINATION lib
            ARCHIVE DESTINATION lib
            RUNTIME DESTINATION bin
        )
    endif()
endif()

# =============================================================================
# INSTALLATION
# =============================================================================

install(TARGETS rac_backend_onnx
    EXPORT rac_backend_onnxTargets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(FILES ${ONNX_HEADERS}
    DESTINATION include/rac
)
