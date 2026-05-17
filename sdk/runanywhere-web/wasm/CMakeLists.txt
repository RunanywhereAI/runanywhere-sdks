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

option(RAC_WASM_PTHREADS "Enable pthreads (requires SharedArrayBuffer)" OFF)
option(RAC_WASM_DEBUG "Enable debug assertions and verbose logging" OFF)
option(RAC_WASM_LLAMACPP "Build with llama.cpp LLM backend" OFF)
option(RAC_WASM_VLM "Build with VLM (Vision Language Model) support via llama.cpp mtmd" OFF)
option(RAC_WASM_WHISPERCPP "Build with whisper.cpp STT backend" OFF)
option(RAC_WASM_ONNX "Build with sherpa-onnx TTS/VAD backend" OFF)
option(RAC_WASM_WEBGPU "Enable WebGPU acceleration for llama.cpp (requires JSPI-capable browser)" OFF)

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

# Enable backends based on options
if(RAC_WASM_LLAMACPP OR RAC_WASM_WHISPERCPP OR RAC_WASM_ONNX)
    set(RAC_BUILD_BACKENDS ON CACHE BOOL "" FORCE)
else()
    set(RAC_BUILD_BACKENDS OFF CACHE BOOL "" FORCE)
endif()

# Individual backend flags
set(RAC_BACKEND_LLAMACPP ${RAC_WASM_LLAMACPP} CACHE BOOL "" FORCE)
set(RAC_BACKEND_WHISPERCPP ${RAC_WASM_WHISPERCPP} CACHE BOOL "" FORCE)
set(RAC_BACKEND_ONNX ${RAC_WASM_ONNX} CACHE BOOL "" FORCE)

# VLM support via llama.cpp mtmd (multimodal vision encoder)
if(RAC_WASM_VLM AND RAC_WASM_LLAMACPP)
    set(RAC_VLM_USE_MTMD ON CACHE BOOL "" FORCE)
    message(STATUS "VLM multimodal support ENABLED via mtmd (CLIP/SigLIP)")
else()
    set(RAC_VLM_USE_MTMD OFF CACHE BOOL "" FORCE)
    if(RAC_WASM_VLM AND NOT RAC_WASM_LLAMACPP)
        message(WARNING "VLM requires llama.cpp backend (--llamacpp). Disabling VLM.")
    endif()
endif()

# =============================================================================
# BACKEND-SPECIFIC CONFIGURATION
# =============================================================================
# IMPORTANT: These must be set BEFORE add_subdirectory() so that llama.cpp,
# whisper.cpp, and ONNX CMake files see the correct cache variables.

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

    # WebGPU acceleration (optional, produces separate build variant)
    if(RAC_WASM_WEBGPU)
        message(STATUS "WebGPU acceleration ENABLED for llama.cpp")
        set(GGML_WEBGPU ON CACHE BOOL "" FORCE)
        # JSPI bridges async WebGPU calls from synchronous C code
        set(GGML_WEBGPU_JSPI ON CACHE BOOL "" FORCE)
        set(WASM_OUTPUT_NAME "racommons-llamacpp-webgpu")
    else()
        set(GGML_WEBGPU OFF CACHE BOOL "" FORCE)
        set(WASM_OUTPUT_NAME "racommons-llamacpp")
    endif()

    # Disable wasm64 / MEMORY64 mode -- not yet widely supported in browsers
    # and causes wasm32/wasm64 linker mismatch with our main module
    set(LLAMA_WASM_MEM64 OFF CACHE BOOL "" FORCE)

    # Disable llama.cpp HTML output and single-file embedding
    set(LLAMA_BUILD_HTML OFF CACHE BOOL "" FORCE)
    set(LLAMA_WASM_SINGLE_FILE OFF CACHE BOOL "" FORCE)
endif()

if(RAC_WASM_WHISPERCPP)
    message(STATUS "Building with whisper.cpp STT backend for WASM")

    # whisper.cpp shares the same GGML config as llama.cpp
    set(GGML_METAL OFF CACHE BOOL "" FORCE)
    set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
    set(GGML_CUDA OFF CACHE BOOL "" FORCE)
    set(GGML_ACCELERATE OFF CACHE BOOL "" FORCE)
    set(GGML_NEON OFF CACHE BOOL "" FORCE)
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

    # Disable CoreML for whisper.cpp on WASM
    set(WHISPER_COREML OFF CACHE BOOL "" FORCE)
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
if(RAC_WASM_WEBGPU)
    add_compile_options("-fwasm-exceptions")
else()
    add_compile_options("-fexceptions")
endif()

# This target is wired from the repo-root CMakeLists after rac_commons and the
# selected engine plugins have already been configured. Keep it in that build
# graph so the wrapper never falls back to Emscripten's default `a.out.*`
# output or an engine-less commons-only build.
if(NOT TARGET rac_commons)
    message(FATAL_ERROR
        "runanywhere_wasm must be configured from the repository root.\n"
        "Use: cmake --preset wasm && cmake --build --preset wasm --target runanywhere_wasm"
    )
endif()

if(RAC_WASM_LLAMACPP AND NOT TARGET rac_backend_llamacpp)
    message(FATAL_ERROR "RAC_WASM_LLAMACPP=ON requires rac_backend_llamacpp. Configure the root build with llama.cpp enabled.")
endif()
if(RAC_WASM_WHISPERCPP AND NOT TARGET rac_backend_whispercpp)
    message(FATAL_ERROR "RAC_WASM_WHISPERCPP=ON requires rac_backend_whispercpp. Configure the root build with whisper.cpp enabled.")
endif()
if(RAC_WASM_ONNX AND NOT TARGET rac_backend_onnx)
    message(FATAL_ERROR
        "RAC_WASM_ONNX=ON requires rac_backend_onnx (embeddings + generic ORT services). "
        "Configure the root build with ONNX enabled. "
        "Note: under Emscripten, engines/onnx requires the vendored static archive at "
        "sdk/runanywhere-commons/third_party/onnxruntime-wasm/lib/libonnxruntime.a. "
        "See CPP-13 / WEB-01 and thoughts/shared/plans/wasm_onnx_unblock.md."
    )
endif()
# Sherpa backend provides STT/TTS/VAD under the ONNX umbrella on WASM.
# It's optional: the build continues when the vendored Sherpa archives
# aren't present, but STT/TTS/VAD routing will return BackendNotAvailable
# at runtime. See CPP-13 / WEB-01.
if(RAC_WASM_ONNX AND NOT TARGET rac_backend_sherpa)
    message(STATUS
        "RAC_WASM_ONNX=ON: rac_backend_sherpa not available (no vendored "
        "sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/ archives). "
        "STT/TTS/VAD calls will return BackendNotAvailable. "
        "See CPP-13 / WEB-01 and thoughts/shared/plans/wasm_onnx_unblock.md."
    )
endif()

# =============================================================================
# WASM PLATFORM SHIMS
# =============================================================================

# Platform-specific shims for Emscripten (backtrace, platform detection, etc.)
set(WASM_PLATFORM_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/platform/wasm_platform_shims.cpp
)

# =============================================================================
# WASM EXPORTS MODULE
# =============================================================================

set(WASM_EXPORT_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/src/wasm_exports.cpp
)

# =============================================================================
# EXPORTED FUNCTIONS
# =============================================================================
# All rac_* C API functions that need to be callable from JavaScript.
# Prefix each with underscore for Emscripten convention.

set(RAC_EXPORTED_FUNCTIONS
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

    # HTTP client / download (T3.13 — Web SDK migration off hand-rolled
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

    # Platform HTTP transport registry (v2 close-out Phase H2 / H7). The
    # WASM shim in rac_http_client_emscripten.cpp registers an
    # emscripten_fetch()-backed adapter via this vtable so the router in
    # rac_http_client_curl.cpp short-circuits to it. TypeScript side calls
    # _rac_http_transport_register_emscripten() once after module load.
    "_rac_http_transport_register"
    "_rac_http_transport_is_registered"
    "_rac_http_transport_register_emscripten"
    # Stage 3d: JS-side adapter registration. JS provides function-table
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

    # Module registry
    "_rac_module_register"
    "_rac_module_unregister"
    "_rac_module_list"
    "_rac_modules_for_capability"
    "_rac_module_get_info"

    # Plugin registry / loader
    "_rac_plugin_api_version"
    "_rac_registry_load_plugin"
    "_rac_registry_unload_plugin"
    "_rac_registry_plugin_count"
    "_rac_registry_list_plugins"
    "_rac_registry_free_plugin_list"

    # Service registry
    # v3.0.0 (C1): rac_service_* legacy exports DELETED. Use rac_plugin_*
    # from rac/plugin/rac_plugin_entry.h and rac/router/rac_route.h.

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
    "_rac_model_registry_refresh"
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
    # pass2-syn-026: Session-based orchestration so the Web SDK can delegate
    # the tool-calling run loop to commons even when TS executors are async
    # (the run-loop-proto callback is synchronous and cannot await a JS Promise).
    "_rac_tool_calling_session_create_proto"
    "_rac_tool_calling_session_step_with_result_proto"
    "_rac_tool_calling_session_destroy_proto"
    # pass2-syn-007: cancel ABI so AbortSignal-driven Web hosts can interrupt
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
    # pass2-syn-002: rac_vad_{start,stop,reset} bare-service decls deleted;
    # use rac_vad_component_{start,stop,reset} / *_lifecycle_proto.
    "_rac_vad_component_start"
    "_rac_vad_component_stop"
    "_rac_vad_component_reset"
    "_rac_vad_pause"
    "_rac_vad_resume"
    "_rac_vad_process_samples"
    "_rac_vad_set_energy_threshold"
    "_rac_vad_get_info"
    "_rac_vad_destroy"

    # VAD component
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

    # Voice Agent — proto-byte streaming ABI (GAP 09 Phase 15 / v3 Phase A4)
    # Required by sdk/runanywhere-web/packages/core/src/Adapters/
    # VoiceAgentStreamAdapter.ts, which calls it through
    # m._rac_voice_agent_set_proto_callback(handle, cbPtr, 0). Pair with
    # -sEXPORTED_RUNTIME_METHODS=['addFunction','removeFunction'] +
    # -sALLOW_TABLE_GROWTH=1 (already enabled in this target).
    "_rac_voice_agent_set_proto_callback"
    "_rac_voice_agent_initialize_proto"
    "_rac_voice_agent_component_states_proto"
    "_rac_voice_agent_process_voice_turn_proto"

    # Solutions runtime (rac/solutions/rac_solution.h) — T4.7 / T4.8.
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

    # RAG generated-proto pipeline
    "_rac_rag_session_create_proto"
    "_rac_rag_session_destroy_proto"
    "_rac_rag_ingest_proto"
    "_rac_rag_query_proto"
    "_rac_rag_clear_proto"
    "_rac_rag_stats_proto"

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
    "_rac_telemetry_manager_track_analytics"
    "_rac_telemetry_manager_http_complete"
    "_rac_telemetry_manager_flush"
    "_rac_telemetry_payload_default"
    "_rac_telemetry_payload_free"

    # Analytics Events
    "_rac_analytics_events_set_callback"
    "_rac_analytics_events_has_callback"

    # Platform Emit Helpers (called from TypeScript via ccall for STT/TTS/VAD/download events)
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
    # BUG-WEB-003 (resolved): These MUST ship in BOTH CPU and WebGPU variants.
    # The pre-9226feb2c WebGPU artifact predated these helpers, which caused
    # PlatformAdapter.register() to throw and LlamaCppBridge.ts to silently
    # fall back to CPU. Always rebuild `racommons-llamacpp-webgpu.{js,wasm}`
    # alongside the CPU variant via `./wasm/scripts/build.sh --llamacpp --webgpu`
    # whenever this list or wasm/src/wasm_exports.cpp changes.
    "_rac_wasm_offsetof_platform_adapter_file_exists"
    "_rac_wasm_offsetof_platform_adapter_file_read"
    "_rac_wasm_offsetof_platform_adapter_file_write"
    "_rac_wasm_offsetof_platform_adapter_file_delete"
    "_rac_wasm_offsetof_platform_adapter_secure_get"
    "_rac_wasm_offsetof_platform_adapter_secure_set"
    "_rac_wasm_offsetof_platform_adapter_secure_delete"
    "_rac_wasm_offsetof_platform_adapter_log"
    "_rac_wasm_offsetof_platform_adapter_track_error"
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

# Add llama.cpp backend exports if enabled
if(RAC_WASM_LLAMACPP)
    list(APPEND RAC_EXPORTED_FUNCTIONS
        "_rac_llm_llamacpp_create"
        "_rac_llm_llamacpp_unload_model"
        "_rac_llm_llamacpp_is_model_loaded"
        "_rac_llm_llamacpp_generate"
        "_rac_llm_llamacpp_generate_stream"
        "_rac_llm_llamacpp_cancel"
        "_rac_llm_llamacpp_get_model_info"
        "_rac_llm_llamacpp_destroy"
        "_rac_backend_llamacpp_register"
        "_rac_backend_llamacpp_unregister"
    )
endif()

# Add llama.cpp VLM backend exports if enabled
if(RAC_WASM_VLM AND RAC_WASM_LLAMACPP)
    list(APPEND RAC_EXPORTED_FUNCTIONS
        "_rac_vlm_llamacpp_create"
        "_rac_vlm_llamacpp_load_model"
        "_rac_vlm_llamacpp_unload_model"
        "_rac_vlm_llamacpp_is_model_loaded"
        "_rac_vlm_llamacpp_process"
        "_rac_vlm_llamacpp_process_stream"
        "_rac_vlm_llamacpp_cancel"
        "_rac_vlm_llamacpp_get_model_info"
        "_rac_vlm_llamacpp_destroy"
        "_rac_backend_llamacpp_vlm_register"
        "_rac_backend_llamacpp_vlm_unregister"
    )
endif()

# Add whisper.cpp backend exports if enabled
if(RAC_WASM_WHISPERCPP)
    list(APPEND RAC_EXPORTED_FUNCTIONS
        "_rac_stt_whispercpp_create"
        "_rac_stt_whispercpp_transcribe"
        "_rac_stt_whispercpp_get_language"
        "_rac_stt_whispercpp_is_ready"
        "_rac_stt_whispercpp_destroy"
        "_rac_backend_whispercpp_register"
        "_rac_backend_whispercpp_unregister"
    )
endif()

# Add sherpa-onnx backend exports if enabled (TTS + VAD)
if(RAC_WASM_ONNX)
    list(APPEND RAC_EXPORTED_FUNCTIONS
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
    # Sherpa backend (STT/TTS/VAD via Sherpa-ONNX C API) exports are added
    # when the rac_backend_sherpa target was configured by the root build.
    # See CPP-13 / WEB-01 — requires the vendored WASM static archives at
    # sdk/runanywhere-commons/third_party/sherpa-onnx-wasm/.
    if(TARGET rac_backend_sherpa)
        list(APPEND RAC_EXPORTED_FUNCTIONS
            "_rac_backend_sherpa_register"
            "_rac_backend_sherpa_unregister"
        )
    endif()
endif()

# Join into a comma-separated list for Emscripten
string(JOIN "," RAC_EXPORTED_FUNCTIONS_STR ${RAC_EXPORTED_FUNCTIONS})

# =============================================================================
# WASM BUILD TARGET
# =============================================================================

add_executable(runanywhere_wasm
    ${WASM_EXPORT_SOURCES}
    ${WASM_PLATFORM_SOURCES}
)

target_link_libraries(runanywhere_wasm PRIVATE rac_commons)

if(RAC_WASM_LLAMACPP)
    target_link_libraries(runanywhere_wasm PRIVATE rac_backend_llamacpp)
endif()

if(RAC_WASM_WHISPERCPP)
    target_link_libraries(runanywhere_wasm PRIVATE rac_backend_whispercpp)
endif()

if(RAC_WASM_ONNX)
    target_link_libraries(runanywhere_wasm PRIVATE rac_backend_onnx)
    # Sherpa STT/TTS/VAD backend links in when its target was configured by
    # the root build (requires vendored WASM static archives — see CPP-13 /
    # WEB-01).
    if(TARGET rac_backend_sherpa)
        target_link_libraries(runanywhere_wasm PRIVATE rac_backend_sherpa)
    endif()
endif()

target_include_directories(runanywhere_wasm PRIVATE
    ${RAC_COMMONS_DIR}/include
    ${RAC_COMMONS_DIR}/src
)

# Emscripten compile definitions
target_compile_definitions(runanywhere_wasm PRIVATE
    RAC_PLATFORM_WASM=1
    RAC_PLATFORM_NAME="Emscripten"
    # WASM exports include legacy internal event headers
    # (rac_analytics_events.h, rac_events.h) to keep the analytics/telemetry
    # bridge alive for in-process Web SDK shims. Marking the TU as internal
    # avoids the public-API #warning these headers emit.
    RAC_INTERNAL_TRANSLATION_UNIT=1
)


if(RAC_WASM_LLAMACPP)
    target_compile_definitions(runanywhere_wasm PRIVATE RAC_WASM_LLAMACPP=1)
endif()

if(RAC_WASM_WEBGPU AND RAC_WASM_LLAMACPP)
    target_compile_definitions(runanywhere_wasm PRIVATE RAC_WASM_WEBGPU=1 GGML_USE_WEBGPU=1)
endif()

if(RAC_WASM_VLM AND RAC_WASM_LLAMACPP)
    target_compile_definitions(runanywhere_wasm PRIVATE RAC_WASM_VLM=1)
endif()

if(RAC_WASM_WHISPERCPP)
    target_compile_definitions(runanywhere_wasm PRIVATE RAC_WASM_WHISPERCPP=1)
endif()

if(RAC_WASM_ONNX)
    target_compile_definitions(runanywhere_wasm PRIVATE RAC_WASM_ONNX=1)
endif()

# =============================================================================
# EMSCRIPTEN LINKER FLAGS
# =============================================================================

set(EMSCRIPTEN_LINK_FLAGS
    # Output format
    "-sWASM=1"
    "-sMODULARIZE=1"
    "-sEXPORT_ES6=1"
    "-sEXPORT_NAME=createLlamaCppModule"
    "-sENVIRONMENT=web,worker"

    # Memory
    "-sALLOW_MEMORY_GROWTH=1"
    "-sINITIAL_MEMORY=33554432"    # 32 MB initial
    "-sMAXIMUM_MEMORY=4294967296"  # 4 GB max (needed for large VLM models + mmproj)
    "-sSTACK_SIZE=1048576"         # 1 MB stack

    # Function exports
    "-sEXPORTED_FUNCTIONS=[${RAC_EXPORTED_FUNCTIONS_STR}]"
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

    # Error handling (overridden below for WebGPU builds)
    "-sDISABLE_EXCEPTION_CATCHING=0"

    # Allow undefined symbols for core-only builds (feature stubs).
    # Functions that don't exist will be null at runtime; the TypeScript
    # wrappers already check for this and throw descriptive errors.
    "-sERROR_ON_UNDEFINED_SYMBOLS=0"
    "-Wno-undefined"
)

# Threading (optional)
if(RAC_WASM_PTHREADS)
    list(APPEND EMSCRIPTEN_LINK_FLAGS
        "-pthread"
        "-sPTHREAD_POOL_SIZE=4"
        "-sPTHREAD_POOL_SIZE_STRICT=0"
    )
    target_compile_options(runanywhere_wasm PRIVATE "-pthread")
    message(STATUS "pthreads ENABLED (requires Cross-Origin Isolation headers)")
else()
    message(STATUS "pthreads DISABLED (single-threaded mode)")
endif()

# WebGPU / JSPI (optional, for GPU-accelerated LLM inference)
if(RAC_WASM_WEBGPU AND RAC_WASM_LLAMACPP)
    # JSPI + wasm-exceptions replace the older JS-based exception mechanism.
    # Remove the conflicting flag and replace it.
    list(REMOVE_ITEM EMSCRIPTEN_LINK_FLAGS "-sDISABLE_EXCEPTION_CATCHING=0")
    # Only the functions that may suspend during WebGPU operations are
    # listed in JSPI_EXPORTS.  Everything else stays synchronous so that
    # direct calls like m._rac_wasm_ping() keep returning plain numbers.
    #
    # NOTE: WASM export names do NOT have the leading underscore that
    # -sEXPORTED_FUNCTIONS uses.  The JSPI regex in the glue JS matches
    # against the raw export names, so we must omit the underscore here.
    set(RAC_JSPI_EXPORTS
        # Module init (static constructors probe for WebGPU adapter)
        "__wasm_call_ctors"
        # SDK init (rac_init may initialize GPU context)
        "rac_init"
        # Backend registration (may probe GPU capabilities)
        "rac_backend_llamacpp_register"
        "rac_backend_llamacpp_vlm_register"
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
    string(JOIN "\",\"" RAC_JSPI_EXPORTS_STR ${RAC_JSPI_EXPORTS})

    list(APPEND EMSCRIPTEN_LINK_FLAGS
        "-sJSPI"                     # Enable JSPI for async WebGPU calls from sync C
        # NOTE: Do NOT add -sASYNCIFY=0 here. -sJSPI internally sets ASYNCIFY=2;
        # an explicit ASYNCIFY=0 would override and disable JSPI.
        "-sJSPI_EXPORTS=[\"${RAC_JSPI_EXPORTS_STR}\"]"
        # Only wrap WebGPU-async imports with WebAssembly.Suspending.
        #
        # Using ["*"] wraps ALL imports (including synchronous ones like
        # fd_write for stderr logging).  During model loading, llama.cpp
        # prints hundreds of log lines via fd_write between WebGPU buffer
        # operations.  The mix of synchronous Suspending-wrapped imports
        # and actual async suspensions causes V8 to report
        # "trying to suspend JS frames" because the synchronous wrappers
        # leave transient JS frames on the JSPI stack.
        #
        # By limiting JSPI_IMPORTS to only the WebGPU functions that
        # actually return Promises (adapter/device request, buffer map,
        # queue sync), fd_write and other synchronous imports remain
        # plain JS calls with no JSPI overhead.
        "-sJSPI_IMPORTS=[\"wgpuInstanceRequestAdapter\",\"wgpuAdapterRequestDevice\",\"wgpuBufferMapAsync\",\"wgpuDeviceCreateComputePipelineAsync\",\"wgpuDeviceCreateRenderPipelineAsync\",\"wgpuQueueOnSubmittedWorkDone\",\"wgpuInstanceProcessEvents\"]"
        "-fwasm-exceptions"          # WASM-native exceptions (required by JSPI)
    )
    message(STATUS "WebGPU + JSPI ENABLED (requires Chrome 113+ / Edge 113+)")
endif()

# Debug mode
if(RAC_WASM_DEBUG)
    list(APPEND EMSCRIPTEN_LINK_FLAGS
        "-sASSERTIONS=2"
        "-sSAFE_HEAP=1"
        "-sSTACK_OVERFLOW_CHECK=2"
        "-g3"
    )
    message(STATUS "Debug mode ENABLED")
else()
    list(APPEND EMSCRIPTEN_LINK_FLAGS
        "-sASSERTIONS=0"
        "-O3"
    )
    # Keep Emscripten runtime object member names stable. The Web SDK's
    # platform adapter and VLM worker bridge call FS.readFile/writeFile/
    # analyzePath directly to mirror native filesystem callbacks.
    message(STATUS "Release mode (optimized)")
endif()

# Join flags
string(JOIN " " EMSCRIPTEN_LINK_FLAGS_STR ${EMSCRIPTEN_LINK_FLAGS})

# Determine output file name (racommons or racommons-webgpu)
if(NOT DEFINED WASM_OUTPUT_NAME)
    set(WASM_OUTPUT_NAME "racommons-llamacpp")
endif()

set_target_properties(runanywhere_wasm PROPERTIES
    LINK_FLAGS "${EMSCRIPTEN_LINK_FLAGS_STR}"
    OUTPUT_NAME "${WASM_OUTPUT_NAME}"
    SUFFIX ".js"
)

# =============================================================================
# POST-BUILD: Copy outputs to packages/core/wasm/
# =============================================================================

set(WASM_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../packages/llamacpp/wasm")

add_custom_command(TARGET runanywhere_wasm POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${WASM_OUTPUT_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy
        "${CMAKE_CURRENT_BINARY_DIR}/${WASM_OUTPUT_NAME}.js"
        "${WASM_OUTPUT_DIR}/${WASM_OUTPUT_NAME}.js"
    COMMAND ${CMAKE_COMMAND} -E copy
        "${CMAKE_CURRENT_BINARY_DIR}/${WASM_OUTPUT_NAME}.wasm"
        "${WASM_OUTPUT_DIR}/${WASM_OUTPUT_NAME}.wasm"
    COMMENT "Copying ${WASM_OUTPUT_NAME} WASM outputs to packages/llamacpp/wasm/"
)

# When pthreads are enabled with older Emscripten (<5.x), the toolchain emits
# a separate `<output>.worker.js` next to the main glue. Emscripten 5.x bundles
# the pthread worker into the main .js file, so the companion file may or may
# not exist. Copy it post-build IF PRESENT, no-op otherwise. This keeps the
# package layout correct for both toolchain generations without failing on the
# 5.x bundled-worker path.
if(RAC_WASM_PTHREADS)
    add_custom_command(TARGET runanywhere_wasm POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E env bash -c "if [ -f '${CMAKE_CURRENT_BINARY_DIR}/${WASM_OUTPUT_NAME}.worker.js' ]; then cp '${CMAKE_CURRENT_BINARY_DIR}/${WASM_OUTPUT_NAME}.worker.js' '${WASM_OUTPUT_DIR}/${WASM_OUTPUT_NAME}.worker.js'; echo 'Staged pthread worker companion'; else echo 'No separate .worker.js (Emscripten 5.x bundles worker into main glue)'; fi"
        COMMENT "Staging ${WASM_OUTPUT_NAME}.worker.js if present (Emscripten <5.x emits it; 5.x bundles into main glue)"
        VERBATIM
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
message(STATUS "Target:       runanywhere_wasm")
message(STATUS "llama.cpp:    ${RAC_WASM_LLAMACPP}")
message(STATUS "WebGPU:       ${RAC_WASM_WEBGPU}")
message(STATUS "VLM (mtmd):   ${RAC_VLM_USE_MTMD}")
message(STATUS "whisper.cpp:  ${RAC_WASM_WHISPERCPP}")
message(STATUS "sherpa-onnx:  ${RAC_WASM_ONNX}")
message(STATUS "Output name:  ${WASM_OUTPUT_NAME}")
message(STATUS "Output dir:   ${WASM_OUTPUT_DIR}")
message(STATUS "====================================")
message(STATUS "")
