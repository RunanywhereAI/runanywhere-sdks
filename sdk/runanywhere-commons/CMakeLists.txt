cmake_minimum_required(VERSION 3.22)

# Read version from VERSION file
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" VERSION_CONTENT)
string(STRIP "${VERSION_CONTENT}" RAC_VERSION)

project(RunAnywhereCommons
    VERSION ${RAC_VERSION}
    LANGUAGES CXX C
    DESCRIPTION "RunAnywhere Commons - Modular C++ layer for capability-based ML inference"
)

# =============================================================================
# OPTIONS
# =============================================================================

# Backend build options
option(RAC_BUILD_LLAMACPP "Build LlamaCpp backend module" ON)
option(RAC_BUILD_ONNX "Build ONNX backend module (STT, TTS, VAD)" ON)
option(RAC_BUILD_WHISPERCPP "Build WhisperCpp backend module (STT)" OFF)

# Feature options
option(RAC_BUILD_TESTS "Build unit tests" OFF)
option(RAC_BUILD_SHARED "Build shared libraries" OFF)

# Path to runanywhere-core (can be overridden)
set(RUNANYWHERE_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../runanywhere-core" CACHE PATH "Path to runanywhere-core")

# =============================================================================
# C++ CONFIGURATION
# =============================================================================

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Export compile commands for clang-tidy
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Add cmake modules path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

if(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(RAC_PLATFORM_IOS TRUE)
    set(RAC_PLATFORM_NAME "iOS")
elseif(ANDROID)
    set(RAC_PLATFORM_ANDROID TRUE)
    set(RAC_PLATFORM_NAME "Android")
elseif(APPLE)
    set(RAC_PLATFORM_MACOS TRUE)
    set(RAC_PLATFORM_NAME "macOS")
elseif(UNIX)
    set(RAC_PLATFORM_LINUX TRUE)
    set(RAC_PLATFORM_NAME "Linux")
else()
    set(RAC_PLATFORM_NAME "Unknown")
endif()

message(STATUS "Platform: ${RAC_PLATFORM_NAME}")

# =============================================================================
# COMPILER FLAGS
# =============================================================================

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-parameter)
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        add_compile_options(-O3 -DNDEBUG)
        # Hidden visibility by default for size optimization
        add_compile_options(-fvisibility=hidden)
        add_compile_options(-ffunction-sections -fdata-sections)
    endif()
endif()

# =============================================================================
# FIND RUNANYWHERE-CORE
# =============================================================================

include(FindRunAnywhereCore)

if(NOT RUNANYWHERE_CORE_FOUND)
    message(FATAL_ERROR "runanywhere-core not found at ${RUNANYWHERE_CORE_DIR}")
endif()

message(STATUS "Found runanywhere-core at: ${RUNANYWHERE_CORE_DIR}")

# Build runanywhere-core in modular mode
set(RA_BUILD_MODULAR ON CACHE BOOL "" FORCE)
set(RA_BUILD_LLAMACPP ${RAC_BUILD_LLAMACPP} CACHE BOOL "" FORCE)
set(RA_BUILD_ONNX ${RAC_BUILD_ONNX} CACHE BOOL "" FORCE)
set(RA_BUILD_WHISPERCPP ${RAC_BUILD_WHISPERCPP} CACHE BOOL "" FORCE)

add_subdirectory(${RUNANYWHERE_CORE_DIR} ${CMAKE_BINARY_DIR}/runanywhere-core)

# =============================================================================
# RAC COMMONS CORE LIBRARY
# =============================================================================

# =============================================================================
# SOURCE FILES (Organized by Swift SDK structure)
# =============================================================================

# Core sources (maps to Swift Core/)
set(RAC_CORE_SOURCES
    src/core/rac_core.cpp
    src/core/rac_error.cpp
    src/core/rac_time.cpp
    src/core/rac_memory.cpp
    src/core/component_types.cpp
    src/core/capabilities/lifecycle_manager.cpp
)

# Infrastructure sources (maps to Swift Infrastructure/)
set(RAC_INFRASTRUCTURE_SOURCES
    src/infrastructure/events/event_publisher.cpp
    src/infrastructure/registry/module_registry.cpp
    src/infrastructure/registry/service_registry.cpp
    src/infrastructure/download/download_manager.cpp
    src/infrastructure/model_management/model_registry.cpp
    src/infrastructure/model_management/model_types.cpp
    src/infrastructure/model_management/model_paths.cpp
)

# Feature sources (maps to Swift Features/)
set(RAC_FEATURES_SOURCES
    # LLM
    src/features/llm/llm_component.cpp
    src/features/llm/streaming_metrics.cpp
    src/features/llm/llm_analytics.cpp
    # STT
    src/features/stt/stt_component.cpp
    src/features/stt/stt_analytics.cpp
    # TTS
    src/features/tts/tts_component.cpp
    src/features/tts/tts_analytics.cpp
    # VAD
    src/features/vad/vad_component.cpp
    src/features/vad/energy_vad.cpp
    src/features/vad/vad_analytics.cpp
    # Voice Agent
    src/features/voice_agent/voice_agent.cpp
    # Result memory management (weak symbols, can be overridden by backends)
    src/features/result_free.cpp
)

# Combine all sources
set(RAC_COMMONS_SOURCES
    ${RAC_CORE_SOURCES}
    ${RAC_INFRASTRUCTURE_SOURCES}
    ${RAC_FEATURES_SOURCES}
)

if(RAC_BUILD_SHARED)
    add_library(rac_commons SHARED ${RAC_COMMONS_SOURCES})
else()
    add_library(rac_commons STATIC ${RAC_COMMONS_SOURCES})
endif()

# Public headers (available to consumers)
# Headers are now under include/rac/{core,features,infrastructure}/
target_include_directories(rac_commons PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Private includes for implementation
target_include_directories(rac_commons PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${RUNANYWHERE_CORE_DIR}/src
    ${RUNANYWHERE_CORE_DIR}/src/capabilities
)

target_link_libraries(rac_commons PUBLIC
    runanywhere_bridge
)

# Symbol visibility for shared builds
if(RAC_BUILD_SHARED)
    target_compile_definitions(rac_commons PRIVATE RAC_BUILDING_SHARED=1)
    set_target_properties(rac_commons PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON
    )
endif()

# =============================================================================
# BACKEND MODULES
# =============================================================================

if(RAC_BUILD_LLAMACPP)
    message(STATUS "Building LlamaCpp backend module")
    add_subdirectory(backends/llamacpp)
endif()

if(RAC_BUILD_ONNX)
    message(STATUS "Building ONNX backend module")
    add_subdirectory(backends/onnx)
endif()

if(RAC_BUILD_WHISPERCPP)
    message(STATUS "Building WhisperCpp backend module")
    add_subdirectory(backends/whispercpp)
endif()

# =============================================================================
# TESTS
# =============================================================================

if(RAC_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# =============================================================================
# INSTALLATION
# =============================================================================

install(TARGETS rac_commons
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)

install(DIRECTORY include/
    DESTINATION include
    FILES_MATCHING PATTERN "*.h"
)

# =============================================================================
# CONFIGURATION SUMMARY
# =============================================================================

message(STATUS "")
message(STATUS "====================================")
message(STATUS "RunAnywhere Commons v${RAC_VERSION}")
message(STATUS "====================================")
message(STATUS "Platform:       ${RAC_PLATFORM_NAME}")
message(STATUS "Build type:     ${CMAKE_BUILD_TYPE}")
message(STATUS "Compiler:       ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "Shared libs:    ${RAC_BUILD_SHARED}")
message(STATUS "")
message(STATUS "Backend modules:")
message(STATUS "  LlamaCpp:     ${RAC_BUILD_LLAMACPP}")
message(STATUS "  ONNX:         ${RAC_BUILD_ONNX}")
message(STATUS "  WhisperCpp:   ${RAC_BUILD_WHISPERCPP}")
message(STATUS "====================================")
message(STATUS "")
