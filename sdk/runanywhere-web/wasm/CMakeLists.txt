# Must match sdk/runanywhere-commons/VERSIONS::MIN_CMAKE_VERSION (3.24).
cmake_minimum_required(VERSION 3.24)

project(RunAnywhereWebWASM
    VERSION 0.1.0
    LANGUAGES CXX C
    DESCRIPTION "RunAnywhere Web SDK - RACommons compiled to WebAssembly"
)

# =============================================================================
# EMSCRIPTEN CHECK
# =============================================================================

if(NOT EMSCRIPTEN)
    message(FATAL_ERROR
        "This CMakeLists.txt must be built with Emscripten.\n"
        "Use: emcmake cmake -B build -S ."
    )
endif()

message(STATUS "Building RACommons for WebAssembly (Emscripten)")

# =============================================================================
# OPTIONS
# =============================================================================
#
# Web SDK WASM build now produces up to four self-contained Emscripten
# executables, one per npm package + an optional WebGPU variant of llamacpp:
#
#   RAC_WASM_BUILD_CORE     -> packages/core/wasm/racommons.{js,wasm}
#                              (commons-only — no backend engines)
#   RAC_WASM_LLAMACPP       -> packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}
#                              (commons + llama.cpp engine: LLM + VLM)
#   RAC_WASM_LLAMACPP +
#   RAC_WASM_WEBGPU         -> packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}
#                              (extra GPU variant of llamacpp)
#   RAC_WASM_ONNX           -> packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}
#                              (commons + ONNX + Sherpa for STT/TTS/VAD)
#
# Each is a standalone Emscripten module with its own EXPORT_NAME so the TS
# layer can host them side-by-side without symbol clashes.

option(RAC_WASM_PTHREADS    "Enable pthreads (requires SharedArrayBuffer)" OFF)
option(RAC_WASM_DEBUG       "Enable debug assertions and verbose logging" OFF)
option(RAC_WASM_BUILD_CORE  "Build the commons-only Web SDK WASM target" OFF)
option(RAC_WASM_LLAMACPP    "Build the llama.cpp Web SDK WASM target (LLM + VLM)" OFF)
option(RAC_WASM_ONNX        "Build the ONNX + Sherpa Web SDK WASM target" OFF)
option(RAC_WASM_WEBGPU      "Also emit the WebGPU variant of the llama.cpp target (requires JSPI)" OFF)

# =============================================================================
# C++ CONFIGURATION
# =============================================================================

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# =============================================================================
# RACommons CONFIGURATION
# =============================================================================

# Point to the RACommons source tree
set(RAC_COMMONS_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../runanywhere-commons")

if(NOT EXISTS "${RAC_COMMONS_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "RACommons not found at: ${RAC_COMMONS_DIR}\n"
        "Expected: sdk/runanywhere-commons/ relative to sdk/runanywhere-web/"
    )
endif()

# Disable features not applicable to WASM
set(RAC_BUILD_JNI OFF CACHE BOOL "" FORCE)
set(RAC_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(RAC_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(RAC_BUILD_PLATFORM OFF CACHE BOOL "" FORCE)

# Enable backends based on options.
# NOTE: Each WASM target picks which static archives it links from the unified
# set of backend libraries below. We always build llama.cpp + ONNX archives
# whenever ANY backend WASM target is requested, so the same RACommons tree
# can satisfy multiple per-package binaries in one configure step — keeps
# things simple, dead-strip handles unused engines.
if(RAC_WASM_LLAMACPP OR RAC_WASM_ONNX OR RAC_WASM_BUILD_CORE)
    set(RAC_BUILD_BACKENDS ON CACHE BOOL "" FORCE)
else()
    set(RAC_BUILD_BACKENDS OFF CACHE BOOL "" FORCE)
endif()

# Individual backend flags
set(RAC_BACKEND_LLAMACPP ${RAC_WASM_LLAMACPP} CACHE BOOL "" FORCE)
set(RAC_BACKEND_ONNX ${RAC_WASM_ONNX} CACHE BOOL "" FORCE)

# =============================================================================
# BACKEND-SPECIFIC CONFIGURATION
# =============================================================================
# IMPORTANT: These must be set BEFORE add_subdirectory() so that llama.cpp
# and ONNX CMake files see the correct cache variables.

if(RAC_WASM_LLAMACPP)
    message(STATUS "Building with llama.cpp LLM backend for WASM")

    # Disable all GPU/accelerator backends not applicable to WASM
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

    # WebGPU acceleration (optional, produces a separate executable target)
    if(RAC_WASM_WEBGPU)
        message(STATUS "WebGPU acceleration ENABLED for llama.cpp")
        set(GGML_WEBGPU ON CACHE BOOL "" FORCE)
        # JSPI bridges async WebGPU calls from synchronous C code
        set(GGML_WEBGPU_JSPI ON CACHE BOOL "" FORCE)
    else()
        set(GGML_WEBGPU OFF CACHE BOOL "" FORCE)
    endif()

    # Disable wasm64 / MEMORY64 mode -- not yet widely supported in browsers
    # and causes wasm32/wasm64 linker mismatch with our main module
    set(LLAMA_WASM_MEM64 OFF CACHE BOOL "" FORCE)

    # Disable llama.cpp HTML output and single-file embedding
    set(LLAMA_BUILD_HTML OFF CACHE BOOL "" FORCE)
    set(LLAMA_WASM_SINGLE_FILE OFF CACHE BOOL "" FORCE)
endif()

if(RAC_WASM_ONNX)
    message(STATUS "Building with sherpa-onnx TTS/VAD backend for WASM")

    # ONNX Runtime Web can use WebAssembly SIMD but not CoreML/NNAPI
    set(ORT_USE_COREML OFF CACHE BOOL "" FORCE)
    set(ORT_USE_NNAPI OFF CACHE BOOL "" FORCE)
endif()

# Enable C++ exception handling at compile-time for ALL targets.
# When WebGPU is enabled, -fwasm-exceptions is required (JSPI is
# incompatible with the older JS-based exception mechanism).
# Otherwise, the classic -fexceptions flag works with DISABLE_EXCEPTION_CATCHING=0.
#
# CRITICAL BUG FIX (WASM-EXC-01): `add_compile_options()` only applies to
# targets created AFTER it runs. The root CMakeLists.txt adds this WASM
# subdirectory AFTER `sdk/runanywhere-commons` and `engines/llamacpp` have
# already configured their targets (and llama.cpp's FetchContent has built
# `llama`, `ggml*`, `llama-common*` targets). Without an explicit
# `target_compile_options()` on each pre-existing target, llama.cpp's
# translation units compiled WITHOUT exception support, so a throw from
# inside `llama_decode` / `llama_sampler_sample` would invoke `__cxa_throw`
# against an unwind table that has no catch frames — surfacing in JS as
# `WebAssembly.Exception` instead of being caught by the `catch (...)`
# block in `rac_llm_llamacpp_generate_stream`.
#
# Fix: explicitly propagate the exception flag to every existing C++ target
# that participates in the decode call chain. Subsequently-created targets
# (e.g. the WASM executables added below) still pick up the flag via
# `add_compile_options()`, so we keep that for forward-coverage.
if(RAC_WASM_WEBGPU)
    set(_RAC_WASM_EXC_FLAG "-fwasm-exceptions")
else()
    set(_RAC_WASM_EXC_FLAG "-fexceptions")
endif()

add_compile_options("${_RAC_WASM_EXC_FLAG}")

# Apply to pre-existing targets that were configured before this
# subdirectory was added. Each must be tested with `if(TARGET ...)` because
# the set of available targets depends on which backends were enabled at
# the root configure step.
set(_RAC_WASM_EXC_TARGETS
    # Commons core — contains the proto service layer that catches throws
    # from the engine and converts them into error events.
    rac_commons
    # llama.cpp engine — Emscripten-only catch sites in rac_llm_llamacpp.cpp
    # rely on this archive being compiled with matching exception support.
    rac_backend_llamacpp
    # llama.cpp FetchContent targets — the actual throw sites
    # (llama_decode, llama_sampler_sample, gguf parsing).
    llama
    llama-common
    llama-common-base
    # ggml backends — tensor ops can throw on bad logits / OOM.
    ggml
    ggml-base
    ggml-cpu
    # ONNX / Sherpa engine — only relevant for the onnx WASM target but
    # listed defensively so the speech path is consistent.
    rac_backend_onnx
    rac_backend_sherpa
)

foreach(_tgt ${_RAC_WASM_EXC_TARGETS})
    if(TARGET ${_tgt})
        target_compile_options(${_tgt} PRIVATE "${_RAC_WASM_EXC_FLAG}")
        # Static archives don't need link flags, but interface link options
        # ensure any future SHARED variant correctly links the unwinder.
        get_target_property(_tgt_type ${_tgt} TYPE)
        if(_tgt_type STREQUAL "SHARED_LIBRARY" OR _tgt_type STREQUAL "EXECUTABLE")
            target_link_options(${_tgt} PRIVATE "${_RAC_WASM_EXC_FLAG}")
        endif()
    endif()
endforeach()

# This target is wired from the repo-root CMakeLists after rac_commons and the
# selected engine plugins have already been configured. Keep it in that build
# graph so the wrapper never falls back to Emscripten's default `a.out.*`
# output or an engine-less commons-only build.
if(NOT TARGET rac_commons)
    message(FATAL_ERROR
        "WASM targets must be configured from the repository root.\n"
        "Use: cmake --preset wasm && cmake --build --preset wasm --target racommons_llamacpp_wasm"
    )
endif()

if(RAC_WASM_LLAMACPP AND NOT TARGET rac_backend_llamacpp)
    message(FATAL_ERROR "RAC_WASM_LLAMACPP=ON requires rac_backend_llamacpp. Configure the root build with llama.cpp enabled.")
endif()
if(RAC_WASM_ONNX AND NOT TARGET rac_backend_onnx)
    message(FATAL_ERROR
        "RAC_WASM_ONNX=ON requires rac_backend_onnx (embeddings + generic ORT services). "
        "Configure the root build with ONNX enabled. "
        "Note: under Emscripten, engines/onnx requires the vendored static archive at "
        "sdk/runanywhere-commons/third_party/onnxruntime-wasm/lib/libonnxruntime.a. "
    )
endif()
# Sherpa backend provides STT/TTS/VAD under the ONNX umbrella on WASM.
# It's optional: the build continues when the vendored Sherpa archives
# aren't present, but STT/TTS/VAD routing will return BackendNotAvailable
# at runtime.
if(RAC_WASM_ONNX AND NOT TARGET rac_backend_sherpa)
    message(STATUS
        "RAC_WASM_ONNX=ON: rac_backend_sherpa not available (no vendored "
        "sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/ archives). "
        "STT/TTS/VAD calls will return BackendNotAvailable. "
    )
endif()

# =============================================================================
# WASM PLATFORM SHIMS + EXPORTS SOURCE
# =============================================================================
# Both source files are compiled into EVERY WASM executable target. The
# wasm_exports.cpp translation unit re-compiles per-target with target-specific
# preprocessor definitions (RAC_WASM_LLAMACPP / RAC_WASM_ONNX / ...) so each
# binary contains only the symbols for its backends.

set(WASM_PLATFORM_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/platform/wasm_platform_shims.cpp
)

set(WASM_EXPORT_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/wasm_exports.cpp
)

# =============================================================================
# EXPORTED FUNCTIONS — COMMONS BASE LIST
# =============================================================================
# All rac_* C API functions in the commons-only set. Each per-target list is
# this base + backend-specific symbols appended below.
# Underscore prefix follows Emscripten's name-mangling convention.

set(RAC_EXPORTED_FUNCTIONS_BASE
    # Memory management
    "_rac_free"
    "_rac_alloc"
    "_rac_strdup"

    # Core initialization
    "_rac_init"
    "_rac_shutdown"
    "_rac_is_initialized"
    "_rac_get_version"
    "_rac_configure_logging"

    # Platform adapter
    "_rac_set_platform_adapter"
    "_rac_get_platform_adapter"
    "_rac_log"
    "_rac_get_current_time_ms"
    "_rac_http_download"
    "_rac_http_download_cancel"
    "_rac_extract_archive"
    "_rac_proto_buffer_init"
    "_rac_proto_buffer_copy"
    "_rac_proto_buffer_set_error"
    "_rac_proto_buffer_free"
    "_rac_proto_buffer_copy_to_raw"
    "_rac_proto_buffer_free_data"

    # HTTP client / download (Web SDK migration off hand-rolled
    # fetch() onto the commons libcurl-backed C ABI). See
    # sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_client.h
    # and rac_http_download.h. TypeScript wrapper lives at
    # sdk/runanywhere-web/packages/core/src/Adapters/HTTPAdapter.ts.
    # Progress/body chunk callbacks are installed via addFunction, so the
    # runtime already enables the required ALLOW_TABLE_GROWTH flag above.
    "_rac_http_client_create"
    "_rac_http_client_destroy"
    "_rac_http_request_send"
    "_rac_http_request_stream"
    "_rac_http_request_resume"
    "_rac_http_response_free"
    "_rac_http_download_execute"

    # Platform HTTP transport registry. The
    # WASM shim in rac_http_client_emscripten.cpp registers an
    # emscripten_fetch()-backed adapter via this vtable so the router in
    # rac_http_client_curl.cpp short-circuits to it. TypeScript side calls
    # _rac_http_transport_register_emscripten() once after module load.
    "_rac_http_transport_register"
    "_rac_http_transport_is_registered"
    "_rac_http_transport_register_emscripten"
    # JS-side adapter registration. JS provides function-table
    # indices (from Module.addFunction) that implement the transport
    # vtable directly in JS. See FetchHttpTransport.ts.
    "_rac_http_transport_register_from_js"

    # Struct layout helpers used by HTTPAdapter.ts to pack/unpack
    # rac_http_request_t / rac_http_response_t / rac_http_download_request_t
    # without hard-coding offsets (safe against future field changes).
    "_rac_wasm_sizeof_http_request"
    "_rac_wasm_offsetof_http_request_method"
    "_rac_wasm_offsetof_http_request_url"
    "_rac_wasm_offsetof_http_request_headers"
    "_rac_wasm_offsetof_http_request_header_count"
    "_rac_wasm_offsetof_http_request_body_bytes"
    "_rac_wasm_offsetof_http_request_body_len"
    "_rac_wasm_offsetof_http_request_timeout_ms"
    "_rac_wasm_offsetof_http_request_follow_redirects"
    "_rac_wasm_offsetof_http_request_expected_checksum_hex"
    "_rac_wasm_sizeof_http_response"
    "_rac_wasm_offsetof_http_response_status"
    "_rac_wasm_offsetof_http_response_headers"
    "_rac_wasm_offsetof_http_response_header_count"
    "_rac_wasm_offsetof_http_response_body_bytes"
    "_rac_wasm_offsetof_http_response_body_len"
    "_rac_wasm_offsetof_http_response_redirected_url"
    "_rac_wasm_sizeof_http_header_kv"
    "_rac_wasm_offsetof_http_header_kv_name"
    "_rac_wasm_offsetof_http_header_kv_value"
    "_rac_wasm_sizeof_http_download_request"
    "_rac_wasm_offsetof_http_download_request_url"
    "_rac_wasm_offsetof_http_download_request_destination_path"
    "_rac_wasm_offsetof_http_download_request_headers"
    "_rac_wasm_offsetof_http_download_request_header_count"
    "_rac_wasm_offsetof_http_download_request_timeout_ms"
    "_rac_wasm_offsetof_http_download_request_follow_redirects"
    "_rac_wasm_offsetof_http_download_request_resume_from_byte"
    "_rac_wasm_offsetof_http_download_request_expected_sha256_hex"
    "_rac_wasm_sizeof_proto_buffer"
    "_rac_wasm_offsetof_proto_buffer_data"
    "_rac_wasm_offsetof_proto_buffer_size"
    "_rac_wasm_offsetof_proto_buffer_status"
    "_rac_wasm_offsetof_proto_buffer_error_message"

    # Canonical rac_result_t -> SDKError proto mapping. Lets
    # SDKException route error construction through the shared commons helper
    # rac_result_to_proto_error instead of the local TypeScript category table.
    "_rac_wasm_result_to_proto_error"

    # Plugin registry / loader
    "_rac_plugin_api_version"
    "_rac_registry_load_plugin"
    "_rac_registry_unload_plugin"
    "_rac_registry_plugin_count"
    "_rac_registry_list_plugins"
    "_rac_registry_free_plugin_list"

    # Service registry
    # Legacy rac_service_* exports DELETED. Use rac_plugin_*
    # from rac/plugin/rac_plugin_entry.h.

    # Events
    "_rac_event_subscribe"
    "_rac_event_subscribe_all"
    "_rac_event_unsubscribe"
    "_rac_event_publish"
    "_rac_event_track"
    "_rac_event_category_name"
    "_rac_sdk_event_subscribe"
    "_rac_sdk_event_unsubscribe"
    "_rac_sdk_event_publish_proto"
    "_rac_sdk_event_poll"
    "_rac_sdk_event_publish_failure"
    "_rac_sdk_event_clear_queue"

    # Error handling
    "_rac_error_message"
    "_rac_error_get_details"
    "_rac_error_set_details"
    "_rac_error_clear_details"

    # Model registry
    "_rac_get_model_registry"
    "_rac_register_model"
    "_rac_get_model"
    "_rac_get_model_by_path"
    "_rac_model_registry_create"
    "_rac_model_registry_destroy"
    "_rac_model_registry_save"
    "_rac_model_registry_get"
    "_rac_model_registry_get_all"
    "_rac_model_registry_remove"
    "_rac_model_registry_get_downloaded"
    "_rac_model_registry_update_download_status"
    "_rac_model_registry_register_proto"
    "_rac_model_registry_update_proto"
    "_rac_model_registry_get_proto"
    "_rac_model_registry_list_proto"
    "_rac_model_registry_query_proto"
    "_rac_model_registry_list_downloaded_proto"
    "_rac_model_registry_remove_proto"
    "_rac_model_registry_get_model_proto"
    "_rac_model_registry_list_models_proto"
    "_rac_model_registry_import_proto"
    "_rac_model_registry_discover_proto"
    "_rac_model_registry_refresh_proto"
    "_rac_model_registry_proto_free"
    "_rac_model_info_is_downloaded"
    # Derive parameterCountB + isSmallModel from
    # RAModelInfo proto so the web example can drop its inlined heuristics.
    "_rac_model_info_is_small_model_proto"
    "_rac_model_info_parameter_count_b_proto"
    "_rac_model_info_alloc"
    "_rac_model_info_free"
    "_rac_model_info_array_free"
    "_rac_model_info_copy"
    "_rac_model_registry_discover_downloaded"
    "_rac_discovery_result_free"

    # Hardware profile/routing proto ABI. Browser/device facts remain Web-owned;
    # commons serializes the canonical HardwareProfileResult and accelerator
    # preference state for generated proto-ts callers.
    "_rac_hardware_profile_get"
    "_rac_hardware_profile_free"
    "_rac_hardware_get_accelerators"
    "_rac_hardware_set_accelerator_preference"

    # Model types
    "_rac_framework_display_name"
    "_rac_framework_supports_llm"
    "_rac_framework_supports_stt"
    "_rac_framework_supports_tts"
    "_rac_model_format_extension"

    # Model paths — base-dir configuration. Web has no native filesystem root,
    # but the C++ download orchestrator rejects an empty base via
    # `rac_model_paths_get_model_folder`. The TypeScript bridge installs a
    # synthetic prefix (e.g. "/opfs") after rac_init so path composition can
    # proceed; actual I/O still flows through PlatformAdapter file callbacks
    # against Emscripten MEMFS (see BUG-WEB-002).
    "_rac_model_paths_set_base_dir"
    "_rac_model_paths_get_base_dir"

    # Lifecycle
    "_rac_lifecycle_create"
    "_rac_lifecycle_load"
    "_rac_lifecycle_unload"
    "_rac_lifecycle_get_state"
    "_rac_lifecycle_is_loaded"
    "_rac_lifecycle_get_model_id"
    "_rac_lifecycle_get_service"
    "_rac_lifecycle_require_service"
    "_rac_lifecycle_destroy"
    "_rac_lifecycle_state_name"

    # Model lifecycle proto ABI. Generated model_types/sdk_events protos are
    # serialized through rac_proto_buffer_t so Web can expose the same stable
    # lifecycle surface as native SDKs.
    "_rac_model_lifecycle_load_proto"
    "_rac_model_lifecycle_unload_proto"
    "_rac_model_lifecycle_current_model_proto"
    "_rac_component_lifecycle_snapshot_proto"
    "_rac_model_lifecycle_reset"

    # LLM service
    "_rac_llm_create"
    "_rac_llm_initialize"
    "_rac_llm_generate"
    "_rac_llm_generate_stream"
    "_rac_llm_get_info"
    "_rac_llm_cancel"
    "_rac_llm_cleanup"
    "_rac_llm_destroy"
    "_rac_llm_result_free"
    "_rac_llm_set_stream_proto_callback"
    "_rac_llm_unset_stream_proto_callback"
    "_rac_llm_generate_proto"
    "_rac_llm_generate_stream_proto"
    "_rac_llm_cancel_proto"

    # LLM component
    "_rac_llm_component_create"
    "_rac_llm_component_configure"
    "_rac_llm_component_is_loaded"
    "_rac_llm_component_get_model_id"
    "_rac_llm_component_load_model"
    "_rac_llm_component_unload"
    "_rac_llm_component_cleanup"
    "_rac_llm_component_cancel"
    "_rac_llm_component_generate"
    "_rac_llm_component_supports_streaming"
    "_rac_llm_component_generate_stream"
    "_rac_llm_component_get_state"
    "_rac_llm_component_get_metrics"
    "_rac_llm_component_destroy"

    # Tool Calling
    "_rac_tool_call_parse"
    "_rac_tool_call_parse_with_format"
    "_rac_tool_call_parse_proto"
    "_rac_tool_call_free"
    "_rac_tool_call_validate_proto"
    "_rac_tool_call_format_name"
    "_rac_tool_call_detect_format"
    "_rac_tool_call_format_from_name"
    # Derive tool-call format from RAModelInfo proto.
    "_rac_tool_call_format_from_model_info_proto"
    "_rac_tool_call_format_prompt"
    "_rac_tool_call_format_prompt_with_format"
    "_rac_tool_call_format_prompt_json"
    "_rac_tool_call_format_prompt_json_with_format"
    "_rac_tool_call_format_prompt_json_with_format_name"
    "_rac_tool_call_build_initial_prompt"
    "_rac_tool_call_build_followup_prompt"
    "_rac_tool_call_format_prompt_proto"
    "_rac_tool_call_normalize_json"
    "_rac_tool_call_definitions_to_json"
    "_rac_tool_call_result_to_json"
    "_rac_tool_calling_run_loop_proto"
    # Session-based orchestration so the Web SDK can delegate
    # the tool-calling run loop to commons even when TS executors are async
    # (the run-loop-proto callback is synchronous and cannot await a JS Promise).
    "_rac_tool_calling_session_create_proto"
    "_rac_tool_calling_session_step_with_result_proto"
    "_rac_tool_calling_session_destroy_proto"
    # Cancel ABI so AbortSignal-driven Web hosts can interrupt
    # the in-flight tool-calling session generate from JS.
    "_rac_tool_calling_session_cancel_proto"
    "_rac_tool_calling_run_loop_with_handle_proto"
    "_rac_tool_calling_run_loop_cancel_proto"

    # STT service
    "_rac_stt_create"
    "_rac_stt_initialize"
    "_rac_stt_transcribe"
    "_rac_stt_transcribe_stream"
    "_rac_stt_get_info"
    "_rac_stt_cleanup"
    "_rac_stt_destroy"
    "_rac_stt_result_free"

    # STT component
    "_rac_stt_component_create"
    "_rac_stt_component_configure"
    "_rac_stt_component_is_loaded"
    "_rac_stt_component_get_model_id"
    "_rac_stt_component_load_model"
    "_rac_stt_component_unload"
    "_rac_stt_component_cleanup"
    "_rac_stt_component_transcribe"
    "_rac_stt_component_supports_streaming"
    "_rac_stt_component_transcribe_stream"
    "_rac_stt_component_transcribe_proto"
    "_rac_stt_component_transcribe_stream_proto"
    "_rac_stt_component_get_state"
    "_rac_stt_component_get_metrics"
    "_rac_stt_component_destroy"

    # STT hybrid router (commons-local — folds into rac_commons). The router C++
    # lives in src/router/hybrid/rac_stt_hybrid_router*.cpp and is anti-dead-stripped
    # by the routing #includes in wasm/src/wasm_exports.cpp. The Web binding's
    # REQUIRED_HYBRID_ROUTER_EXPORTS (HybridWasmModule.ts) hard-depends on the
    # lifecycle + 5 proto-byte calls + buffer-free + the two service-creation
    # helpers; the device-state / custom-filter table symbols are optional
    # (the binding degrades gracefully when absent). The cloud engine's
    # register/unregister are appended on the ONNX-sherpa target that owns the
    # offline STT side (see RAC_EXPORTED_FUNCTIONS_CLOUD below).
    "_rac_stt_hybrid_router_create"
    "_rac_stt_hybrid_router_destroy"
    "_rac_stt_hybrid_router_cancel"
    "_rac_stt_hybrid_router_set_offline_service_proto"
    "_rac_stt_hybrid_router_set_online_service_proto"
    "_rac_stt_hybrid_router_set_policy_proto"
    "_rac_stt_hybrid_router_transcribe_proto"
    "_rac_stt_hybrid_router_proto_buffer_free"
    "_rac_stt_hybrid_router_create_service"
    "_rac_stt_hybrid_router_destroy_service"
    # Hybrid host-state vtables (rac_hybrid_device_state.h /
    # rac_hybrid_custom_filter.h). The struct-based setters are exported here;
    # the flattened `*_from_js` convenience wrappers the TS layer prefers are a
    # separate future build delta (the binding falls back to the optimistic
    # default / ignores custom filters when they are absent).
    "_rac_hybrid_set_device_state"
    "_rac_hybrid_get_device_state_snapshot"
    "_rac_hybrid_register_custom_filter"
    "_rac_hybrid_unregister_custom_filter"
    "_rac_hybrid_invoke_custom_filter"

    # TTS service
    "_rac_tts_create"
    "_rac_tts_initialize"
    "_rac_tts_synthesize"
    "_rac_tts_synthesize_stream"
    "_rac_tts_stop"
    "_rac_tts_get_info"
    "_rac_tts_cleanup"
    "_rac_tts_destroy"
    "_rac_tts_result_free"

    # TTS component
    "_rac_tts_component_create"
    "_rac_tts_component_configure"
    "_rac_tts_component_is_loaded"
    "_rac_tts_component_get_voice_id"
    "_rac_tts_component_load_voice"
    "_rac_tts_component_unload"
    "_rac_tts_component_cleanup"
    "_rac_tts_component_stop"
    "_rac_tts_component_synthesize"
    "_rac_tts_component_synthesize_stream"
    "_rac_tts_component_list_voices_proto"
    "_rac_tts_component_synthesize_proto"
    "_rac_tts_component_synthesize_stream_proto"
    "_rac_tts_component_get_state"
    "_rac_tts_component_get_metrics"
    "_rac_tts_component_destroy"

    # VAD service
    "_rac_vad_create"
    "_rac_vad_initialize"
    "_rac_vad_set_activity_callback"
    "_rac_vad_set_audio_callback"
    "_rac_vad_pause"
    "_rac_vad_resume"
    "_rac_vad_process_samples"
    "_rac_vad_set_energy_threshold"
    "_rac_vad_get_info"
    "_rac_vad_destroy"

    # VAD component
    # rac_vad_{start,stop,reset} bare-service decls deleted;
    # use rac_vad_component_{start,stop,reset} / *_lifecycle_proto.
    "_rac_vad_component_create"
    "_rac_vad_component_configure"
    "_rac_vad_component_is_initialized"
    "_rac_vad_component_initialize"
    "_rac_vad_component_is_loaded"
    "_rac_vad_component_load_model"
    "_rac_vad_component_unload"
    "_rac_vad_component_cleanup"
    "_rac_vad_component_set_activity_callback"
    "_rac_vad_component_set_audio_callback"
    "_rac_vad_component_start"
    "_rac_vad_component_stop"
    "_rac_vad_component_reset"
    "_rac_vad_component_process"
    "_rac_vad_component_configure_proto"
    "_rac_vad_component_process_proto"
    "_rac_vad_component_get_statistics_proto"
    "_rac_vad_component_set_activity_proto_callback"
    "_rac_vad_component_is_speech_active"
    "_rac_vad_component_get_energy_threshold"
    "_rac_vad_component_set_energy_threshold"
    "_rac_vad_component_get_state"
    "_rac_vad_component_get_metrics"
    "_rac_vad_component_destroy"

    # Voice Agent
    "_rac_audio_pipeline_state_name"
    "_rac_audio_pipeline_can_activate_microphone"
    "_rac_audio_pipeline_can_play_tts"
    "_rac_audio_pipeline_is_valid_transition"
    "_rac_voice_agent_create_standalone"
    "_rac_voice_agent_create"
    "_rac_voice_agent_destroy"
    "_rac_voice_agent_load_stt_model"
    "_rac_voice_agent_load_llm_model"
    "_rac_voice_agent_load_tts_voice"
    "_rac_voice_agent_is_stt_loaded"
    "_rac_voice_agent_is_llm_loaded"
    "_rac_voice_agent_is_tts_loaded"
    "_rac_voice_agent_get_stt_model_id"
    "_rac_voice_agent_get_llm_model_id"
    "_rac_voice_agent_get_tts_voice_id"
    "_rac_voice_agent_initialize"
    "_rac_voice_agent_initialize_with_loaded_models"
    "_rac_voice_agent_cleanup"
    "_rac_voice_agent_is_ready"
    "_rac_voice_agent_process_voice_turn"
    "_rac_voice_agent_process_stream"
    "_rac_voice_agent_transcribe"
    "_rac_voice_agent_generate_response"
    "_rac_voice_agent_synthesize_speech"
    "_rac_voice_agent_detect_speech"
    "_rac_voice_agent_result_free"

    # Voice Agent — proto-byte streaming ABI
    # Required by sdk/runanywhere-web/packages/core/src/Adapters/
    # VoiceAgentStreamAdapter.ts, which calls it through
    # m._rac_voice_agent_set_proto_callback(handle, cbPtr, 0). Pair with
    # -sEXPORTED_RUNTIME_METHODS=['addFunction','removeFunction'] +
    # -sALLOW_TABLE_GROWTH=1 (already enabled in this target).
    "_rac_voice_agent_set_proto_callback"
    # Caller-side shutdown helper.
    "_rac_voice_agent_proto_quiesce"
    "_rac_voice_agent_initialize_proto"
    "_rac_voice_agent_component_states_proto"
    "_rac_voice_agent_process_voice_turn_proto"

    # Solutions runtime (rac/solutions/rac_solution.h).
    # Required by sdk/runanywhere-web/packages/core/src/Adapters/
    # SolutionAdapter.ts (proto-byte / YAML driven L5 pipeline runtime).
    # `rac_solution_create_from_proto` consumes a serialized
    # `runanywhere.v1.SolutionConfig` (or PipelineSpec) message; the
    # lifecycle verbs operate on the returned opaque handle.
    "_rac_solution_create_from_proto"
    "_rac_solution_create_from_yaml"
    "_rac_solution_start"
    "_rac_solution_stop"
    "_rac_solution_cancel"
    "_rac_solution_feed"
    "_rac_solution_close_input"
    "_rac_solution_destroy"

    # C++-owned proto download workflow. JS keeps only transport/progress
    # callback wiring while commons owns planning, lifecycle, resume/cancel,
    # and progress state.
    "_rac_download_set_progress_proto_callback"
    "_rac_download_plan_proto"
    "_rac_download_start_proto"
    "_rac_download_cancel_proto"
    "_rac_download_resume_proto"
    "_rac_download_progress_poll_proto"

    # Storage analyzer proto ABI. The browser supplies storage/file callbacks
    # locally; commons owns availability, delete planning and deletion policy.
    "_rac_storage_analyzer_create"
    "_rac_storage_analyzer_destroy"
    "_rac_storage_analyzer_info_proto"
    "_rac_storage_analyzer_availability_proto"
    "_rac_storage_analyzer_delete_plan_proto"
    "_rac_storage_analyzer_delete_proto"

    # VLM service
    "_rac_vlm_get_builtin_template"
    "_rac_vlm_result_free"
    "_rac_vlm_create"
    "_rac_vlm_initialize"
    "_rac_vlm_process"
    "_rac_vlm_process_stream"
    "_rac_vlm_get_info"
    "_rac_vlm_cancel"
    "_rac_vlm_process_proto"
    "_rac_vlm_process_stream_proto"
    "_rac_vlm_cancel_proto"
    "_rac_vlm_cleanup"
    "_rac_vlm_destroy"

    # VLM component
    "_rac_vlm_component_create"
    "_rac_vlm_component_configure"
    "_rac_vlm_component_is_loaded"
    "_rac_vlm_component_get_model_id"
    "_rac_vlm_component_load_model"
    "_rac_vlm_component_unload"
    "_rac_vlm_component_cleanup"
    "_rac_vlm_component_cancel"
    "_rac_vlm_component_process"
    "_rac_vlm_component_supports_streaming"
    "_rac_vlm_component_process_stream"
    "_rac_vlm_component_get_state"
    "_rac_vlm_component_get_metrics"
    "_rac_vlm_component_destroy"

    # Structured Output
    "_rac_structured_output_extract_json"
    "_rac_structured_output_find_complete_json"
    "_rac_structured_output_find_matching_brace"
    "_rac_structured_output_find_matching_bracket"
    "_rac_structured_output_prepare_prompt"
    "_rac_structured_output_prepare_prompt_proto"
    "_rac_structured_output_get_system_prompt"
    "_rac_structured_output_validate"
    "_rac_structured_output_validate_proto"
    "_rac_structured_output_validation_free"
    "_rac_structured_output_parse_proto"
    "_rac_structured_output_generate_proto"
    "_rac_structured_output_generate_stream_proto"
    "_rac_structured_output_schema_to_json_proto"

    # Diffusion component
    "_rac_diffusion_generate_proto"
    "_rac_diffusion_generate_with_progress_proto"
    "_rac_diffusion_cancel_proto"
    "_rac_diffusion_component_create"
    "_rac_diffusion_component_configure"
    "_rac_diffusion_component_is_loaded"
    "_rac_diffusion_component_get_model_id"
    "_rac_diffusion_component_load_model"
    "_rac_diffusion_component_unload"
    "_rac_diffusion_component_cleanup"
    "_rac_diffusion_component_cancel"
    "_rac_diffusion_component_generate"
    "_rac_diffusion_component_generate_with_callbacks"
    "_rac_diffusion_component_get_capabilities"
    "_rac_diffusion_component_get_info"
    "_rac_diffusion_component_get_state"
    "_rac_diffusion_component_get_metrics"
    "_rac_diffusion_component_destroy"
    "_rac_diffusion_result_free"

    # Embeddings service
    "_rac_embeddings_create"
    "_rac_embeddings_initialize"
    "_rac_embeddings_embed"
    "_rac_embeddings_embed_batch"
    "_rac_embeddings_embed_batch_proto"
    "_rac_embeddings_get_info"
    "_rac_embeddings_cleanup"
    "_rac_embeddings_destroy"
    "_rac_embeddings_result_free"

    # Embeddings component
    "_rac_embeddings_component_create"
    "_rac_embeddings_component_configure"
    "_rac_embeddings_component_is_loaded"
    "_rac_embeddings_component_get_model_id"
    "_rac_embeddings_component_load_model"
    "_rac_embeddings_component_unload"
    "_rac_embeddings_component_cleanup"
    "_rac_embeddings_component_embed"
    "_rac_embeddings_component_embed_batch"
    "_rac_embeddings_component_get_state"
    "_rac_embeddings_component_get_metrics"
    "_rac_embeddings_component_destroy"

    # RAG generated-proto pipeline exports are appended conditionally on
    # RAC_BACKEND_RAG below — they are commons-local symbols (the RAG OBJECT
    # library folds into rac_commons). When RAC_BACKEND_RAG=ON these exports
    # ride along with both the llamacpp target and
    # the ONNX-sherpa target; the runtime layer surfaces
    # RAC_ERROR_FEATURE_NOT_AVAILABLE if no embeddings provider is registered.
    # See sdk/runanywhere-commons/CMakeLists.txt's RAC_WASM_RAG_STANDALONE
    # option for the Emscripten gating.

    # LoRA generated-proto service
    "_rac_get_lora_registry"
    "_rac_lora_register_proto"
    "_rac_lora_catalog_list_proto"
    "_rac_lora_catalog_query_proto"
    "_rac_lora_catalog_get_proto"
    "_rac_lora_catalog_mark_download_completed_proto"
    "_rac_lora_compatibility_proto"
    "_rac_lora_apply_proto"
    "_rac_lora_remove_proto"
    "_rac_lora_list_proto"
    "_rac_lora_state_proto"

    # Environment / SDK config
    "_rac_sdk_init"
    "_rac_sdk_init_phase1_proto"
    "_rac_sdk_init_phase2_proto"
    "_rac_sdk_get_config"
    "_rac_sdk_get_environment"
    "_rac_sdk_is_initialized"
    "_rac_sdk_reset"

    # Auth manager (read-only state query — used by RunAnywhere auth properties).
    # Future auth flows (authenticate/refresh) will need additional exports
    # paired with HTTP transport + secure storage wiring.
    "_rac_auth_is_authenticated"
    "_rac_auth_get_user_id"
    "_rac_auth_get_organization_id"
    "_rac_state_is_device_registered"

    # Telemetry
    "_rac_telemetry_manager_create"
    "_rac_telemetry_manager_destroy"
    "_rac_telemetry_manager_set_device_info"
    "_rac_telemetry_manager_set_http_callback"
    "_rac_telemetry_manager_track"
    "_rac_telemetry_manager_track_proto"
    "_rac_telemetry_manager_http_complete"
    "_rac_telemetry_manager_flush"
    "_rac_telemetry_payload_default"
    "_rac_telemetry_payload_free"

    # Event destination router — telemetry sink registration
    "_rac_events_set_telemetry_sink"

    # Platform Emit Helpers (called from TypeScript via ccall for STT/TTS/VAD/download events).
    # These now build canonical proto SDKEvents and publish through the destination router.
    "_rac_analytics_emit_stt_model_load_completed"
    "_rac_analytics_emit_stt_model_load_failed"
    "_rac_analytics_emit_stt_transcription_completed"
    "_rac_analytics_emit_stt_transcription_failed"
    "_rac_analytics_emit_tts_voice_load_completed"
    "_rac_analytics_emit_tts_voice_load_failed"
    "_rac_analytics_emit_tts_synthesis_completed"
    "_rac_analytics_emit_tts_synthesis_failed"
    "_rac_analytics_emit_vad_speech_started"
    "_rac_analytics_emit_vad_speech_ended"
    "_rac_analytics_emit_model_download_started"
    "_rac_analytics_emit_model_download_completed"
    "_rac_analytics_emit_model_download_failed"

    # WASM helper functions (sizeof, ping, version)
    "_rac_wasm_ping"
    "_rac_wasm_get_version_major"
    "_rac_wasm_get_version_minor"
    "_rac_wasm_get_version_patch"
    "_rac_wasm_sizeof_platform_adapter"
    # Per-field offsetof helpers for rac_platform_adapter_t — required so the
    # TS PlatformAdapter never hard-codes PTR_SIZE or sequential offsets.
    # These MUST ship in BOTH CPU and WebGPU variants.
    # The pre-9226feb2c WebGPU artifact predated these helpers, which caused
    # PlatformAdapter.register() to throw and LlamaCppBridge.ts to silently
    # fall back to CPU. Always rebuild `racommons-llamacpp-webgpu.{js,wasm}`
    # alongside the CPU variant via `./wasm/scripts/build.sh --llamacpp --webgpu`
    # whenever this list or wasm/src/wasm_exports.cpp changes.
    "_rac_wasm_offsetof_platform_adapter_abi_version"
    "_rac_wasm_offsetof_platform_adapter_struct_size"
    "_rac_wasm_offsetof_platform_adapter_file_exists"
    "_rac_wasm_offsetof_platform_adapter_file_read"
    "_rac_wasm_offsetof_platform_adapter_file_write"
    "_rac_wasm_offsetof_platform_adapter_file_delete"
    "_rac_wasm_offsetof_platform_adapter_secure_get"
    "_rac_wasm_offsetof_platform_adapter_secure_set"
    "_rac_wasm_offsetof_platform_adapter_secure_delete"
    "_rac_wasm_offsetof_platform_adapter_log"
    "_rac_wasm_offsetof_platform_adapter_now_ms"
    "_rac_wasm_offsetof_platform_adapter_get_memory_info"
    "_rac_wasm_offsetof_platform_adapter_http_download"
    "_rac_wasm_offsetof_platform_adapter_http_download_cancel"
    "_rac_wasm_offsetof_platform_adapter_extract_archive"
    "_rac_wasm_offsetof_platform_adapter_file_list_directory"
    "_rac_wasm_offsetof_platform_adapter_is_non_empty_directory"
    "_rac_wasm_offsetof_platform_adapter_get_vendor_id"
    "_rac_wasm_offsetof_platform_adapter_user_data"
    "_rac_wasm_sizeof_directory_entry"
    "_rac_wasm_offsetof_directory_entry_name"
    "_rac_wasm_offsetof_directory_entry_is_dir"
    "_rac_wasm_offsetof_directory_entry_size_bytes"
    "_rac_wasm_sizeof_config"
    "_rac_wasm_offsetof_config_platform_adapter"
    "_rac_wasm_offsetof_config_log_level"
    "_rac_wasm_sizeof_llm_options"
    "_rac_wasm_sizeof_llm_result"
    "_rac_wasm_create_llm_options_default"
    "_rac_wasm_sizeof_stt_options"
    "_rac_wasm_sizeof_stt_result"
    "_rac_wasm_sizeof_tts_options"
    "_rac_wasm_sizeof_tts_result"
    "_rac_wasm_sizeof_vad_config"
    "_rac_wasm_sizeof_voice_agent_config"
    "_rac_wasm_sizeof_voice_agent_result"
    "_rac_wasm_sizeof_vlm_options"
    "_rac_wasm_sizeof_vlm_result"
    "_rac_wasm_sizeof_vlm_image"
    "_rac_wasm_sizeof_structured_output_config"
    "_rac_wasm_sizeof_diffusion_options"
    "_rac_wasm_sizeof_diffusion_result"
    "_rac_wasm_sizeof_embeddings_options"
    "_rac_wasm_sizeof_embeddings_result"

    # Dev config WASM wrappers
    "_rac_wasm_dev_config_is_available"
    "_rac_wasm_dev_config_get_supabase_url"
    "_rac_wasm_dev_config_get_supabase_key"
    "_rac_wasm_dev_config_get_build_token"

    # Emscripten runtime helpers
    "_malloc"
    "_free"
)

# =============================================================================
# BACKEND-SPECIFIC EXPORT LISTS
# =============================================================================
# Per-backend export deltas — only appended when the matching backend is being
# linked into a target. Each list is closed (no `if(RAC_WASM_*)` here; gating
# happens at target construction time).

set(RAC_EXPORTED_FUNCTIONS_LLAMACPP
    # LLM ops
    "_rac_llm_llamacpp_create"
    "_rac_llm_llamacpp_unload_model"
    "_rac_llm_llamacpp_is_model_loaded"
    "_rac_llm_llamacpp_generate"
    "_rac_llm_llamacpp_generate_stream"
    "_rac_llm_llamacpp_cancel"
    "_rac_llm_llamacpp_get_model_info"
    "_rac_llm_llamacpp_destroy"
    # VLM ops (vision-language is a modality of the same engine)
    "_rac_vlm_llamacpp_create"
    "_rac_vlm_llamacpp_load_model"
    "_rac_vlm_llamacpp_unload_model"
    "_rac_vlm_llamacpp_is_model_loaded"
    "_rac_vlm_llamacpp_process"
    "_rac_vlm_llamacpp_process_stream"
    "_rac_vlm_llamacpp_cancel"
    "_rac_vlm_llamacpp_get_model_info"
    "_rac_vlm_llamacpp_destroy"
    # Single unified register/unregister for the whole engine
    "_rac_backend_llamacpp_register"
    "_rac_backend_llamacpp_unregister"
)

set(RAC_EXPORTED_FUNCTIONS_ONNX
    # TTS (Piper via ONNX)
    "_rac_tts_onnx_create"
    "_rac_tts_onnx_synthesize"
    "_rac_tts_onnx_get_voices"
    "_rac_tts_onnx_stop"
    "_rac_tts_onnx_destroy"
    # VAD (Silero via ONNX)
    "_rac_vad_onnx_create"
    "_rac_vad_onnx_process"
    "_rac_vad_onnx_start"
    "_rac_vad_onnx_stop"
    "_rac_vad_onnx_reset"
    "_rac_vad_onnx_set_threshold"
    "_rac_vad_onnx_is_speech_active"
    "_rac_vad_onnx_destroy"
    "_rac_backend_onnx_register"
    "_rac_backend_onnx_unregister"
)

set(RAC_EXPORTED_FUNCTIONS_SHERPA
    "_rac_backend_sherpa_register"
    "_rac_backend_sherpa_unregister"
)

# cloud engine registration — the ONLINE side of the hybrid STT router.
# The cloud engine is lightweight (HTTP STT, no local runtime); under Emscripten
# RAC_STATIC_PLUGINS is forced ON, so its sources (incl. the register/unregister
# entry points) FOLD INTO rac_commons rather than a standalone
# rac_backend_cloud archive. We therefore only need to EXPORT the two entry
# symbols in the emitted JS glue; they resolve from rac_commons. Appended to the
# ONNX-sherpa target, which owns the offline sherpa STT side — so a single
# bundle can serve both router sides. (If a future non-static-plugin WASM build
# produces a standalone rac_backend_cloud target, the link guard below picks
# it up.)
set(RAC_EXPORTED_FUNCTIONS_CLOUD
    "_rac_backend_cloud_register"
    "_rac_backend_cloud_unregister"
)

# RAG generated-proto pipeline. The RAG OBJECT library folds into
# librac_commons whenever RAC_BACKEND_RAG=ON (default ON, gated to ONNX
# availability on Emscripten — see sdk/runanywhere-commons/CMakeLists.txt).
# RAG routes embeddings through the rac_embeddings_service vtable at runtime,
# so these exports are only meaningful on the ONNX-sherpa WASM target where
# the ONNX embedding provider is also linked. Appended to that target only.
set(RAC_EXPORTED_FUNCTIONS_RAG
    "_rac_rag_session_create_proto"
    "_rac_rag_session_destroy_proto"
    "_rac_rag_ingest_proto"
    "_rac_rag_query_proto"
    "_rac_rag_clear_proto"
    "_rac_rag_stats_proto"
)

# =============================================================================
# WebGPU/JSPI suspending-import list (shared by webgpu llamacpp variant)
# =============================================================================
# WASM export names do NOT have the leading underscore that
# -sEXPORTED_FUNCTIONS uses. The JSPI regex in the glue JS matches against
# the raw export names, so we must omit the underscore here.

set(RAC_JSPI_EXPORTS
    # Module init (static constructors probe for WebGPU adapter)
    "__wasm_call_ctors"
    # SDK init (rac_init may initialize GPU context)
    "rac_init"
    # Backend registration (may probe GPU capabilities) — unified register
    # covers both LLM and VLM modalities of the llama.cpp engine
    "rac_backend_llamacpp_register"
    # C++ lifecycle/model wrappers invoked directly from TypeScript.
    "rac_model_lifecycle_load_proto"
    "rac_model_lifecycle_unload_proto"
    # LLM lifecycle (GPU memory allocation / inference / cleanup)
    "rac_llm_component_create"
    "rac_llm_component_load_model"
    "rac_llm_component_generate"
    "rac_llm_component_generate_stream"
    "rac_llm_component_unload"
    "rac_llm_generate_proto"
    "rac_llm_generate_stream_proto"
    # VLM lifecycle (GPU memory allocation / inference / cleanup)
    "rac_vlm_component_create"
    "rac_vlm_component_load_model"
    "rac_vlm_component_process"
    "rac_vlm_component_process_stream"
    "rac_vlm_component_unload"
    "rac_vlm_process_proto"
    "rac_vlm_process_stream_proto"
)

# =============================================================================
# HELPER: rac_wasm_add_target
# =============================================================================
# Add one Emscripten executable target with a uniform shape. Each call
# produces a self-contained Emscripten module (.js + .wasm) staged into the
# matching npm package directory.
#
# Single-value args:
#   NAME              -- CMake target name (e.g. racommons_llamacpp_wasm)
#   OUTPUT_NAME       -- Emscripten output base (e.g. racommons-llamacpp)
#   OUTPUT_DIR        -- Final staging directory (post-build copy destination)
#   EXPORT_NAME       -- -sEXPORT_NAME= module factory (e.g. createLlamaCppModule)
#   ENABLE_WEBGPU     -- ON to add JSPI + WebGPU link flags (default OFF)
# Multi-value args:
#   LINK_LIBRARIES    -- CMake targets to PRIVATE link (rac_commons + backend archives)
#   EXPORTED_FUNCTIONS -- Final list of _rac_* exports for this target
#   COMPILE_DEFS      -- Extra target_compile_definitions (e.g. RAC_WASM_LLAMACPP=1)
#   EXTRA_LINK_FLAGS  -- Optional extra emcc link flags appended verbatim

function(rac_wasm_add_target)
    set(_oneValueArgs NAME OUTPUT_NAME OUTPUT_DIR EXPORT_NAME ENABLE_WEBGPU)
    set(_multiValueArgs LINK_LIBRARIES EXPORTED_FUNCTIONS COMPILE_DEFS EXTRA_LINK_FLAGS)
    cmake_parse_arguments(RWT "" "${_oneValueArgs}" "${_multiValueArgs}" ${ARGN})

    if(NOT RWT_NAME OR NOT RWT_OUTPUT_NAME OR NOT RWT_OUTPUT_DIR OR NOT RWT_EXPORT_NAME)
        message(FATAL_ERROR "rac_wasm_add_target: NAME, OUTPUT_NAME, OUTPUT_DIR, EXPORT_NAME are required")
    endif()
    if(NOT RWT_ENABLE_WEBGPU)
        set(RWT_ENABLE_WEBGPU OFF)
    endif()

    add_executable(${RWT_NAME}
        ${WASM_EXPORT_SOURCES}
        ${WASM_PLATFORM_SOURCES}
    )

    target_link_libraries(${RWT_NAME} PRIVATE ${RWT_LINK_LIBRARIES})

    target_include_directories(${RWT_NAME} PRIVATE
        ${RAC_COMMONS_DIR}/include
        ${RAC_COMMONS_DIR}/src
    )

    target_compile_definitions(${RWT_NAME} PRIVATE
        RAC_PLATFORM_WASM=1
        RAC_PLATFORM_NAME="Emscripten"
        # wasm_exports.cpp includes legacy internal event headers
        # (rac_analytics_events.h, rac_events.h) to keep the analytics/telemetry
        # bridge alive for in-process Web SDK shims. Marking the TU as internal
        # avoids the public-API #warning these headers emit.
        RAC_INTERNAL_TRANSLATION_UNIT=1
    )

    if(RWT_COMPILE_DEFS)
        target_compile_definitions(${RWT_NAME} PRIVATE ${RWT_COMPILE_DEFS})
    endif()

    # Build the comma-separated -sEXPORTED_FUNCTIONS=[...] argument.
    string(JOIN "," _exports_str ${RWT_EXPORTED_FUNCTIONS})

    # Identical memory layout for every WASM produced here so the TS layer
    # can host multiple modules side-by-side without per-package surprises.
    set(_link_flags
        # Output format
        "-sWASM=1"
        "-sMODULARIZE=1"
        "-sEXPORT_ES6=1"
        "-sEXPORT_NAME=${RWT_EXPORT_NAME}"
        "-sENVIRONMENT=web,worker"

        # Memory
        "-sALLOW_MEMORY_GROWTH=1"
        "-sINITIAL_MEMORY=33554432"    # 32 MB initial
        "-sMAXIMUM_MEMORY=4294967296"  # 4 GB max (needed for large VLM models + mmproj)
        "-sSTACK_SIZE=1048576"         # 1 MB stack

        # Function exports
        "-sEXPORTED_FUNCTIONS=[${_exports_str}]"
        "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE=\\$wasmTable"
        "-sEXPORTED_RUNTIME_METHODS=[\"ccall\",\"cwrap\",\"addFunction\",\"removeFunction\",\"wasmTable\",\"UTF8ToString\",\"stringToUTF8\",\"lengthBytesUTF8\",\"setValue\",\"getValue\",\"FS\",\"HEAPU8\",\"HEAP32\",\"HEAPU32\",\"HEAPF32\",\"wasmMemory\"]"

        # Allow JS function pointers (needed for platform adapter callbacks).
        # Web downloads are scheduled on the main Emscripten runtime so JS callback
        # pointers are invoked against the table that addFunction() mutates.
        "-sALLOW_TABLE_GROWTH=1"

        # Filesystem
        "-sFORCE_FILESYSTEM=1"

        # No auto-exit
        "-sNO_EXIT_RUNTIME=1"

        # Allow undefined symbols for stub builds (commons-only doesn't link
        # backend archives, so engine-specific symbols stay null at runtime
        # and the TS bridges already check for that).
        "-sERROR_ON_UNDEFINED_SYMBOLS=0"
        "-Wno-undefined"
    )

    # Exception model. WebGPU uses wasm-native exceptions (JSPI requirement);
    # everything else uses the classic JS-based mechanism.
    if(RWT_ENABLE_WEBGPU)
        # nothing — -fwasm-exceptions added below via EXTRA_LINK_FLAGS
    else()
        list(APPEND _link_flags "-sDISABLE_EXCEPTION_CATCHING=0")
    endif()

    # Threading (optional)
    if(RAC_WASM_PTHREADS)
        list(APPEND _link_flags
            "-pthread"
            "-sPTHREAD_POOL_SIZE=4"
            "-sPTHREAD_POOL_SIZE_STRICT=0"
        )
        target_compile_options(${RWT_NAME} PRIVATE "-pthread")
    endif()

    # WebGPU / JSPI (only for the llamacpp+webgpu variant)
    if(RWT_ENABLE_WEBGPU)
        string(JOIN "\",\"" _jspi_str ${RAC_JSPI_EXPORTS})
        list(APPEND _link_flags
            "-sJSPI"                     # Enable JSPI for async WebGPU calls from sync C
            # NOTE: Do NOT add -sASYNCIFY=0 here. -sJSPI internally sets ASYNCIFY=2;
            # an explicit ASYNCIFY=0 would override and disable JSPI.
            "-sJSPI_EXPORTS=[\"${_jspi_str}\"]"
            # Only wrap WebGPU-async imports with WebAssembly.Suspending so
            # sync imports (e.g. fd_write log lines emitted during model
            # loading) keep zero JSPI overhead.
            "-sJSPI_IMPORTS=[\"wgpuInstanceRequestAdapter\",\"wgpuAdapterRequestDevice\",\"wgpuBufferMapAsync\",\"wgpuDeviceCreateComputePipelineAsync\",\"wgpuDeviceCreateRenderPipelineAsync\",\"wgpuQueueOnSubmittedWorkDone\",\"wgpuInstanceProcessEvents\"]"
            "-fwasm-exceptions"          # WASM-native exceptions (required by JSPI)
        )
    endif()

    # Debug vs release
    if(RAC_WASM_DEBUG)
        list(APPEND _link_flags
            "-sASSERTIONS=2"
            "-sSAFE_HEAP=1"
            "-sSTACK_OVERFLOW_CHECK=2"
            "-g3"
        )
    else()
        list(APPEND _link_flags
            "-sASSERTIONS=0"
            "-O3"
        )
    endif()

    # Caller-supplied extras (rare — webgpu already handled above).
    if(RWT_EXTRA_LINK_FLAGS)
        list(APPEND _link_flags ${RWT_EXTRA_LINK_FLAGS})
    endif()

    string(JOIN " " _link_flags_str ${_link_flags})

    set_target_properties(${RWT_NAME} PROPERTIES
        LINK_FLAGS "${_link_flags_str}"
        OUTPUT_NAME "${RWT_OUTPUT_NAME}"
        SUFFIX ".js"
    )

    # =============================================================================
    # POST-BUILD: stage outputs into the matching npm package dir
    # =============================================================================
    add_custom_command(TARGET ${RWT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${RWT_OUTPUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy
            "$<TARGET_FILE_DIR:${RWT_NAME}>/${RWT_OUTPUT_NAME}.js"
            "${RWT_OUTPUT_DIR}/${RWT_OUTPUT_NAME}.js"
        COMMAND ${CMAKE_COMMAND} -E copy
            "$<TARGET_FILE_DIR:${RWT_NAME}>/${RWT_OUTPUT_NAME}.wasm"
            "${RWT_OUTPUT_DIR}/${RWT_OUTPUT_NAME}.wasm"
        COMMENT "Copying ${RWT_OUTPUT_NAME} WASM outputs to ${RWT_OUTPUT_DIR}"
    )

    # Pthread worker staging policy (mirrored by wasm/scripts/build.sh):
    #   * Emscripten <5.x : toolchain emits a separate `<output>.worker.js` next
    #     to the main glue. The companion MUST be present; missing it is a real
    #     bug (linker dropped pthread output) and we hard-fail the build.
    #   * Emscripten >=5.x: toolchain bundles the pthread worker into the main
    #     .js file, so no companion file is produced. Tolerate its absence.
    if(RAC_WASM_PTHREADS)
        if(DEFINED CMAKE_C_COMPILER_VERSION
           AND CMAKE_C_COMPILER_VERSION VERSION_GREATER_EQUAL "5.0")
            add_custom_command(TARGET ${RWT_NAME} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E env bash -c
                    "if [ -f '$<TARGET_FILE_DIR:${RWT_NAME}>/${RWT_OUTPUT_NAME}.worker.js' ]; then \
                       cp '$<TARGET_FILE_DIR:${RWT_NAME}>/${RWT_OUTPUT_NAME}.worker.js' '${RWT_OUTPUT_DIR}/${RWT_OUTPUT_NAME}.worker.js'; \
                       echo 'Staged pthread worker companion'; \
                     else \
                       echo 'No separate .worker.js (Emscripten >=5.x bundles into main glue)'; \
                     fi"
                COMMENT "Staging ${RWT_OUTPUT_NAME}.worker.js if present (Emscripten >=5.x bundles into main glue)"
                VERBATIM
            )
        else()
            add_custom_command(TARGET ${RWT_NAME} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy
                    "$<TARGET_FILE_DIR:${RWT_NAME}>/${RWT_OUTPUT_NAME}.worker.js"
                    "${RWT_OUTPUT_DIR}/${RWT_OUTPUT_NAME}.worker.js"
                COMMENT "Copying ${RWT_OUTPUT_NAME}.worker.js (Emscripten <5.x always emits a companion worker)"
            )
        endif()
    endif()
endfunction()

# =============================================================================
# TARGET CONSTRUCTION
# =============================================================================
# One CMake target per Web SDK npm package WASM artifact + an optional WebGPU
# variant of the llamacpp target.

set(_CORE_OUTPUT_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/../packages/core/wasm")
set(_LLAMACPP_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../packages/llamacpp/wasm")
set(_ONNX_OUTPUT_DIR     "${CMAKE_CURRENT_SOURCE_DIR}/../packages/onnx/wasm")

set(_targets_built "")

# --- Core (commons-only) -----------------------------------------------------
if(RAC_WASM_BUILD_CORE)
    rac_wasm_add_target(
        NAME racommons_core_wasm
        OUTPUT_NAME racommons
        OUTPUT_DIR "${_CORE_OUTPUT_DIR}"
        EXPORT_NAME createRACommonsCoreModule
        LINK_LIBRARIES rac_commons
        EXPORTED_FUNCTIONS ${RAC_EXPORTED_FUNCTIONS_BASE}
    )
    list(APPEND _targets_built "racommons_core_wasm -> packages/core/wasm/racommons.{js,wasm}")
endif()

# --- llama.cpp (LLM + VLM) ---------------------------------------------------
if(RAC_WASM_LLAMACPP)
    set(_llamacpp_exports ${RAC_EXPORTED_FUNCTIONS_BASE})
    list(APPEND _llamacpp_exports ${RAC_EXPORTED_FUNCTIONS_LLAMACPP})

    # When RAG is enabled on the llamacpp WASM target
    # (e.g. via build.sh --rag for the auto-loaded Docs/RAG bundle), append the
    # rac_rag_*_proto exports so the TS proto-byte bridge can reach the symbols.
    # The RAG OBJECT library has already been folded into librac_commons by
    # sdk/runanywhere-commons/CMakeLists.txt — we just need to expose the
    # 6 rac_rag_*_proto symbols in the emitted JS glue. The runtime layer
    # returns RAC_ERROR_FEATURE_NOT_AVAILABLE if no embeddings provider is
    # registered (matches the non-WASM platform contract).
    if(RAC_BACKEND_RAG)
        list(APPEND _llamacpp_exports ${RAC_EXPORTED_FUNCTIONS_RAG})
    endif()

    # cloud — the ONLINE side of the hybrid STT router. The llamacpp Web target
    # is the default Web WASM bundle (LLM + VLM + the hybrid STT router that
    # lives in rac_commons), and the hybrid router's online leg routes through
    # the "cloud" engine over the existing JS fetch transport. The cloud sources
    # fold into rac_commons under RAC_STATIC_PLUGINS=ON (forced for WASM — see
    # engines/cloud/CMakeLists.txt), so rac_backend_cloud_register resolves from
    # the already-linked librac_commons.a; we only need to EXPORT the two entry
    # symbols in the emitted JS glue so dead-strip keeps them and CloudSTT.ts can
    # call _rac_backend_cloud_register. (Mirrors the same append on the ONNX
    # target below; the standalone-target link guard is defensive for a future
    # non-static-plugin WASM build.)
    list(APPEND _llamacpp_exports ${RAC_EXPORTED_FUNCTIONS_CLOUD})
    set(_llamacpp_libs rac_commons rac_backend_llamacpp)
    if(TARGET rac_backend_cloud)
        list(APPEND _llamacpp_libs rac_backend_cloud)
    endif()

    if(NOT RAC_WASM_WEBGPU)
        # CPU variant — keep EXPORT_NAME=createLlamaCppModule for backward
        # compatibility with the existing TS bridge.
        rac_wasm_add_target(
            NAME racommons_llamacpp_wasm
            OUTPUT_NAME racommons-llamacpp
            OUTPUT_DIR "${_LLAMACPP_OUTPUT_DIR}"
            EXPORT_NAME createLlamaCppModule
            LINK_LIBRARIES ${_llamacpp_libs}
            EXPORTED_FUNCTIONS ${_llamacpp_exports}
            COMPILE_DEFS RAC_WASM_LLAMACPP=1
        )
        list(APPEND _targets_built "racommons_llamacpp_wasm -> packages/llamacpp/wasm/racommons-llamacpp.{js,wasm}")
    else()
        # WebGPU variant. Configures one build dir per variant; do not also
        # build the CPU artifact in the same configure (build script handles
        # that by re-invoking cmake without --webgpu).
        rac_wasm_add_target(
            NAME racommons_llamacpp_webgpu_wasm
            OUTPUT_NAME racommons-llamacpp-webgpu
            OUTPUT_DIR "${_LLAMACPP_OUTPUT_DIR}"
            EXPORT_NAME createLlamaCppWebGPUModule
            LINK_LIBRARIES ${_llamacpp_libs}
            EXPORTED_FUNCTIONS ${_llamacpp_exports}
            COMPILE_DEFS RAC_WASM_LLAMACPP=1 RAC_WASM_WEBGPU=1 GGML_USE_WEBGPU=1
            ENABLE_WEBGPU ON
        )
        list(APPEND _targets_built "racommons_llamacpp_webgpu_wasm -> packages/llamacpp/wasm/racommons-llamacpp-webgpu.{js,wasm}")
    endif()
endif()

# --- ONNX + Sherpa (STT/TTS/VAD) ---------------------------------------------
if(RAC_WASM_ONNX)
    set(_onnx_exports ${RAC_EXPORTED_FUNCTIONS_BASE})
    list(APPEND _onnx_exports ${RAC_EXPORTED_FUNCTIONS_ONNX})

    set(_onnx_libs rac_commons rac_backend_onnx)
    if(TARGET rac_backend_sherpa)
        list(APPEND _onnx_libs rac_backend_sherpa)
        list(APPEND _onnx_exports ${RAC_EXPORTED_FUNCTIONS_SHERPA})
    endif()

    # cloud — the online side of the hybrid STT router. Always export its
    # register/unregister symbols on this target (the offline-STT owner) so a
    # single bundle can drive both router sides. Under Emscripten the cloud
    # sources fold into rac_commons (RAC_STATIC_PLUGINS forced ON), so no extra
    # link is required; the link below is a defensive guard for any future build
    # that produces a standalone rac_backend_cloud target.
    list(APPEND _onnx_exports ${RAC_EXPORTED_FUNCTIONS_CLOUD})
    if(TARGET rac_backend_cloud)
        list(APPEND _onnx_libs rac_backend_cloud)
    endif()

    # RAG proto-byte exports: the ONNX target also ships RAG so the same
    # bundle can serve embeddings via the ONNX provider. (The llamacpp target
    # above receives the same exports when RAC_BACKEND_RAG=ON.)
    if(RAC_BACKEND_RAG)
        list(APPEND _onnx_exports ${RAC_EXPORTED_FUNCTIONS_RAG})
    endif()

    rac_wasm_add_target(
        NAME racommons_onnx_wasm
        OUTPUT_NAME racommons-onnx-sherpa
        OUTPUT_DIR "${_ONNX_OUTPUT_DIR}"
        EXPORT_NAME createRACommonsONNXModule
        LINK_LIBRARIES ${_onnx_libs}
        EXPORTED_FUNCTIONS ${_onnx_exports}
        COMPILE_DEFS RAC_WASM_ONNX=1
    )
    list(APPEND _targets_built "racommons_onnx_wasm -> packages/onnx/wasm/racommons-onnx-sherpa.{js,wasm}")
endif()

if(NOT _targets_built)
    message(FATAL_ERROR
        "No WASM targets configured. Enable at least one of:\n"
        "  -DRAC_WASM_BUILD_CORE=ON\n"
        "  -DRAC_WASM_LLAMACPP=ON  (optionally with -DRAC_WASM_WEBGPU=ON)\n"
        "  -DRAC_WASM_ONNX=ON"
    )
endif()

# =============================================================================
# SUMMARY
# =============================================================================

message(STATUS "")
message(STATUS "====================================")
message(STATUS "RunAnywhere Web WASM Build")
message(STATUS "====================================")
message(STATUS "RACommons:    ${RAC_COMMONS_DIR}")
message(STATUS "pthreads:     ${RAC_WASM_PTHREADS}")
message(STATUS "Debug:        ${RAC_WASM_DEBUG}")
message(STATUS "Core target:  ${RAC_WASM_BUILD_CORE}")
message(STATUS "llama.cpp:    ${RAC_WASM_LLAMACPP}")
message(STATUS "WebGPU:       ${RAC_WASM_WEBGPU}")
message(STATUS "sherpa-onnx:  ${RAC_WASM_ONNX}")
message(STATUS "Targets:")
foreach(_t ${_targets_built})
    message(STATUS "  ${_t}")
endforeach()
message(STATUS "====================================")
message(STATUS "")
