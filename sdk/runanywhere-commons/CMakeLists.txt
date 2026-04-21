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
option(RAC_BACKEND_RAG "Build RAG pipeline (USearch vector search)" ON)
# WhisperCPP OFF by default - Sherpa-ONNX (NeMo CTC / Parakeet) is now the primary STT backend
option(RAC_BACKEND_WHISPERCPP "Build WhisperCPP backend" OFF)
if(APPLE)
    option(RAC_BACKEND_WHISPERKIT_COREML "Build WhisperKit CoreML backend (Apple Neural Engine STT)" ON)
    option(RAC_BACKEND_METALRT "Build MetalRT backend (custom Metal GPU kernels, Apple only)" OFF)
else()
    set(RAC_BACKEND_WHISPERKIT_COREML OFF CACHE BOOL "" FORCE)
    set(RAC_BACKEND_METALRT OFF CACHE BOOL "" FORCE)
endif()
option(RAC_BUILD_SERVER "Build OpenAI-compatible HTTP server (runanywhere-server)" OFF)

# =============================================================================
# C++ CONFIGURATION
# =============================================================================

# C++20 is required because MSVC does not implement C++17 designated initializers
# (e.g. `struct S s = {.field = value};`) — the codebase uses them in several
# places (service vtable registration, config structs). All supported compilers
# (GCC 10+, Clang 11+, MSVC 19.28+ / VS 2019 16.8+) support C++20.
set(CMAKE_CXX_STANDARD 20)
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
elseif(WIN32)
    set(RAC_PLATFORM_WINDOWS TRUE)
    set(RAC_PLATFORM_NAME "Windows")
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

# libarchive - streaming archive extraction (ZIP, TAR.GZ, TAR.BZ2)
# Used for native model archive extraction across all platforms
if(NOT DEFINED LIBARCHIVE_VERSION)
    set(LIBARCHIVE_VERSION "3.8.1")
endif()

# -----------------------------------------------------------------------------
# Zlib: Bundle from source when system zlib is not available.
# Windows (MSVC) and some cross-compilation targets don't ship zlib.
# We try system first; if not found, build from source so libarchive gets it.
# -----------------------------------------------------------------------------
find_package(ZLIB QUIET)
if(NOT ZLIB_FOUND)
    message(STATUS "System zlib not found — bundling from source...")
    FetchContent_Declare(
        zlib_src
        GIT_REPOSITORY https://github.com/madler/zlib.git
        GIT_TAG        v1.3.1
        GIT_SHALLOW    TRUE
    )
    # Prevent zlib from installing or building examples
    set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_LIBRARIES ON CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_HEADERS ON CACHE BOOL "" FORCE)
    set(SKIP_INSTALL_FILES ON CACHE BOOL "" FORCE)
    # Save and restore BUILD_SHARED_LIBS
    set(_SAVED_BSL_ZLIB ${BUILD_SHARED_LIBS})
    set(BUILD_SHARED_LIBS OFF)
    FetchContent_MakeAvailable(zlib_src)
    set(BUILD_SHARED_LIBS ${_SAVED_BSL_ZLIB})

    # Set cache variables so libarchive's find_package(ZLIB) picks up our build.
    # For multi-config generators (Visual Studio), we point to the static lib
    # output. The actual path is resolved at build time via target_link_libraries.
    set(ZLIB_INCLUDE_DIR "${zlib_src_SOURCE_DIR};${zlib_src_BINARY_DIR}" CACHE PATH "" FORCE)
    set(ZLIB_INCLUDE_DIRS "${zlib_src_SOURCE_DIR};${zlib_src_BINARY_DIR}" CACHE PATH "" FORCE)
    # Use the CMake target name directly - this works because we link manually below
    set(ZLIB_LIBRARY zlibstatic CACHE STRING "" FORCE)
    set(ZLIB_LIBRARIES zlibstatic CACHE STRING "" FORCE)
    set(ZLIB_FOUND TRUE CACHE BOOL "" FORCE)
    # Create an imported ZLIB::ZLIB target that points to our zlibstatic
    if(NOT TARGET ZLIB::ZLIB)
        add_library(ZLIB::ZLIB ALIAS zlibstatic)
    endif()
    # On MSVC, set zlibstatic output to a known location so the linker can find it
    if(MSVC AND TARGET zlibstatic)
        set_target_properties(zlibstatic PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib"
            ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib"
        )
    endif()
    message(STATUS "Bundled zlib ready (v1.3.1)")
else()
    message(STATUS "Using system zlib: ${ZLIB_LIBRARIES}")
endif()

# -----------------------------------------------------------------------------
# BZip2: Bundle from source for cross-compilation targets
# Android NDK and Emscripten don't ship libbz2. macOS/iOS have it in the SDK.
# We try system first; if not found, build from source so libarchive gets it.
# -----------------------------------------------------------------------------
find_package(BZip2 QUIET)
if(NOT BZIP2_FOUND)
    message(STATUS "System BZip2 not found — bundling from source for cross-compilation...")
    FetchContent_Declare(
        bzip2_src
        URL https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
        URL_HASH SHA256=ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269
    )
    FetchContent_MakeAvailable(bzip2_src)

    add_library(bz2_bundled STATIC
        ${bzip2_src_SOURCE_DIR}/blocksort.c
        ${bzip2_src_SOURCE_DIR}/huffman.c
        ${bzip2_src_SOURCE_DIR}/crctable.c
        ${bzip2_src_SOURCE_DIR}/randtable.c
        ${bzip2_src_SOURCE_DIR}/compress.c
        ${bzip2_src_SOURCE_DIR}/decompress.c
        ${bzip2_src_SOURCE_DIR}/bzlib.c
    )
    target_include_directories(bz2_bundled PUBLIC ${bzip2_src_SOURCE_DIR})
    set_target_properties(bz2_bundled PROPERTIES POSITION_INDEPENDENT_CODE ON)

    # Set cache variables so libarchive's find_package(BZip2) picks up our build
    set(BZIP2_INCLUDE_DIR "${bzip2_src_SOURCE_DIR}" CACHE PATH "" FORCE)
    set(BZIP2_LIBRARIES bz2_bundled CACHE STRING "" FORCE)
    set(BZIP2_FOUND TRUE CACHE BOOL "" FORCE)
    # On MSVC, set output to a known location so the linker can find it
    if(MSVC AND TARGET bz2_bundled)
        set_target_properties(bz2_bundled PROPERTIES
            ARCHIVE_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/lib"
            ARCHIVE_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}/lib"
        )
    endif()
    message(STATUS "Bundled BZip2 ready (v1.0.8)")
else()
    message(STATUS "Using system BZip2: ${BZIP2_LIBRARIES}")
endif()

FetchContent_Declare(
    libarchive
    GIT_REPOSITORY https://github.com/libarchive/libarchive.git
    GIT_TAG v${LIBARCHIVE_VERSION}
    GIT_SHALLOW TRUE
)
# Disable everything except the static library and the formats we need
set(ENABLE_MBEDTLS OFF CACHE BOOL "" FORCE)
set(ENABLE_NETTLE OFF CACHE BOOL "" FORCE)
set(ENABLE_OPENSSL OFF CACHE BOOL "" FORCE)
set(ENABLE_LIBB2 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZ4 OFF CACHE BOOL "" FORCE)
set(ENABLE_LZO OFF CACHE BOOL "" FORCE)
set(ENABLE_LZMA OFF CACHE BOOL "" FORCE)     # tar.xz not currently used by any model
set(ENABLE_ZSTD OFF CACHE BOOL "" FORCE)
set(ENABLE_ZLIB ON CACHE BOOL "" FORCE)      # Needed for tar.gz and zip
set(ENABLE_BZip2 ON CACHE BOOL "" FORCE)     # Needed for tar.bz2 (k2-fsa models)
set(ENABLE_LIBXML2 OFF CACHE BOOL "" FORCE)
set(ENABLE_EXPAT OFF CACHE BOOL "" FORCE)
set(ENABLE_PCREPOSIX OFF CACHE BOOL "" FORCE)
set(ENABLE_PCRE2POSIX OFF CACHE BOOL "" FORCE)
# libarchive's ENABLE_LIBGCC gates a `find_library(GCC_LIBRARY gcc)` / `-lgcc`
# link. Needed on MSVC for the bundled runtime; a no-op on Apple/Clang (no
# libgcc); on Linux+GCC keep it OFF so we don't add an explicit -lgcc to the
# link line (it's pulled in implicitly and adding it can cause duplicate-symbol
# warnings in static configurations).
if(MSVC)
    set(ENABLE_LIBGCC ON CACHE BOOL "" FORCE)
else()
    set(ENABLE_LIBGCC OFF CACHE BOOL "" FORCE)
endif()
set(ENABLE_CNG OFF CACHE BOOL "" FORCE)
set(ENABLE_TAR OFF CACHE BOOL "" FORCE)      # Don't build bsdtar binary
set(ENABLE_CPIO OFF CACHE BOOL "" FORCE)     # Don't build bsdcpio binary
set(ENABLE_CAT OFF CACHE BOOL "" FORCE)      # Don't build bsdcat binary
set(ENABLE_UNZIP OFF CACHE BOOL "" FORCE)    # Don't build bsdunzip binary
set(ENABLE_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_ACL OFF CACHE BOOL "" FORCE)
set(ENABLE_XATTR OFF CACHE BOOL "" FORCE)
set(ENABLE_ICONV OFF CACHE BOOL "" FORCE)
# Save and restore BUILD_SHARED_LIBS since libarchive respects it
set(_SAVED_BUILD_SHARED_LIBS ${BUILD_SHARED_LIBS})
set(BUILD_SHARED_LIBS OFF)
FetchContent_MakeAvailable(libarchive)
set(BUILD_SHARED_LIBS ${_SAVED_BUILD_SHARED_LIBS})

if(TARGET bz2_bundled AND TARGET archive_static)
    target_link_libraries(archive_static bz2_bundled)
endif()

# Link bundled zlib to libarchive if we built it from source
if(TARGET zlibstatic AND TARGET archive_static)
    target_link_libraries(archive_static zlibstatic)
    target_include_directories(archive_static PRIVATE ${zlib_src_SOURCE_DIR} ${zlib_src_BINARY_DIR})
endif()

# On MSVC multi-config generators, libarchive references "zlibstatic.lib" and
# "bz2_bundled.lib" by bare filename. The linker can't find them because they
# are built into <config>/ subdirectories. Fix: redirect their output to a
# single known directory and add it to the global linker search path.
if(MSVC)
    set(RAC_BUNDLED_LIB_DIR "${CMAKE_BINARY_DIR}/_bundled_libs")
    foreach(_cfg Release Debug RelWithDebInfo MinSizeRel)
        string(TOUPPER "${_cfg}" _CFG)
        if(TARGET zlibstatic)
            set_target_properties(zlibstatic PROPERTIES
                ARCHIVE_OUTPUT_DIRECTORY_${_CFG} "${RAC_BUNDLED_LIB_DIR}")
        endif()
        if(TARGET bz2_bundled)
            set_target_properties(bz2_bundled PROPERTIES
                ARCHIVE_OUTPUT_DIRECTORY_${_CFG} "${RAC_BUNDLED_LIB_DIR}")
        endif()
    endforeach()
    link_directories("${RAC_BUNDLED_LIB_DIR}")
endif()

message(STATUS "libarchive ready (v${LIBARCHIVE_VERSION})")

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
elseif(MSVC)
    # /W3 = reasonable warning level, /utf-8 = source/execution charset
    # /Zc:__cplusplus = report correct __cplusplus value
    # /EHsc = standard C++ exception handling
    add_compile_options(/W3 /utf-8 /Zc:__cplusplus /EHsc)
    # Suppress common harmless warnings in third-party code
    add_compile_options(/wd4244 /wd4267 /wd4996)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS NOMINMAX WIN32_LEAN_AND_MEAN)
    # Use generator expressions instead of CMAKE_BUILD_TYPE so Release flags
    # apply correctly with multi-config generators (Visual Studio), where
    # CMAKE_BUILD_TYPE is empty at configure time and the config is selected
    # at build time via --config Release.
    add_compile_options(
        $<$<CONFIG:Release>:/O2>
        $<$<CONFIG:Release>:/DNDEBUG>
    )
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
    src/core/rac_benchmark.cpp
    src/core/rac_benchmark_metrics.cpp
    src/core/rac_benchmark_log.cpp
    src/core/rac_benchmark_stats.cpp
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
    # GAP 02 Phase 7: unified engine plugin registry (rac_engine_vtable_t).
    src/plugin/rac_plugin_registry.cpp
    # GAP 03 Phase 1: dynamic plugin loader (dlopen path; gated by RAC_PLUGIN_MODE_SHARED).
    src/plugin/plugin_loader.cpp
    src/infrastructure/download/download_manager.cpp
    src/infrastructure/download/download_orchestrator.cpp
    src/infrastructure/model_management/model_registry.cpp
    src/infrastructure/model_management/lora_registry.cpp
    src/infrastructure/model_management/model_types.cpp
    src/infrastructure/model_management/model_paths.cpp
    src/infrastructure/model_management/model_strategy.cpp
    src/infrastructure/model_management/model_assignment.cpp
    src/infrastructure/model_management/model_compatibility.cpp
    src/infrastructure/storage/storage_analyzer.cpp
    src/infrastructure/file_management/file_manager.cpp
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
    src/infrastructure/extraction/rac_extraction.cpp
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
    # Result memory management (weak symbol fallbacks)
    # On MSVC, each service .cpp already provides strong definitions,
    # so result_free.cpp (which uses __attribute__((weak)) on GCC/Clang)
    # must be excluded to avoid LNK2005 duplicate symbol errors.
    $<$<NOT:$<CXX_COMPILER_ID:MSVC>>:src/features/result_free.cpp>
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

# libarchive - native archive extraction
# PUBLIC on Windows because MSVC static libs don't propagate transitive deps
if(WIN32)
    target_link_libraries(rac_commons PUBLIC archive_static)
    # Tell libarchive headers we're using the static library (not DLL)
    target_compile_definitions(rac_commons PRIVATE LIBARCHIVE_STATIC)
    if(TARGET zlibstatic)
        target_link_libraries(rac_commons PUBLIC zlibstatic)
    endif()
    if(TARGET bz2_bundled)
        target_link_libraries(rac_commons PUBLIC bz2_bundled)
    endif()
else()
    target_link_libraries(rac_commons PRIVATE archive_static)
endif()
target_include_directories(rac_commons PRIVATE ${libarchive_SOURCE_DIR}/libarchive ${libarchive_BINARY_DIR})

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

if(RAC_PLATFORM_WINDOWS)
    target_compile_definitions(rac_commons PRIVATE RAC_PLATFORM_WINDOWS=1)
    # ws2_32 = Winsock, shlwapi = path utilities
    target_link_libraries(rac_commons PUBLIC ws2_32 shlwapi)
endif()

# =============================================================================
# GAP 03: Plugin Loading Mode (static vs. dynamic)
# =============================================================================
# Two paths share one plugin entry-point convention:
#   - STATIC: plugin TUs compiled directly into rac_commons; registration
#     happens at process start via RAC_STATIC_PLUGIN_REGISTER(<name>).
#     iOS App Store + WebAssembly forbid dlopen, so they MUST use this path.
#   - SHARED: plugin TUs build standalone *.so / *.dylib / *.dll loaded at
#     runtime via rac_registry_load_plugin(path) (dlopen + dlsym).
#
# RAC_STATIC_PLUGINS:
#   ON  → STATIC mode (default on iOS / Emscripten / forced)
#   OFF → SHARED mode (default on Android / Linux / macOS / Windows)
if(RAC_PLATFORM_IOS OR EMSCRIPTEN)
    set(RAC_STATIC_PLUGINS ON CACHE BOOL
        "Link engine plugins statically into rac_commons (forced ON on iOS/WASM)" FORCE)
else()
    option(RAC_STATIC_PLUGINS
        "Link engine plugins statically into rac_commons (default OFF: use dlopen)" OFF)
endif()

if(RAC_STATIC_PLUGINS)
    target_compile_definitions(rac_commons PUBLIC RAC_PLUGIN_MODE_STATIC=1)
    message(STATUS "Plugin mode: STATIC (engine plugins linked into rac_commons)")
else()
    target_compile_definitions(rac_commons PUBLIC RAC_PLUGIN_MODE_SHARED=1)
    message(STATUS "Plugin mode: SHARED (engine plugins loaded via rac_registry_load_plugin)")
    # ${CMAKE_DL_LIBS} expands to -ldl on Linux/Android, empty on macOS/Win.
    target_link_libraries(rac_commons PUBLIC ${CMAKE_DL_LIBS})
endif()

set_target_properties(rac_commons PROPERTIES
    CXX_STANDARD 20
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

    if(RAC_BACKEND_METALRT AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/backends/metalrt/CMakeLists.txt")
        message(STATUS "  - MetalRT backend — folded into rac_commons")
        add_subdirectory(src/backends/metalrt)

        # MetalRT is an OBJECT library. Fold its compiled objects into
        # rac_commons so there is no separate rac_backend_metalrt artifact
        # to distribute — mirrors how RAG is integrated. Public builds ship
        # stub implementations; engine-enabled builds link the private
        # libmetalrt_engine.a via RAC_METALRT_ENGINE_LIB propagated from
        # the subdirectory.
        target_sources(rac_commons PRIVATE $<TARGET_OBJECTS:rac_backend_metalrt>)

        # Apple frameworks are needed wherever the wrappers are compiled.
        if(APPLE)
            target_link_libraries(rac_commons PUBLIC
                "-framework Metal"
                "-framework Foundation"
                "-framework Accelerate"
            )
        endif()

        # If the engine is available, link the private static lib onto
        # rac_commons so the OBJECT target's unresolved metalrt_* symbols
        # resolve in the final archive.
        if(RAC_METALRT_ENGINE_LIB)
            target_link_libraries(rac_commons PUBLIC ${RAC_METALRT_ENGINE_LIB})
        endif()
    endif()

    if(RAC_BACKEND_RAG AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/src/features/rag/CMakeLists.txt")
        message(STATUS "  - RAG pipeline (USearch) — folded into rac_commons")
        add_subdirectory(src/features/rag)

        # RAG is an OBJECT library. Fold its compiled objects into rac_commons
        # so there is no separate librac_backend_rag binary to distribute.
        target_sources(rac_commons PRIVATE $<TARGET_OBJECTS:rac_backend_rag>)

        # Propagate RAG's non-cyclic dependencies manually.
        # We intentionally do NOT use target_link_libraries(rac_commons PRIVATE rac_backend_rag)
        # because that would transitively pull in rac_backend_onnx (via the ONNX embedding
        # provider) and create a shared-library cycle:
        #   rac_commons -> rac_backend_rag -> rac_backend_onnx -> rac_commons
        # nlohmann_json is already linked project-wide (line 116).
        # Apple frameworks used by RAG (Accelerate) need explicit propagation.
        if(APPLE)
            target_link_libraries(rac_commons PUBLIC "-framework Accelerate")
        endif()
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
if(RAC_PLATFORM_WINDOWS)
    message(STATUS "  Platform:     Windows (MSVC)")
endif()
if(RAC_BUILD_BACKENDS)
    message(STATUS "  Backends:     LlamaCPP=${RAC_BACKEND_LLAMACPP}, ONNX=${RAC_BACKEND_ONNX}, WhisperCPP=${RAC_BACKEND_WHISPERCPP}, WhisperKitCoreML=${RAC_BACKEND_WHISPERKIT_COREML}, MetalRT=${RAC_BACKEND_METALRT}")
    if(RAC_BACKEND_RAG)
        message(STATUS "  RAG pipeline: Enabled (folded into rac_commons)")
    endif()
endif()
if(RAC_BUILD_SERVER)
    message(STATUS "  Server:       OpenAI-compatible HTTP server (runanywhere-server)")
endif()
message(STATUS "")
message(STATUS "JNI bridge:     ${RAC_BUILD_JNI}")
message(STATUS "HTTP Server:    ${RAC_BUILD_SERVER}")
message(STATUS "====================================")
message(STATUS "")
