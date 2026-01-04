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

# NOTE: LlamaCpp, ONNX, and WhisperCpp backends have been moved to runanywhere-core.
# The SDKs consume RAC APIs directly from runanywhere-core's build artifacts.
# Platform services (Apple Foundation Models, System TTS) are built into rac_commons.
option(RAC_BUILD_JNI "Build JNI bridge for Android/JVM" OFF)

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
    # Use source code and compile locally
    include(FindRunAnywhereCore)

    if(NOT RUNANYWHERE_CORE_FOUND)
        message(FATAL_ERROR "runanywhere-core not found at ${RUNANYWHERE_CORE_DIR}")
    endif()

    message(STATUS "Found runanywhere-core source at: ${RUNANYWHERE_CORE_DIR}")
    message(STATUS "Compiling runanywhere-core from source")

    # Build runanywhere-core in modular mode with STATIC libraries
    # This matches iOS where we combine static .a files into xcframeworks
    set(RA_BUILD_MODULAR ON CACHE BOOL "" FORCE)
    set(RA_BUILD_SHARED OFF CACHE BOOL "" FORCE)  # Force static libs for static linking

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

# Platform services (Apple Foundation Models + System TTS)
# These are always included on Apple platforms since they're required for platform services
if(APPLE)
    set(RAC_PLATFORM_SOURCES
        src/features/platform/rac_llm_platform.cpp
        src/features/platform/rac_tts_platform.cpp
        src/features/platform/rac_backend_platform_register.cpp
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
# NOTE: LlamaCpp, ONNX, and WhisperCpp backend headers are now in runanywhere-core.
# Platform headers are now in include/rac/features/platform/ (included via main include dir)

# Link against runanywhere-core bridge
# Note: In source compilation mode, we do NOT link rac_commons against runanywhere_bridge directly.
# The backends (llamacpp, onnx, etc.) link against their respective core libraries.
# This avoids duplicate symbol issues when both bridge and backend libs have
# implementations of the same functions (ra_stt_*, ra_tts_*, ra_vad_*).
if(DEFINED RUNANYWHERE_CORE_BRIDGE_LIB)
    # Pre-built library mode (USE_PREBUILT_CORE=ON) - link the pre-built bridge
    target_link_libraries(rac_commons PUBLIC ${RUNANYWHERE_CORE_BRIDGE_LIB})
else()
    # Source compilation mode - backends link against their specific runanywhere-core backend libraries
    # (runanywhere_llamacpp, runanywhere_onnx, etc.) via their own CMakeLists.txt
    # Do NOT link against runanywhere_bridge here to avoid duplicate symbols
    message(STATUS "Source mode: rac_commons will NOT link runanywhere_bridge (backends handle their own linking)")
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
# JNI BRIDGE (Android/JVM)
# =============================================================================

if(RAC_BUILD_JNI)
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/jni/CMakeLists.txt")
        message(STATUS "Building JNI bridge for Android/JVM")
        add_subdirectory(src/jni)
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
if(APPLE)
    message(STATUS "Platform services: Apple Foundation Models, System TTS (built into rac_commons)")
endif()
message(STATUS "NOTE: LlamaCpp, ONNX, WhisperCpp backends moved to runanywhere-core")
message(STATUS "")
message(STATUS "JNI bridge:     ${RAC_BUILD_JNI}")
message(STATUS "====================================")
message(STATUS "")
