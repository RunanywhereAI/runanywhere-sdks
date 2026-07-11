# =============================================================================
# RunAnywhere SDKs — Root CMake project
# =============================================================================
#
# This is the SINGLE entry point for native builds across the monorepo.
# Subdirectories:
#   - sdk/runanywhere-commons/ — the C++ runtime library (rac_commons)
#   - idl/                     — protobuf IDL schemas + codegen (no CMake
#                                target; see idl/codegen/)
#   - engines/                 — engine plugins (llamacpp, onnx, sherpa,
#                                qhexrt, coreml). Each publishes
#                                a `rac_engine_vtable_t` at
#                                `RAC_PLUGIN_API_VERSION=3u` via
#                                `RAC_STATIC_PLUGIN_REGISTER` or a dlopen'd
#                                `rac_plugin_entry` symbol.
#   - tools/plugin-loader-smoke/ — CLI smoke test for the plugin loader
#
# Common builds:
#   cmake --preset macos-release && cmake --build --preset macos-release
#   cmake --preset linux-asan       && cmake --build --preset linux-asan
#   cmake --preset android-arm64    && cmake --build --preset android-arm64
#   cmake --preset ios-device       && cmake --build --preset ios-device
#   cmake --preset wasm             && cmake --build --preset wasm
#
# Per-language SDKs (Swift / Kotlin / Flutter / RN / Web) consume the artifacts
# this build produces — they do NOT call this CMake directly. The wrapper
# scripts under scripts/build/build-core-{android,xcframework,wasm}.sh wire the
# preset output into the right SDK directory layout.
# =============================================================================

# Must match sdk/runanywhere-commons/VERSIONS::MIN_CMAKE_VERSION (3.24).
# Required for FetchContent's FIND_PACKAGE_ARGS and DOWNLOAD_EXTRACT_TIMESTAMP
# (both added in CMake 3.24) used by the protobuf and ONNX Runtime fetches.
cmake_minimum_required(VERSION 3.24)

# Read version from the canonical VERSION file (kept under commons for
# historical reasons; treat as monorepo-wide).
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/VERSION" _RAC_VERSION_RAW)
string(STRIP "${_RAC_VERSION_RAW}" RAC_VERSION)

project(runanywhere
    VERSION ${RAC_VERSION}
    LANGUAGES CXX C
    DESCRIPTION "RunAnywhere SDKs — on-device AI runtime + per-language frontends"
    HOMEPAGE_URL "https://github.com/RunanywhereAI/runanywhere-sdks"
)

# Enable Objective-C AND Objective-C++ at the root project level.
#   - OBJCXX: engines/coreml/*.mm and any Apple-framework bridge TU.
#   - OBJC:   vendored llama.cpp ggml-metal *.m. These are plain Objective-C
#             (C-style implicit void*->T* conversions, e.g. `calloc`). Without
#             OBJC enabled, the Makefiles/Ninja generators have no Objective-C
#             language and fall back to compiling .m as Objective-C++ (clang++
#             -std=c++17), which rejects those conversions and breaks the Metal
#             build. (The Xcode generator used for the iOS presets maps .m->OBJC
#             natively, which is why device builds were unaffected.)
# `enable_language` inside a subdirectory doesn't populate the CMAKE_OBJC*_*
# toolchain variables the generator needs — it must run before subdirectories.
if(APPLE)
    enable_language(OBJC)
    enable_language(OBJCXX)
endif()

# =============================================================================
# Top-level options
#
# These are the *single source of truth* for build switches. Subdirectories
# (commons, engines/*, idl) inherit them via cache vars + the helper macros
# in cmake/plugins.cmake.
# =============================================================================

# Build mode
option(RAC_BUILD_SHARED       "Build rac_commons + plugins as shared libraries" OFF)
option(RAC_BUILD_TESTS        "Build CTest binaries" OFF)
option(RAC_BUILD_SERVER       "Build the OpenAI-compatible HTTP server (runanywhere-server)" OFF)
option(RAC_BUILD_PLATFORM     "Build the platform backend (Apple Foundation Models, System TTS) on Apple hosts" ON)
option(RAC_BUILD_JNI          "Build the JNI bridge for Android / JVM hosts" OFF)
option(RAC_BUILD_PLUGIN_SMOKE "Build tools/plugin-loader-smoke" OFF)
option(RAC_BUILD_CLI          "Build the rcli desktop CLI (sdk/runanywhere-cli)" OFF)
option(RAC_DESKTOP_ADAPTER    "Build the desktop (macOS/Linux) platform adapter + libcurl HTTP transport" OFF)

# Plugin loading mode
# RAC_STATIC_PLUGINS:
#   ON  → engine TUs are linked into rac_commons; iOS/WASM force this.
#   OFF → engines build as standalone librunanywhere_<name>.so/.dylib/.dll
#         and the host loads them via rac_registry_load_plugin().
# Forcing for iOS/Emscripten happens inside sdk/runanywhere-commons/CMakeLists.txt
# so subdirectory consumers see the final value.
option(RAC_STATIC_PLUGINS "Link engine plugins statically into rac_commons (forced ON on iOS/WASM)" OFF)

# Sanitizers
set(RAC_SANITIZER "" CACHE STRING "Enable a sanitizer: '', 'asan', 'tsan', 'ubsan'")
set_property(CACHE RAC_SANITIZER PROPERTY STRINGS "" asan tsan ubsan)

# WebAssembly knobs must be cached at the root so commons/engines see the
# final values before their CMakeLists run. The wasm wrapper target itself
# lives under sdk/runanywhere-web/wasm and is added after the engine targets.
if(EMSCRIPTEN)
    option(RAC_WASM_PTHREADS    "Enable pthreads in the WebAssembly target" OFF)
    option(RAC_WASM_DEBUG       "Enable debug assertions/logging in the WebAssembly target" OFF)
    option(RAC_WASM_BUILD_CORE  "Build the commons-only Web SDK WASM target" OFF)
    option(RAC_WASM_LLAMACPP    "Build the WebAssembly target with llama.cpp (LLM + VLM)" OFF)
    option(RAC_WASM_ONNX        "Build the WebAssembly target with ONNX/sherpa support" OFF)
    option(RAC_WASM_WEBGPU      "Enable WebGPU acceleration for the WebAssembly target" OFF)
    option(RAC_WASM_WEBGPU_JSPI "Use experimental JSPI instead of Asyncify for WebGPU" OFF)

    set(RAC_BUILD_JNI OFF CACHE BOOL "" FORCE)
    set(RAC_BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(RAC_BUILD_SHARED OFF CACHE BOOL "" FORCE)
    set(RAC_BUILD_PLATFORM OFF CACHE BOOL "" FORCE)

    # Backends follow the union of requested WASM targets. The core-only target
    # never links backend archives, but a configure that ONLY requests core
    # still leaves backends off (commons compiles standalone).
    if(RAC_WASM_LLAMACPP OR RAC_WASM_ONNX)
        set(RAC_BUILD_BACKENDS ON CACHE BOOL "" FORCE)
    else()
        set(RAC_BUILD_BACKENDS OFF CACHE BOOL "" FORCE)
    endif()

    set(RAC_BACKEND_LLAMACPP ${RAC_WASM_LLAMACPP} CACHE BOOL "" FORCE)
    set(RAC_BACKEND_ONNX ${RAC_WASM_ONNX} CACHE BOOL "" FORCE)

    if(RAC_WASM_LLAMACPP)
        set(GGML_METAL OFF CACHE BOOL "" FORCE)
        set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
        set(GGML_CUDA OFF CACHE BOOL "" FORCE)
        set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
        set(GGML_HIPBLAS OFF CACHE BOOL "" FORCE)
        set(GGML_SYCL OFF CACHE BOOL "" FORCE)
        set(GGML_KOMPUTE OFF CACHE BOOL "" FORCE)
        set(GGML_RPC OFF CACHE BOOL "" FORCE)
        set(GGML_ACCELERATE OFF CACHE BOOL "" FORCE)
        set(GGML_NEON OFF CACHE BOOL "" FORCE)
        set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
        set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
        set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
        set(GGML_CPU_HBM OFF CACHE BOOL "" FORCE)
    endif()

    if(RAC_WASM_LLAMACPP)
        if(RAC_WASM_WEBGPU)
            set(GGML_WEBGPU ON CACHE BOOL "" FORCE)
            set(GGML_WEBGPU_JSPI ${RAC_WASM_WEBGPU_JSPI} CACHE BOOL "" FORCE)
        else()
            set(GGML_WEBGPU OFF CACHE BOOL "" FORCE)
            set(GGML_WEBGPU_JSPI OFF CACHE BOOL "" FORCE)
        endif()
        set(LLAMA_WASM_MEM64 OFF CACHE BOOL "" FORCE)
        set(LLAMA_BUILD_HTML OFF CACHE BOOL "" FORCE)
        set(LLAMA_WASM_SINGLE_FILE OFF CACHE BOOL "" FORCE)
    endif()

    if(RAC_WASM_ONNX)
        set(ORT_USE_COREML OFF CACHE BOOL "" FORCE)
        set(ORT_USE_NNAPI OFF CACHE BOOL "" FORCE)
    endif()
endif()

# =============================================================================
# Shared cmake/ helpers
# =============================================================================

list(APPEND CMAKE_MODULE_PATH
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake"
    "${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/cmake"  # LoadVersions, FetchONNXRuntime, ... — kept for engine subdirs
)

# Shared cmake/ helper modules. The includes are OPTIONAL so a missing
# helper degrades gracefully rather than failing configure.
include(platform   OPTIONAL)   # rac_detect_platform()
include(sanitizers OPTIONAL)   # rac_apply_sanitizer()
include(plugins    OPTIONAL)   # rac_add_engine_plugin() / rac_force_load()
include(protobuf   OPTIONAL)   # RAC_HAVE_PROTOBUF / RAC_ABSL_LIBS

if(COMMAND rac_detect_platform)
    rac_detect_platform()
endif()

# =============================================================================
# Compiler defaults
# =============================================================================

# C++20 is required because parts of the codebase use designated initializers
# (struct vtable registration) that MSVC doesn't accept under C++17.
set(CMAKE_CXX_STANDARD          20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS        OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# =============================================================================
# Subdirectories
# =============================================================================

# Commons — always built. Owns its own backend-toggle option block.
add_subdirectory(sdk/runanywhere-commons)

# IDL — no CMake target. The C++ proto bindings the commons build consumes are
# committed under sdk/runanywhere-commons/src/generated/proto/ and compiled by
# rac_commons directly; Swift/Kotlin/Dart/TS bindings are generated by the
# helper scripts in idl/codegen/, not via CMake.

# runtimes/ — L1 compute-runtime plugins. Mirrors engines/ but scoped
# to compute targets (CPU, ONNX Runtime, CoreML, CUDA, …). The built-in CPU runtime
# is always folded into rac_commons; adapter runtimes are linked by their
# owning engines.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/runtimes/CMakeLists.txt")
    add_subdirectory(runtimes)
endif()

# engines/ — top-level engine plugin directory. LlamaCPP owns GGUF LLM/VLM,
# Sherpa owns speech primitives and legacy ONNX-named speech compatibility,
# ONNX owns embeddings and ONNXRT-backed generic services, QHexRT owns
# Qualcomm Hexagon NPU bundles, and CoreML owns Apple diffusion models.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/engines/CMakeLists.txt")
    add_subdirectory(engines)
endif()

# Fold the built-in CPU runtime's OBJECTs into rac_commons so there is no
# separate librac_runtime_cpu to ship.
if(TARGET rac_runtime_cpu)
    target_sources(rac_commons PRIVATE $<TARGET_OBJECTS:rac_runtime_cpu>)
endif()

# WASM wrapper target — composes rac_commons + any enabled engine plugins into
# the JavaScript/WebAssembly artifacts consumed by sdk/runanywhere-web.
if(EMSCRIPTEN
   AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-web/wasm/CMakeLists.txt")
    add_subdirectory(sdk/runanywhere-web/wasm)
endif()

# Smoke test for the plugin loader. Only built when explicitly
# requested so headless CI nodes don't pay the build cost.
if(RAC_BUILD_PLUGIN_SMOKE
   AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/plugin-loader-smoke/CMakeLists.txt")
    add_subdirectory(tools/plugin-loader-smoke)
endif()

# Enable CTest before SDK subdirectories that register their own tests.
if(RAC_BUILD_TESTS)
    enable_testing()
endif()

# rcli desktop CLI. Added after engines/ because it links the
# rac_backend_* targets that only exist once the engine subdirs configured.
if(RAC_BUILD_CLI)
    add_subdirectory(sdk/runanywhere-cli)
endif()

# Tests — wired through commons/tests for now. RAC_BUILD_TESTS is forwarded
# from this root option to the commons cache slot of the same name.
if(RAC_BUILD_TESTS)
    enable_testing()
    # Host-only race regression: compile the real QHexRT STT adapter against a
    # deterministic fake C runtime so CI can prove same-session operations do
    # not overlap even when Qualcomm device libraries are unavailable.
    if(NOT TARGET test_qhexrt_session_serialization)
        find_package(Threads REQUIRED)
        add_executable(test_qhexrt_session_serialization
            engines/qhexrt/tests/test_qhexrt_session_serialization.cpp
            engines/qhexrt/qhexrt_stt_ops.cpp
        )
        target_include_directories(test_qhexrt_session_serialization PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt/tests/fake_qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
        )
        target_link_libraries(test_qhexrt_session_serialization PRIVATE
            rac_commons
            Threads::Threads
        )
        target_compile_features(test_qhexrt_session_serialization PRIVATE cxx_std_17)
        add_test(NAME qhexrt_session_serialization_tests
                 COMMAND test_qhexrt_session_serialization)
    endif()
    # Host-only VLM cancellation regression: cancellation during native reset
    # must stop that request without poisoning the next independent request.
    if(NOT TARGET test_qhexrt_vlm_cancellation)
        find_package(Threads REQUIRED)
        add_executable(test_qhexrt_vlm_cancellation
            engines/qhexrt/tests/test_qhexrt_vlm_cancellation.cpp
            engines/qhexrt/qhexrt_vlm_ops.cpp
        )
        target_include_directories(test_qhexrt_vlm_cancellation PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt/tests/fake_qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
        )
        target_link_libraries(test_qhexrt_vlm_cancellation PRIVATE
            rac_commons
            Threads::Threads
        )
        target_compile_features(test_qhexrt_vlm_cancellation PRIVATE cxx_std_17)
        add_test(NAME qhexrt_vlm_cancellation_tests
                 COMMAND test_qhexrt_vlm_cancellation)
    endif()
    # Host-only bridge regression: the semantic disable_thinking flag must reach
    # QHexRT's template-aware input ABI for both batch and streaming generation.
    if(NOT TARGET test_qhexrt_llm_thinking_bridge)
        find_package(Threads REQUIRED)
        add_executable(test_qhexrt_llm_thinking_bridge
            engines/qhexrt/tests/test_qhexrt_llm_thinking_bridge.cpp
            engines/qhexrt/qhexrt_llm_ops.cpp
        )
        target_include_directories(test_qhexrt_llm_thinking_bridge PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt/tests/fake_qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
        )
        target_link_libraries(test_qhexrt_llm_thinking_bridge PRIVATE
            rac_commons
            Threads::Threads
        )
        target_compile_features(test_qhexrt_llm_thinking_bridge PRIVATE cxx_std_17)
        add_test(NAME qhexrt_llm_thinking_bridge_tests
                 COMMAND test_qhexrt_llm_thinking_bridge)
    endif()
    # Host-only provider cancellation regression: cancel must survive the
    # reset/setup window, interrupt prefill without waiting for a token callback,
    # and map a callback stop to RAC_ERROR_CANCELLED even if QHexRT returns cleanly.
    if(NOT TARGET test_qhexrt_llm_cancellation)
        find_package(Threads REQUIRED)
        add_executable(test_qhexrt_llm_cancellation
            engines/qhexrt/tests/test_qhexrt_llm_cancellation.cpp
            engines/qhexrt/qhexrt_llm_ops.cpp
        )
        target_include_directories(test_qhexrt_llm_cancellation PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt/tests/fake_qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
        )
        target_link_libraries(test_qhexrt_llm_cancellation PRIVATE
            rac_commons
            Threads::Threads
        )
        target_compile_features(test_qhexrt_llm_cancellation PRIVATE cxx_std_17)
        add_test(NAME qhexrt_llm_cancellation_tests
                 COMMAND test_qhexrt_llm_cancellation)
    endif()
    # QHexRT owns Qualcomm chip selection and the device-aware model catalog
    # facade. The test lives with the engine and links after the engine target
    # exists; commons tests intentionally remain backend-neutral.
    if(RAC_BACKEND_QHEXRT AND TARGET rac_backend_qhexrt AND
       NOT TARGET test_qhexrt_model_catalog)
        add_executable(test_qhexrt_model_catalog
            engines/qhexrt/tests/test_qhexrt_model_catalog.cpp)
        target_include_directories(test_qhexrt_model_catalog PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/qhexrt/include
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
        )
        target_link_libraries(test_qhexrt_model_catalog PRIVATE
            rac_backend_qhexrt
            rac_commons
        )
        if(RAC_PROTOBUF_RUNTIME_ENABLED)
            target_compile_definitions(test_qhexrt_model_catalog PRIVATE
                RAC_QHEXRT_HAVE_PROTOBUF=1)
            target_include_directories(test_qhexrt_model_catalog PRIVATE
                ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/src/generated/proto)
            if(TARGET protobuf::libprotobuf)
                target_link_libraries(test_qhexrt_model_catalog PRIVATE protobuf::libprotobuf)
            elseif(Protobuf_LIBRARIES)
                target_include_directories(test_qhexrt_model_catalog PRIVATE
                    ${Protobuf_INCLUDE_DIRS})
                target_link_libraries(test_qhexrt_model_catalog PRIVATE ${Protobuf_LIBRARIES})
            endif()
        endif()
        if(COMMAND rac_link_archive_deps)
            rac_link_archive_deps(test_qhexrt_model_catalog)
        endif()
        target_compile_features(test_qhexrt_model_catalog PRIVATE cxx_std_17)
        add_test(NAME qhexrt_model_catalog_tests COMMAND test_qhexrt_model_catalog)
    endif()
    # commons-010: sherpa plugin-entry smoke test. Wired here because
    # rac_backend_sherpa is built by engines/
    # which is configured after sdk/runanywhere-commons/, so the target does
    # not exist when commons/tests/CMakeLists.txt runs.
    if(RAC_BACKEND_SHERPA AND TARGET rac_backend_sherpa AND NOT TARGET test_plugin_entry_sherpa)
        add_executable(test_plugin_entry_sherpa
            sdk/runanywhere-commons/tests/test_plugin_entry_sherpa.cpp)
        target_include_directories(test_plugin_entry_sherpa PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/tests
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
        )
        target_link_libraries(test_plugin_entry_sherpa PRIVATE
            rac_commons
            rac_backend_sherpa
        )
        if(TARGET archive_static)
            target_link_libraries(test_plugin_entry_sherpa PRIVATE archive_static)
        endif()
        if(TARGET zlibstatic)
            target_link_libraries(test_plugin_entry_sherpa PRIVATE zlibstatic)
        endif()
        if(TARGET bz2_bundled)
            target_link_libraries(test_plugin_entry_sherpa PRIVATE bz2_bundled)
        endif()
        target_compile_features(test_plugin_entry_sherpa PRIVATE cxx_std_17)
        add_test(NAME plugin_entry_sherpa_tests COMMAND test_plugin_entry_sherpa)
    endif()

    if(APPLE AND RAC_BACKEND_COREML
       AND TARGET rac_backend_coreml
       AND NOT TARGET test_diffusion_coreml_generate)
        add_executable(test_diffusion_coreml_generate
            sdk/runanywhere-commons/tests/test_diffusion_coreml_generate.cpp)
        target_include_directories(test_diffusion_coreml_generate PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/tests
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
            ${CMAKE_CURRENT_SOURCE_DIR}/engines/coreml
        )
        target_link_libraries(test_diffusion_coreml_generate PRIVATE
            rac_commons
            rac_backend_coreml
        )
        if(TARGET archive_static)
            target_link_libraries(test_diffusion_coreml_generate PRIVATE archive_static)
        endif()
        if(TARGET zlibstatic)
            target_link_libraries(test_diffusion_coreml_generate PRIVATE zlibstatic)
        endif()
        if(TARGET bz2_bundled)
            target_link_libraries(test_diffusion_coreml_generate PRIVATE bz2_bundled)
        endif()
        target_compile_features(test_diffusion_coreml_generate PRIVATE cxx_std_17)
        add_test(NAME diffusion_coreml_generate_tests COMMAND test_diffusion_coreml_generate)
    endif()

    # coreml engine plugin-entry smoke test. Same wiring rationale as sherpa:
    # rac_backend_coreml is built by engines/ which is
    # configured after sdk/runanywhere-commons/. The coreml engine is the sole
    # RAC_PRIMITIVE_DIFFUSION provider, so this locks the manifest's COREML
    # runtime/format + diffusion_ops slot that the EngineRouter routes against;
    # test_diffusion_coreml_generate.cpp only exercises the backend directly and
    # bypasses the plugin-entry/vtable path. Apple-only because the backend is.
    if(APPLE AND RAC_BACKEND_COREML
       AND TARGET rac_backend_coreml
       AND NOT TARGET test_plugin_entry_coreml)
        add_executable(test_plugin_entry_coreml
            sdk/runanywhere-commons/tests/test_plugin_entry_coreml.cpp)
        target_include_directories(test_plugin_entry_coreml PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/tests
            ${CMAKE_CURRENT_SOURCE_DIR}/sdk/runanywhere-commons/include
        )
        target_link_libraries(test_plugin_entry_coreml PRIVATE
            rac_commons
            rac_backend_coreml
        )
        if(TARGET archive_static)
            target_link_libraries(test_plugin_entry_coreml PRIVATE archive_static)
        endif()
        if(TARGET zlibstatic)
            target_link_libraries(test_plugin_entry_coreml PRIVATE zlibstatic)
        endif()
        if(TARGET bz2_bundled)
            target_link_libraries(test_plugin_entry_coreml PRIVATE bz2_bundled)
        endif()
        target_compile_features(test_plugin_entry_coreml PRIVATE cxx_std_17)
        add_test(NAME plugin_entry_coreml_tests
                 COMMAND test_plugin_entry_coreml)
    endif()

    # Cross-SDK parity test harness.
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tests/streaming/CMakeLists.txt")
        add_subdirectory(tests/streaming)
    endif()
endif()

# =============================================================================
# Configuration summary (matches the commons summary block for consistency)
# =============================================================================

# Resolve genex-free strings: message() runs at configure time and prints
# generator expressions literally, so compute the mode labels with if().
if(RAC_BUILD_SHARED)
    set(_rac_build_mode "SHARED")
else()
    set(_rac_build_mode "STATIC")
endif()
if(RAC_STATIC_PLUGINS)
    set(_rac_plugin_mode "STATIC (linked into commons)")
else()
    set(_rac_plugin_mode "SHARED (dlopen-loaded)")
endif()

message(STATUS "")
message(STATUS "============================================")
message(STATUS "RunAnywhere SDKs — root CMake configured")
message(STATUS "============================================")
message(STATUS "Version          : ${RAC_VERSION}")
message(STATUS "Build mode       : ${_rac_build_mode}")
message(STATUS "Plugin mode      : ${_rac_plugin_mode}")
message(STATUS "Sanitizer        : ${RAC_SANITIZER}")
message(STATUS "Tests            : ${RAC_BUILD_TESTS}")
message(STATUS "Server (HTTP)    : ${RAC_BUILD_SERVER}")
message(STATUS "Platform backend : ${RAC_BUILD_PLATFORM}")
message(STATUS "JNI bridge       : ${RAC_BUILD_JNI}")
message(STATUS "Plugin smoke CLI : ${RAC_BUILD_PLUGIN_SMOKE}")
message(STATUS "CLI (rcli)       : ${RAC_BUILD_CLI}")
message(STATUS "Desktop adapter  : ${RAC_DESKTOP_ADAPTER}")
message(STATUS "============================================")
message(STATUS "")
