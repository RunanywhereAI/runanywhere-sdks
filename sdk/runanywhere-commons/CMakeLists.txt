cmake_minimum_required(VERSION 3.22)

# Read version from VERSION file
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" VERSION_CONTENT)
string(STRIP "${VERSION_CONTENT}" RAC_VERSION)

project(RunAnywhereCommons
    VERSION ${RAC_VERSION}
    LANGUAGES CXX C
    DESCRIPTION "RunAnywhere Commons - Standalone infrastructure library for ML inference SDKs"
)

# =============================================================================
# ABOUT THIS LIBRARY
# =============================================================================
#
# rac_commons is a STANDALONE library that provides:
#   - Logging, error handling, and event tracking
#   - Service registry and provider infrastructure
#   - Model management (download strategies, storage)
#   - Platform backend (Apple Foundation Models, System TTS) on Apple platforms
# =============================================================================

# =============================================================================
# OPTIONS
# =============================================================================

option(RAC_BUILD_JNI "Build JNI bridge for Android/JVM" OFF)
option(RAC_BUILD_TESTS "Build unit tests" OFF)
option(RAC_BUILD_SHARED "Build shared libraries" OFF)
option(RAC_BUILD_PLATFORM "Build platform backend (Apple Foundation Models, System TTS)" ON)
option(RAC_BUILD_BACKENDS "Build ML backends (LlamaCPP, ONNX, WhisperCPP, RAG)" OFF)
option(RAC_BACKEND_LLAMACPP "Build LlamaCPP backend" ON)
option(RAC_BACKEND_ONNX "Build ONNX backend" ON)
option(RAC_BACKEND_RAG "Build RAG backend (USearch)" ON)
# WhisperCPP OFF by default - Sherpa-ONNX (NeMo CTC / Parakeet) is now the primary STT backend
option(RAC_BACKEND_WHISPERCPP "Build WhisperCPP backend" OFF)
if(APPLE)
    option(RAC_BACKEND_WHISPERKIT_COREML "Build WhisperKit CoreML backend (Apple Neural Engine STT)" ON)
else()
    set(RAC_BACKEND_WHISPERKIT_COREML OFF CACHE BOOL "" FORCE)
endif()
option(RAC_BUILD_SERVER "Build OpenAI-compatible HTTP server (runanywhere-server)" OFF)

# =============================================================================
# C++ CONFIGURATION
# =============================================================================

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Workaround for React Native 0.83 std::format incompatibility on Android NDK 26
# Add a define to suppress the issue in React Native's graphicsConversions.h
if(ANDROID)
    add_compile_definitions(YG_ENABLE_STANDARD_LIBRARY_SUPPORT=0)
    # Suppress std::format usage by adding this flag
    add_compile_options(-fno-strict-aliasing)
endif()

# Export compile commands for clang-tidy
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Add cmake modules path
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Load versions from VERSIONS file (single source of truth)
include(LoadVersions)

# Make project version available to subdirectories
set(RAC_PROJECT_VERSION "${RAC_VERSION}" CACHE STRING "Project version" FORCE)

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

if(EMSCRIPTEN)
    set(RAC_PLATFORM_WASM TRUE)
    set(RAC_PLATFORM_NAME "Emscripten")
elseif(IOS OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
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
# SHARED DEPENDENCIES (FetchContent)
# =============================================================================

include(FetchContent)

# nlohmann/json - header-only JSON library (used by JNI, backends, server)
if(NOT DEFINED NLOHMANN_JSON_VERSION)
    set(NLOHMANN_JSON_VERSION "3.11.3")
endif()
FetchContent_Declare(
    nlohmann_json
    GIT_REPOSITORY https://github.com/nlohmann/json.git
    GIT_TAG v${NLOHMANN_JSON_VERSION}
    GIT_SHALLOW TRUE
)
set(JSON_BuildTests OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(nlohmann_json)

# Make nlohmann_json headers available project-wide for IDE indexing
# (nlohmann_json_SOURCE_DIR is set by FetchContent_MakeAvailable)
include_directories(SYSTEM ${nlohmann_json_SOURCE_DIR}/include)

# =============================================================================
# SERVER DEPENDENCIES (FetchContent)
# =============================================================================

if(RAC_BUILD_SERVER)
    # cpp-httplib - header-only HTTP library (same as llama.cpp uses)
    FetchContent_Declare(
        cpp-httplib
        GIT_REPOSITORY https://github.com/yhirose/cpp-httplib.git
        GIT_TAG v0.15.3
        GIT_SHALLOW TRUE
    )

    message(STATUS "Fetching server dependencies (cpp-httplib)...")
    FetchContent_MakeAvailable(cpp-httplib)
    message(STATUS "Server dependencies ready")
endif()

# =============================================================================
# COMPILER FLAGS
# =============================================================================

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    add_compile_options(-Wall -Wextra -Wpedantic -Wno-unused-parameter)
    if(CMAKE_BUILD_TYPE STREQUAL "Release")
        add_compile_options(-O3 -DNDEBUG)
        add_compile_options(-fvisibility=hidden)
        add_compile_options(-ffunction-sections -fdata-sections)
    endif()
endif()

# =============================================================================
# 16KB Page Alignment for Android 15+ (API 35) Compliance
# Required starting November 1, 2025 for Google Play submissions
# All shared libraries must have PT_LOAD segments aligned to 16KB
# =============================================================================
if(ANDROID)
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
    message(STATUS "Enabled 16KB page alignment for Android (Google Play requirement)")
endif()

# =============================================================================
# AUTO-GENERATE DEVELOPMENT CONFIG IF MISSING
# =============================================================================
# development_config.cpp is git-ignored because it can contain secrets.
# For CI builds or fresh checkouts, we auto-generate a stub from the template.

set(DEV_CONFIG_FILE "${CMAKE_CURRENT_SOURCE_DIR}/src/infrastructure/network/development_config.cpp")
set(DEV_CONFIG_TEMPLATE "${CMAKE_CURRENT_SOURCE_DIR}/src/infrastructure/network/development_config.cpp.template")

if(NOT EXISTS "${DEV_CONFIG_FILE}")
    if(EXISTS "${DEV_CONFIG_TEMPLATE}")
        message(STATUS "development_config.cpp not found, generating stub from template...")
        file(READ "${DEV_CONFIG_TEMPLATE}" DEV_CONFIG_CONTENT)
        file(WRITE "${DEV_CONFIG_FILE}" "${DEV_CONFIG_CONTENT}")
        message(STATUS "Generated: ${DEV_CONFIG_FILE}")
    else()
        message(FATAL_ERROR "Neither development_config.cpp nor .template found!")
    endif()
endif()

# =============================================================================
# SOURCE FILES
# =============================================================================

# Core sources - logging, errors, time, memory, events
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
    src/core/rac_structured_error.cpp
    src/core/capabilities/lifecycle_manager.cpp
    src/core/rac_error_model.cpp
)

# Infrastructure sources - registry, model management, network, telemetry
set(RAC_INFRASTRUCTURE_SOURCES
    src/infrastructure/events/event_publisher.cpp
    src/infrastructure/registry/module_registry.cpp
    src/infrastructure/registry/service_registry.cpp
    src/infrastructure/download/download_manager.cpp
    src/infrastructure/model_management/model_registry.cpp
    src/infrastructure/model_management/lora_registry.cpp
    src/infrastructure/model_management/model_types.cpp
    src/infrastructure/model_management/model_paths.cpp
    src/infrastructure/model_management/model_strategy.cpp
    src/infrastructure/model_management/model_assignment.cpp
    src/infrastructure/model_management/model_compatibility.cpp
    src/infrastructure/storage/storage_analyzer.cpp
    src/infrastructure/network/environment.cpp
    src/infrastructure/network/endpoints.cpp
    src/infrastructure/network/api_types.cpp
    src/infrastructure/network/http_client.cpp
    src/infrastructure/network/auth_manager.cpp
    src/infrastructure/network/development_config.cpp
    src/infrastructure/telemetry/telemetry_types.cpp
    src/infrastructure/telemetry/telemetry_json.cpp
    src/infrastructure/telemetry/telemetry_manager.cpp
    src/infrastructure/device/rac_device_manager.cpp
)

# Feature sources - LLM, STT, TTS, VAD, Wake Word, VLM, Diffusion (iOS/Apple only)
set(RAC_FEATURES_SOURCES
    # LLM
    src/features/llm/llm_component.cpp
    src/features/llm/rac_llm_service.cpp
    src/features/llm/streaming_metrics.cpp
    src/features/llm/llm_analytics.cpp
    src/features/llm/structured_output.cpp
    src/features/llm/tool_calling.cpp
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
    # Wake Word
    src/features/wakeword/wakeword_service.cpp
    # VLM (Vision Language Model)
    src/features/vlm/vlm_component.cpp
    src/features/vlm/rac_vlm_service.cpp
    # Diffusion
    src/features/diffusion/diffusion_component.cpp
    src/features/diffusion/rac_diffusion_service.cpp
    src/features/diffusion/diffusion_model_registry.cpp
    src/features/diffusion/diffusion_json.cpp
    src/features/diffusion/rac_diffusion_tokenizer.cpp
    # Embeddings
    src/features/embeddings/rac_embeddings_service.cpp
    src/features/embeddings/embeddings_component.cpp
    # Voice Agent
    src/features/voice_agent/voice_agent.cpp
    # Result memory management
    src/features/result_free.cpp
)

# Platform services (Apple Foundation Models + System TTS + CoreML Diffusion)
if(APPLE AND RAC_BUILD_PLATFORM)
    set(RAC_PLATFORM_SOURCES
        src/features/platform/rac_llm_platform.cpp
        src/features/platform/rac_tts_platform.cpp
        src/features/platform/rac_diffusion_platform.cpp
        src/features/platform/rac_backend_platform_register.cpp
    )
    message(STATUS "Building platform services: Apple Foundation Models, System TTS, CoreML Diffusion")
else()
    set(RAC_PLATFORM_SOURCES "")
endif()

# WhisperKit CoreML backend (Apple-only, no external deps → compiled into rac_commons)
if(APPLE AND RAC_BACKEND_WHISPERKIT_COREML)
    set(RAC_WHISPERKIT_COREML_SOURCES
        src/backends/whisperkit_coreml/rac_stt_whisperkit_coreml.cpp
        src/backends/whisperkit_coreml/rac_backend_whisperkit_coreml_register.cpp
    )
    message(STATUS "Building WhisperKit CoreML backend (compiled into rac_commons)")
else()
    set(RAC_WHISPERKIT_COREML_SOURCES "")
endif()

# Combine all sources
set(RAC_COMMONS_SOURCES
    ${RAC_CORE_SOURCES}
    ${RAC_INFRASTRUCTURE_SOURCES}
    ${RAC_FEATURES_SOURCES}
    ${RAC_PLATFORM_SOURCES}
    ${RAC_WHISPERKIT_COREML_SOURCES}
)

# =============================================================================
# RAC COMMONS LIBRARY
# =============================================================================

if(RAC_BUILD_SHARED)
    add_library(rac_commons SHARED ${RAC_COMMONS_SOURCES})
else()
    add_library(rac_commons STATIC ${RAC_COMMONS_SOURCES})
endif()

# Public headers
target_include_directories(rac_commons PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
)

# Private includes for implementation
target_include_directories(rac_commons PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
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

# Platform-specific linking
if(APPLE)
    target_link_libraries(rac_commons PUBLIC
        "-framework Foundation"
    )
    if(RAC_BUILD_PLATFORM)
        target_link_libraries(rac_commons PUBLIC
            "-framework AVFoundation"
        )
    endif()
endif()

if(RAC_PLATFORM_ANDROID)
    target_compile_definitions(rac_commons PRIVATE RAC_PLATFORM_ANDROID=1)
    target_link_libraries(rac_commons PUBLIC log)
endif()

set_target_properties(rac_commons PROPERTIES
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
    CXX_EXTENSIONS OFF
)

# =============================================================================
# JNI BRIDGE (Android/JVM)
# =============================================================================

if(RAC_BUILD_JNI)
    # Make JNI headers available project-wide so CLion can resolve jni.h
    # in ALL source files (including backend JNI files not in the current build)
    if(NOT ANDROID)
        # Auto-detect JAVA_HOME if not set or invalid
        if(NOT DEFINED ENV{JAVA_HOME} OR "$ENV{JAVA_HOME}" STREQUAL ""
           OR NOT EXISTS "$ENV{JAVA_HOME}/include/jni.h")
            find_program(_JAVA_EXEC java)
            if(_JAVA_EXEC)
                get_filename_component(_JAVA_EXEC_REAL "${_JAVA_EXEC}" REALPATH)
                get_filename_component(_JAVA_BIN_DIR "${_JAVA_EXEC_REAL}" DIRECTORY)
                get_filename_component(_JAVA_HOME_DETECTED "${_JAVA_BIN_DIR}" DIRECTORY)
                set(ENV{JAVA_HOME} "${_JAVA_HOME_DETECTED}")
                message(STATUS "Auto-detected JAVA_HOME: ${_JAVA_HOME_DETECTED}")
            endif()
        endif()
        find_package(JNI QUIET)
        if(JNI_FOUND)
            # Project-wide include so IDE resolves jni.h in all files
            include_directories(SYSTEM ${JNI_INCLUDE_DIRS})
            message(STATUS "JNI include dirs: ${JNI_INCLUDE_DIRS}")
        else()
            message(WARNING "JNI not found. Set JAVA_HOME for IDE indexing.")
        endif()
    endif()

    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/jni/CMakeLists.txt")
        message(STATUS "Building JNI bridge for Android/JVM")
        add_subdirectory(src/jni)
    endif()
endif()

# =============================================================================
# BACKENDS (LlamaCPP, ONNX, WhisperCPP)
# =============================================================================

if(RAC_BUILD_BACKENDS)
    message(STATUS "Building ML backends...")

    if(RAC_BACKEND_LLAMACPP AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/backends/llamacpp/CMakeLists.txt")
        message(STATUS "  - LlamaCPP backend")
        add_subdirectory(src/backends/llamacpp)
    endif()

    if(RAC_BACKEND_ONNX AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/backends/onnx/CMakeLists.txt")
        message(STATUS "  - ONNX backend")
        add_subdirectory(src/backends/onnx)
    endif()

    if(RAC_BACKEND_WHISPERCPP AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/backends/whispercpp/CMakeLists.txt")
        message(STATUS "  - WhisperCPP backend")
        add_subdirectory(src/backends/whispercpp)
    endif()

    if(RAC_BACKEND_RAG AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/backends/rag/CMakeLists.txt")
        message(STATUS "  - RAG backend (USearch)")
        add_subdirectory(src/backends/rag)
    endif()
endif()

# =============================================================================
# SERVER (OpenAI-compatible HTTP Server)
# =============================================================================

if(RAC_BUILD_SERVER)
    message(STATUS "Building OpenAI-compatible HTTP server...")
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/server/CMakeLists.txt")
        add_subdirectory(src/server)
    else()
        message(WARNING "Server source directory not found: src/server/")
    endif()

    # Also build the standalone server binary
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/CMakeLists.txt")
        add_subdirectory(tools)
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
message(STATUS "Components:")
message(STATUS "  Core:         Logging, errors, events, memory")
message(STATUS "  Registry:     Service & module registration")
message(STATUS "  Models:       Download strategies, storage")
message(STATUS "  Services:     LLM, STT, TTS, VAD interfaces")
if(APPLE AND RAC_BUILD_PLATFORM)
    message(STATUS "  Platform:     Apple Foundation Models, System TTS")
endif()
if(RAC_BUILD_BACKENDS)
    message(STATUS "  Backends:     LlamaCPP=${RAC_BACKEND_LLAMACPP}, ONNX=${RAC_BACKEND_ONNX}, WhisperCPP=${RAC_BACKEND_WHISPERCPP}, WhisperKitCoreML=${RAC_BACKEND_WHISPERKIT_COREML}, RAG=${RAC_BACKEND_RAG}")
endif()
if(RAC_BUILD_SERVER)
    message(STATUS "  Server:       OpenAI-compatible HTTP server (runanywhere-server)")
endif()
message(STATUS "")
message(STATUS "JNI bridge:     ${RAC_BUILD_JNI}")
message(STATUS "HTTP Server:    ${RAC_BUILD_SERVER}")
message(STATUS "====================================")
message(STATUS "")
