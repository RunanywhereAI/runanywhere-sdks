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
option(RAC_BUILD_PLATFORM "Build Platform backend module (Apple Foundation Models, System TTS)" ON)

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

# Load versions from VERSIONS file (single source of truth)
include(LoadVersions)

# Make project version available to subdirectories (for backend CMakeLists.txt)
set(RAC_PROJECT_VERSION "${RAC_VERSION}" CACHE STRING "Project version for subdirectories" FORCE)

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
# FIND RUNANYWHERE-CORE (Pre-built or Source)
# =============================================================================

# Option to use pre-built core libraries instead of compiling from source
option(USE_PREBUILT_CORE "Use pre-built runanywhere-core libraries instead of compiling from source" OFF)

if(USE_PREBUILT_CORE)
    # Use pre-built core libraries (downloaded from remote releases)
    include(FindRunAnywhereCorePrebuilt)
    
    if(NOT RUNANYWHERE_CORE_PREBUILT_FOUND)
        message(FATAL_ERROR "Pre-built runanywhere-core not found. Run: ./scripts/download-core-prebuilt.sh")
    endif()
    
    message(STATUS "Using PRE-BUILT runanywhere-core libraries")
    message(STATUS "  Bridge: ${RUNANYWHERE_CORE_BRIDGE_LIB}")
    if(RUNANYWHERE_CORE_HAS_LLAMACPP)
        message(STATUS "  LlamaCPP: ${RUNANYWHERE_CORE_LLAMACPP_LIB}")
    endif()
    if(RUNANYWHERE_CORE_HAS_ONNX)
        message(STATUS "  ONNX: ${RUNANYWHERE_CORE_ONNX_LIB}")
    endif()
    
    # Set variables for compatibility with existing code
    set(RUNANYWHERE_CORE_INCLUDE_DIRS ${RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS})
    set(RUNANYWHERE_CORE_HAS_LLAMACPP ${RUNANYWHERE_CORE_HAS_LLAMACPP})
    set(RUNANYWHERE_CORE_HAS_ONNX ${RUNANYWHERE_CORE_HAS_ONNX})
else()
    # Use source code and compile locally (legacy mode)
    include(FindRunAnywhereCore)
    
    if(NOT RUNANYWHERE_CORE_FOUND)
        message(FATAL_ERROR "runanywhere-core not found at ${RUNANYWHERE_CORE_DIR}")
    endif()
    
    message(STATUS "Found runanywhere-core source at: ${RUNANYWHERE_CORE_DIR}")
    message(STATUS "Compiling runanywhere-core from source (legacy mode)")
    
    # Build runanywhere-core in modular mode
    set(RA_BUILD_MODULAR ON CACHE BOOL "" FORCE)
    set(RA_BUILD_LLAMACPP ${RAC_BUILD_LLAMACPP} CACHE BOOL "" FORCE)
    set(RA_BUILD_ONNX ${RAC_BUILD_ONNX} CACHE BOOL "" FORCE)
    set(RA_BUILD_WHISPERCPP ${RAC_BUILD_WHISPERCPP} CACHE BOOL "" FORCE)
    
    add_subdirectory(${RUNANYWHERE_CORE_DIR} ${CMAKE_BINARY_DIR}/runanywhere-core)
endif()

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
    src/core/rac_logger.cpp
    src/core/rac_audio_utils.cpp
    src/core/component_types.cpp
    src/core/events.cpp
    src/core/sdk_state.cpp
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
    src/infrastructure/model_management/model_strategy.cpp
    src/infrastructure/model_management/model_assignment.cpp
    src/infrastructure/storage/storage_analyzer.cpp
    # Network / Data layer (maps to Swift Data/)
    src/infrastructure/network/environment.cpp
    src/infrastructure/network/endpoints.cpp
    src/infrastructure/network/api_types.cpp
    src/infrastructure/network/http_client.cpp
    src/infrastructure/network/auth_manager.cpp
    src/infrastructure/network/development_config.cpp
    # Telemetry (maps to Swift Analytics/)
    src/infrastructure/telemetry/telemetry_types.cpp
    src/infrastructure/telemetry/telemetry_json.cpp
    src/infrastructure/telemetry/telemetry_manager.cpp
    # Device (device registration manager)
    src/infrastructure/device/rac_device_manager.cpp
)

# Feature sources (maps to Swift Features/)
set(RAC_FEATURES_SOURCES
    # LLM
    src/features/llm/llm_component.cpp
    src/features/llm/rac_llm_service.cpp
    src/features/llm/streaming_metrics.cpp
    src/features/llm/llm_analytics.cpp
    src/features/llm/structured_output.cpp
    # STT
    src/features/stt/stt_component.cpp
    src/features/stt/rac_stt_service.cpp
    src/features/stt/stt_analytics.cpp
    # TTS
    src/features/tts/tts_component.cpp
    src/features/tts/rac_tts_service.cpp
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

# Platform backend sources (Apple Foundation Models + System TTS)
# These are always included on Apple platforms since they're required for platform services
if(APPLE)
    set(RAC_PLATFORM_SOURCES
        backends/platform/src/rac_llm_platform.cpp
        backends/platform/src/rac_tts_platform.cpp
        backends/platform/src/rac_backend_platform_register.cpp
    )
else()
    set(RAC_PLATFORM_SOURCES "")
endif()

# Combine all sources
set(RAC_COMMONS_SOURCES
    ${RAC_CORE_SOURCES}
    ${RAC_INFRASTRUCTURE_SOURCES}
    ${RAC_FEATURES_SOURCES}
    ${RAC_PLATFORM_SOURCES}
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
)
# Core includes (pre-built or source)
if(USE_PREBUILT_CORE AND DEFINED RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS)
    target_include_directories(rac_commons PRIVATE
        ${RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS}
    )
elseif(NOT USE_PREBUILT_CORE AND DEFINED RUNANYWHERE_CORE_INCLUDE_DIRS)
    target_include_directories(rac_commons PRIVATE
        ${RUNANYWHERE_CORE_INCLUDE_DIRS}
    )
endif()

# Include runanywhere-core headers (for pre-built or source mode)
if(USE_PREBUILT_CORE AND DEFINED RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS)
    target_include_directories(rac_commons PUBLIC
        ${RUNANYWHERE_CORE_PREBUILT_INCLUDE_DIRS}
    )
elseif(NOT USE_PREBUILT_CORE AND DEFINED RUNANYWHERE_CORE_INCLUDE_DIRS)
    target_include_directories(rac_commons PUBLIC
        ${RUNANYWHERE_CORE_INCLUDE_DIRS}
    )
endif()

# Backend headers - needed for vtable dispatch in service files
# These headers define backend-specific functions called through vtables
if(RAC_BUILD_LLAMACPP)
    target_include_directories(rac_commons PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/backends/llamacpp/include>
    )
endif()
if(RAC_BUILD_ONNX)
    target_include_directories(rac_commons PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/backends/onnx/include>
    )
endif()
# Platform backend headers (always on Apple)
if(APPLE)
    target_include_directories(rac_commons PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/backends/platform/include>
    )
endif()

# Link against runanywhere-core bridge
# Use pre-built library if available, otherwise use compiled target
if(DEFINED RUNANYWHERE_CORE_BRIDGE_LIB)
    # Pre-built library mode (USE_PREBUILT_CORE=ON)
    target_link_libraries(rac_commons PUBLIC ${RUNANYWHERE_CORE_BRIDGE_LIB})
elseif(TARGET runanywhere_bridge)
    # Source compilation mode (legacy)
    target_link_libraries(rac_commons PUBLIC runanywhere_bridge)
else()
    message(FATAL_ERROR "runanywhere-core bridge library not found. Either set USE_PREBUILT_CORE=ON and run download-core-prebuilt.sh, or provide core source.")
endif()

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
#
# Backend libraries provide specific ML inference implementations:
# - llamacpp: LLM text generation (GGUF models via llama.cpp)
# - onnx: STT, TTS, VAD (ONNX Runtime models)
# - whispercpp: STT (Whisper.cpp models)
#
# Each backend:
# 1. Links against rac_commons for service registration
# 2. Links against runanywhere-core for low-level inference
# 3. Builds into a static library (.a) or xcframework
#

if(RAC_BUILD_LLAMACPP)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/backends/llamacpp/CMakeLists.txt")
        message(STATUS "Building LlamaCpp backend")
        add_subdirectory(backends/llamacpp)
    endif()
endif()

if(RAC_BUILD_ONNX)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/backends/onnx/CMakeLists.txt")
        message(STATUS "Building ONNX backend")
        add_subdirectory(backends/onnx)
    endif()
endif()

if(RAC_BUILD_WHISPERCPP)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/backends/whispercpp/CMakeLists.txt")
        message(STATUS "Building WhisperCpp backend")
        add_subdirectory(backends/whispercpp)
    endif()
endif()

if(RAC_BUILD_PLATFORM)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/backends/platform/CMakeLists.txt")
        message(STATUS "Building Platform backend (Apple Foundation Models, System TTS)")
        add_subdirectory(backends/platform)
    endif()
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
message(STATUS "  Platform:     ${RAC_BUILD_PLATFORM}")
message(STATUS "====================================")
message(STATUS "")
