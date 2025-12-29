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
    src/rac_backend_onnx_register.cpp
    # Generic service implementations that delegate to ONNX-specific functions
    src/rac_stt_service_impl.cpp
    src/rac_tts_service_impl.cpp
    src/rac_vad_service_impl.cpp
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
