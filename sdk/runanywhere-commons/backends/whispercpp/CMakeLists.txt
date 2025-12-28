# =============================================================================
# RABackendWhisperCPP - STT backend using whisper.cpp
# =============================================================================
#
# This module wraps runanywhere-core's WhisperCPP backend for use with
# the runanywhere-commons module/service registry system.
#
# Capabilities: STT
#

cmake_minimum_required(VERSION 3.16)
project(RABackendWhisperCPP VERSION 1.0.0 LANGUAGES CXX)

# =============================================================================
# OPTIONS
# =============================================================================

option(RAC_WHISPERCPP_BUILD_SHARED "Build as shared library" OFF)
option(RAC_WHISPERCPP_ENABLE_METAL "Enable Metal GPU support (Apple)" ON)
option(RAC_WHISPERCPP_ENABLE_COREML "Enable CoreML (Apple)" ON)

# =============================================================================
# SOURCES
# =============================================================================

set(WHISPERCPP_SOURCES
    src/rac_stt_whispercpp.cpp
    src/rac_backend_whispercpp_register.cpp
)

set(WHISPERCPP_HEADERS
    include/rac_stt_whispercpp.h
)

# =============================================================================
# LIBRARY TARGET
# =============================================================================

if(RAC_WHISPERCPP_BUILD_SHARED)
    add_library(rac_backend_whispercpp SHARED ${WHISPERCPP_SOURCES})
else()
    add_library(rac_backend_whispercpp STATIC ${WHISPERCPP_SOURCES})
endif()

# Public headers
target_include_directories(rac_backend_whispercpp
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# C++17 standard
target_compile_features(rac_backend_whispercpp PUBLIC cxx_std_17)

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Link against rac_commons (parent project provides this)
if(TARGET rac_commons)
    target_link_libraries(rac_backend_whispercpp PUBLIC rac_commons)
endif()

# Include runanywhere-commons public headers
target_include_directories(rac_backend_whispercpp PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

# Link against runanywhere-core's whispercpp backend
if(TARGET runanywhere_whispercpp)
    target_link_libraries(rac_backend_whispercpp PRIVATE runanywhere_whispercpp)
    # Include runanywhere-core headers for backend APIs
    target_include_directories(rac_backend_whispercpp PRIVATE
        ${RUNANYWHERE_CORE_DIR}/src
        ${RUNANYWHERE_CORE_DIR}/src/capabilities
        ${RUNANYWHERE_CORE_DIR}/src/backends/whispercpp
    )
elseif(DEFINED RUNANYWHERE_CORE_WHISPERCPP_LIB)
    target_link_libraries(rac_backend_whispercpp PRIVATE ${RUNANYWHERE_CORE_WHISPERCPP_LIB})
endif()

# =============================================================================
# PLATFORM-SPECIFIC
# =============================================================================

if(APPLE)
    # Metal framework for GPU acceleration
    if(RAC_WHISPERCPP_ENABLE_METAL)
        find_library(METAL_FRAMEWORK Metal)
        find_library(METALKIT_FRAMEWORK MetalKit)
        if(METAL_FRAMEWORK AND METALKIT_FRAMEWORK)
            target_link_libraries(rac_backend_whispercpp PRIVATE
                ${METAL_FRAMEWORK}
                ${METALKIT_FRAMEWORK}
            )
            target_compile_definitions(rac_backend_whispercpp PRIVATE GGML_USE_METAL=1)
        endif()
    endif()

    # CoreML for additional acceleration
    if(RAC_WHISPERCPP_ENABLE_COREML)
        find_library(COREML_FRAMEWORK CoreML)
        if(COREML_FRAMEWORK)
            target_link_libraries(rac_backend_whispercpp PRIVATE ${COREML_FRAMEWORK})
            target_compile_definitions(rac_backend_whispercpp PRIVATE WHISPER_USE_COREML=1)
        endif()
    endif()

    # Accelerate framework
    find_library(ACCELERATE_FRAMEWORK Accelerate)
    if(ACCELERATE_FRAMEWORK)
        target_link_libraries(rac_backend_whispercpp PRIVATE ${ACCELERATE_FRAMEWORK})
    endif()
endif()

# =============================================================================
# SYMBOL VISIBILITY
# =============================================================================

set_target_properties(rac_backend_whispercpp PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)

target_compile_definitions(rac_backend_whispercpp PRIVATE RAC_WHISPERCPP_BUILDING)

# =============================================================================
# INSTALLATION
# =============================================================================

install(TARGETS rac_backend_whispercpp
    EXPORT rac_backend_whispercppTargets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(FILES ${WHISPERCPP_HEADERS}
    DESTINATION include/rac
)
