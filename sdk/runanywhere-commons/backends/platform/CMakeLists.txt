# =============================================================================
# RABackendPlatform - Platform-native services (Apple Foundation Models, System TTS)
# =============================================================================
#
# This module provides platform-native AI services that delegate to Swift/ObjC:
# - Apple Foundation Models (iOS 26+ / macOS 26+) for LLM
# - AVSpeechSynthesizer for TTS
#
# The C++ layer handles registration and service routing, while Swift provides
# the actual implementation via callbacks.
#
# Capabilities: TEXT_GENERATION (LLM), TTS
#

cmake_minimum_required(VERSION 3.16)

# Use version from parent project (loaded from VERSIONS file)
if(NOT DEFINED RAC_PROJECT_VERSION)
    set(RAC_PROJECT_VERSION "1.0.0")
endif()

project(RABackendPlatform VERSION ${RAC_PROJECT_VERSION} LANGUAGES CXX)

# =============================================================================
# OPTIONS
# =============================================================================

option(RAC_PLATFORM_BUILD_SHARED "Build as shared library" OFF)

# =============================================================================
# SOURCES
# =============================================================================

set(PLATFORM_SOURCES
    src/rac_llm_platform.cpp
    src/rac_tts_platform.cpp
    src/rac_backend_platform_register.cpp
)

set(PLATFORM_HEADERS
    include/rac_llm_platform.h
    include/rac_tts_platform.h
)

# =============================================================================
# LIBRARY TARGET
# =============================================================================

if(RAC_PLATFORM_BUILD_SHARED)
    add_library(rac_backend_platform SHARED ${PLATFORM_SOURCES})
else()
    add_library(rac_backend_platform STATIC ${PLATFORM_SOURCES})
endif()

# Public headers
target_include_directories(rac_backend_platform
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# C++17 standard
target_compile_features(rac_backend_platform PUBLIC cxx_std_17)

# =============================================================================
# DEPENDENCIES
# =============================================================================

# Link against rac_commons (parent project provides this)
if(TARGET rac_commons)
    target_link_libraries(rac_backend_platform PUBLIC rac_commons)
endif()

# Include runanywhere-commons public headers
target_include_directories(rac_backend_platform PUBLIC
    ${CMAKE_SOURCE_DIR}/include
)

# =============================================================================
# PLATFORM-SPECIFIC
# =============================================================================

if(APPLE)
    # Foundation framework for basic types
    find_library(FOUNDATION_FRAMEWORK Foundation)
    if(FOUNDATION_FRAMEWORK)
        target_link_libraries(rac_backend_platform PRIVATE ${FOUNDATION_FRAMEWORK})
    endif()
endif()

# =============================================================================
# SYMBOL VISIBILITY
# =============================================================================

set_target_properties(rac_backend_platform PROPERTIES
    C_VISIBILITY_PRESET hidden
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN YES
)

target_compile_definitions(rac_backend_platform PRIVATE RAC_PLATFORM_BUILDING)

# =============================================================================
# INSTALLATION
# =============================================================================

install(TARGETS rac_backend_platform
    EXPORT rac_backend_platformTargets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)

install(FILES ${PLATFORM_HEADERS}
    DESTINATION include/rac
)
