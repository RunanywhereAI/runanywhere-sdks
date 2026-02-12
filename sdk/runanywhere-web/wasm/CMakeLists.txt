cmake_minimum_required(VERSION 3.22)

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
option(RAC_WASM_WHISPERCPP "Build with whisper.cpp STT backend" OFF)
option(RAC_WASM_ONNX "Build with sherpa-onnx TTS/VAD backend" OFF)

# =============================================================================
# C++ CONFIGURATION
# =============================================================================

set(CMAKE_CXX_STANDARD 17)
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

# Disable VLM for initial WASM (reduces build complexity)
set(RAC_VLM_USE_MTMD OFF CACHE BOOL "" FORCE)

# =============================================================================
# BACKEND-SPECIFIC CONFIGURATION
# =============================================================================
# IMPORTANT: These must be set BEFORE add_subdirectory() so that llama.cpp,
# whisper.cpp, and ONNX CMake files see the correct cache variables.

if(RAC_WASM_LLAMACPP)
    message(STATUS "Building with llama.cpp LLM backend for WASM")

    # Disable all GPU/accelerator backends (CPU-only for WASM)
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

# Add RACommons as subdirectory (builds rac_commons static library)
# Must come AFTER backend configuration so cache variables are set.
add_subdirectory("${RAC_COMMONS_DIR}" "${CMAKE_CURRENT_BINARY_DIR}/rac_commons")

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

    # Module registry
    "_rac_module_register"
    "_rac_module_unregister"
    "_rac_module_list"
    "_rac_modules_for_capability"
    "_rac_module_get_info"

    # Service registry
    "_rac_service_register_provider"
    "_rac_service_unregister_provider"
    "_rac_service_create"
    "_rac_service_list_providers"

    # Events
    "_rac_event_subscribe"
    "_rac_event_subscribe_all"
    "_rac_event_unsubscribe"
    "_rac_event_publish"
    "_rac_event_track"
    "_rac_event_category_name"

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
    "_rac_model_info_is_downloaded"
    "_rac_model_info_alloc"
    "_rac_model_info_free"
    "_rac_model_info_array_free"
    "_rac_model_info_copy"
    "_rac_model_registry_discover_downloaded"
    "_rac_discovery_result_free"

    # Model types
    "_rac_framework_display_name"
    "_rac_framework_supports_llm"
    "_rac_framework_supports_stt"
    "_rac_framework_supports_tts"
    "_rac_model_format_extension"

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
    "_rac_tts_component_get_state"
    "_rac_tts_component_get_metrics"
    "_rac_tts_component_destroy"

    # VAD service
    "_rac_vad_create"
    "_rac_vad_initialize"
    "_rac_vad_set_activity_callback"
    "_rac_vad_set_audio_callback"
    "_rac_vad_start"
    "_rac_vad_stop"
    "_rac_vad_reset"
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
    "_rac_vad_component_cleanup"
    "_rac_vad_component_set_activity_callback"
    "_rac_vad_component_set_audio_callback"
    "_rac_vad_component_start"
    "_rac_vad_component_stop"
    "_rac_vad_component_reset"
    "_rac_vad_component_process"
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

    # VLM service
    "_rac_vlm_get_builtin_template"
    "_rac_vlm_result_free"
    "_rac_vlm_create"
    "_rac_vlm_initialize"
    "_rac_vlm_process"
    "_rac_vlm_process_stream"
    "_rac_vlm_get_info"
    "_rac_vlm_cancel"
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
    "_rac_structured_output_get_system_prompt"
    "_rac_structured_output_validate"
    "_rac_structured_output_validation_free"

    # Diffusion component
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
    "_rac_diffusion_component_configure_json"
    "_rac_diffusion_component_generate_json"
    "_rac_diffusion_component_get_info_json"
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

    # Environment / SDK config
    "_rac_sdk_init"
    "_rac_sdk_get_config"
    "_rac_sdk_get_environment"
    "_rac_sdk_is_initialized"
    "_rac_sdk_reset"

    # Telemetry
    "_rac_telemetry_manager_create"
    "_rac_telemetry_manager_destroy"
    "_rac_telemetry_manager_set_device_info"
    "_rac_telemetry_manager_set_http_callback"
    "_rac_telemetry_manager_track"
    "_rac_telemetry_manager_flush"
    "_rac_telemetry_payload_default"
    "_rac_telemetry_payload_free"

    # WASM helper functions (sizeof, ping, version)
    "_rac_wasm_ping"
    "_rac_wasm_get_version_major"
    "_rac_wasm_get_version_minor"
    "_rac_wasm_get_version_patch"
    "_rac_wasm_sizeof_platform_adapter"
    "_rac_wasm_sizeof_config"
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

    # Emscripten runtime helpers
    "_malloc"
    "_free"
)

# Add llama.cpp backend exports if enabled
if(RAC_WASM_LLAMACPP)
    list(APPEND RAC_EXPORTED_FUNCTIONS
        "_rac_llm_llamacpp_create"
        "_rac_llm_llamacpp_load_model"
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
endif()

# Join into a comma-separated list for Emscripten
string(JOIN "," RAC_EXPORTED_FUNCTIONS_STR ${RAC_EXPORTED_FUNCTIONS})

# =============================================================================
# WASM BUILD TARGET
# =============================================================================

add_executable(racommons
    ${WASM_EXPORT_SOURCES}
    ${WASM_PLATFORM_SOURCES}
)

target_link_libraries(racommons PRIVATE rac_commons)

if(RAC_WASM_LLAMACPP)
    target_link_libraries(racommons PRIVATE rac_backend_llamacpp)
endif()

if(RAC_WASM_WHISPERCPP)
    target_link_libraries(racommons PRIVATE rac_backend_whispercpp)
endif()

if(RAC_WASM_ONNX)
    target_link_libraries(racommons PRIVATE rac_backend_onnx)
endif()

target_include_directories(racommons PRIVATE
    ${RAC_COMMONS_DIR}/include
    ${RAC_COMMONS_DIR}/src
)

# Emscripten compile definitions
target_compile_definitions(racommons PRIVATE
    RAC_PLATFORM_WASM=1
    RAC_PLATFORM_NAME="Emscripten"
)

if(RAC_WASM_LLAMACPP)
    target_compile_definitions(racommons PRIVATE RAC_WASM_LLAMACPP=1)
endif()

if(RAC_WASM_WHISPERCPP)
    target_compile_definitions(racommons PRIVATE RAC_WASM_WHISPERCPP=1)
endif()

if(RAC_WASM_ONNX)
    target_compile_definitions(racommons PRIVATE RAC_WASM_ONNX=1)
endif()

# =============================================================================
# EMSCRIPTEN LINKER FLAGS
# =============================================================================

set(EMSCRIPTEN_LINK_FLAGS
    # Output format
    "-sWASM=1"
    "-sMODULARIZE=1"
    "-sEXPORT_ES6=1"
    "-sEXPORT_NAME=createRACommonsModule"
    "-sENVIRONMENT=web,worker"

    # Memory
    "-sALLOW_MEMORY_GROWTH=1"
    "-sINITIAL_MEMORY=33554432"    # 32 MB initial
    "-sMAXIMUM_MEMORY=2147483648"  # 2 GB max
    "-sSTACK_SIZE=1048576"         # 1 MB stack

    # Function exports
    "-sEXPORTED_FUNCTIONS=[${RAC_EXPORTED_FUNCTIONS_STR}]"
    "-sEXPORTED_RUNTIME_METHODS=[\"ccall\",\"cwrap\",\"addFunction\",\"removeFunction\",\"UTF8ToString\",\"stringToUTF8\",\"lengthBytesUTF8\",\"setValue\",\"getValue\",\"FS\"]"

    # Allow JS function pointers (needed for platform adapter callbacks)
    "-sALLOW_TABLE_GROWTH=1"

    # Filesystem
    "-sFORCE_FILESYSTEM=1"

    # No auto-exit
    "-sNO_EXIT_RUNTIME=1"

    # Error handling
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
    target_compile_options(racommons PRIVATE "-pthread")
    message(STATUS "pthreads ENABLED (requires Cross-Origin Isolation headers)")
else()
    message(STATUS "pthreads DISABLED (single-threaded mode)")
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
        "--closure=1"
    )
    message(STATUS "Release mode (optimized)")
endif()

# Join flags
string(JOIN " " EMSCRIPTEN_LINK_FLAGS_STR ${EMSCRIPTEN_LINK_FLAGS})

set_target_properties(racommons PROPERTIES
    LINK_FLAGS "${EMSCRIPTEN_LINK_FLAGS_STR}"
    OUTPUT_NAME "racommons"
    SUFFIX ".js"
)

# =============================================================================
# POST-BUILD: Copy outputs to packages/core/wasm/
# =============================================================================

set(WASM_OUTPUT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../packages/core/wasm")

add_custom_command(TARGET racommons POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${WASM_OUTPUT_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy
        "${CMAKE_CURRENT_BINARY_DIR}/racommons.js"
        "${WASM_OUTPUT_DIR}/racommons.js"
    COMMAND ${CMAKE_COMMAND} -E copy
        "${CMAKE_CURRENT_BINARY_DIR}/racommons.wasm"
        "${WASM_OUTPUT_DIR}/racommons.wasm"
    COMMENT "Copying WASM outputs to packages/core/wasm/"
)

# Also copy worker file if pthreads enabled
if(RAC_WASM_PTHREADS)
    add_custom_command(TARGET racommons POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
            "${CMAKE_CURRENT_BINARY_DIR}/racommons.worker.js"
            "${WASM_OUTPUT_DIR}/racommons.worker.js"
        COMMENT "Copying pthread worker to packages/core/wasm/"
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
message(STATUS "llama.cpp:    ${RAC_WASM_LLAMACPP}")
message(STATUS "whisper.cpp:  ${RAC_WASM_WHISPERCPP}")
message(STATUS "sherpa-onnx:  ${RAC_WASM_ONNX}")
message(STATUS "Output:       ${WASM_OUTPUT_DIR}")
message(STATUS "====================================")
message(STATUS "")
