/**
 * EmscriptenModule.ts
 *
 * Typed surface over the Emscripten-compiled
 * RACommons modules so TypeScript call sites can use one validated shape
 * without redeclaring C ABI signatures.
 *
 * `CommonsModule` loads the core package's commons-only artifact. The
 * llama.cpp and ONNX packages load their own artifacts, then register the
 * module for only the capabilities they implement. This file owns that typed
 * capability registry; it does not contain a concrete backend loader.
 */

import { DownloadAdapter } from '../Adapters/DownloadAdapter.js';
import { ModelLifecycleAdapter } from '../Adapters/ModelLifecycleAdapter.js';
import { ModelRegistryAdapter } from '../Adapters/ModelRegistryAdapter.js';
import { ModalityProtoAdapter } from '../Adapters/ModalityProtoAdapter.js';
import { SDKEventStreamAdapter } from '../Adapters/SDKEventStreamAdapter.js';

/**
 * Minimal subset of the Emscripten Module object that this SDK uses.
 * Add exported-function signatures here as they're wired through the
 * TS surface.
 */
export interface EmscriptenRunanywhereModule {
  // =============================================================================
  // Exported C functions
  // =============================================================================
  // Must be listed in sdk/runanywhere-web/wasm/CMakeLists.txt
  // RAC_EXPORTED_FUNCTIONS to actually resolve at runtime.

  /**
   * `rac_result_t rac_voice_agent_set_proto_callback(
   *    rac_voice_agent_handle_t handle,
   *    rac_voice_agent_proto_event_callback_fn callback,  // function-table index
   *    void* user_data);`
   *
   * The `callback` argument is a function-table index obtained from
   * `addFunction(fn, 'viii')`. Pass 0 to clear the registration.
   */
  _rac_voice_agent_set_proto_callback(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;

  /**
   * `rac_result_t rac_llm_set_stream_proto_callback(
   *    rac_handle_t handle,
   *    rac_llm_stream_proto_callback_fn callback,  // function-table index
   *    void* user_data);`
   *
   * `rac_result_t rac_llm_unset_stream_proto_callback(rac_handle_t handle);`
   *
   * Same function-table-index contract as the voice agent variant; the
   * callback signature is `void (*)(uint8_t*, size_t, void*)` which
   * encodes as `'viii'` when installed via `addFunction`.
   */
  _rac_llm_set_stream_proto_callback(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_llm_unset_stream_proto_callback(handle: number): number;

  // -----------------------------------------------------------------------------
  // Generated-proto modality ABI
  // -----------------------------------------------------------------------------
  _rac_llm_generate_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_llm_generate_stream_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_llm_cancel_proto?(outEvent: number): number;

  _rac_stt_component_transcribe_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_stt_component_transcribe_stream_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_stt_transcribe_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_stt_transcribe_stream_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_tts_component_list_voices_proto?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_tts_component_synthesize_proto?(
    handle: number,
    text: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_tts_component_synthesize_stream_proto?(
    handle: number,
    text: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_tts_synthesize_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_tts_synthesize_stream_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_tts_stop_lifecycle_proto?(outResult: number): number;
  _rac_tts_list_voices_lifecycle_proto?(outResult: number): number;

  _rac_vad_component_configure_proto?(
    handle: number,
    configBytes: number,
    configSize: number,
  ): number;
  _rac_vad_component_process_proto?(
    handle: number,
    samples: number,
    numSamples: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_vad_component_get_statistics_proto?(
    handle: number,
    outResult: number,
  ): number;
  _rac_vad_component_set_activity_proto_callback?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_vad_process_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_vad_configure_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_vad_start_lifecycle_proto?(outResult: number): number;
  _rac_vad_stop_lifecycle_proto?(outResult: number): number;
  _rac_vad_reset_lifecycle_proto?(outResult: number): number;

  _rac_voice_agent_initialize_proto?(
    handle: number,
    configBytes: number,
    configSize: number,
    outComponentStates: number,
  ): number;
  _rac_voice_agent_component_states_proto?(
    handle: number,
    outComponentStates: number,
  ): number;
  _rac_voice_agent_process_voice_turn_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    outResult: number,
  ): number;
  _rac_voice_agent_component_destroy_proto?(handle: number): number;

  _rac_vlm_generate_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  /** Typed stream ABI: serialized VLMGenerationRequest in, VLMStreamEvent
   *  per callback. Lifecycle-owned model — no handle, no out-result. */
  _rac_vlm_stream_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_vlm_cancel_lifecycle_proto?(outEvent: number): number;

  _rac_embeddings_embed_batch_proto?(
    handle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_embeddings_embed_batch_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;

  _rac_segmentation_segment_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;

  _rac_vocoder_vocode_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;

  _rac_diffusion_generate_proto?(
    handle: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_diffusion_generate_with_progress_proto?(
    handle: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
    outResult: number,
  ): number;
  _rac_diffusion_cancel_proto?(handle: number): number;

  _rac_rag_session_create_proto?(
    configBytes: number,
    configSize: number,
    outSession: number,
  ): number;
  _rac_rag_session_destroy_proto?(session: number): void;
  _rac_rag_ingest_proto?(
    session: number,
    documentBytes: number,
    documentSize: number,
    outStats: number,
  ): number;
  _rac_rag_query_proto?(
    session: number,
    queryBytes: number,
    querySize: number,
    outResult: number,
  ): number;
  _rac_rag_query_stream_proto?(
    session: number,
    queryBytes: number,
    querySize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_rag_clear_proto?(session: number, outStats: number): number;
  _rac_rag_stats_proto?(session: number, outStats: number): number;

  _rac_get_lora_registry?(): number;
  _rac_lora_register_proto?(
    registry: number,
    entryBytes: number,
    entrySize: number,
    outEntry: number,
  ): number;
  _rac_lora_catalog_list_proto?(
    registry: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_catalog_query_proto?(
    registry: number,
    queryBytes: number,
    querySize: number,
    outResult: number,
  ): number;
  _rac_lora_catalog_get_proto?(
    registry: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_catalog_mark_download_completed_proto?(
    registry: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_compatibility_proto?(
    configBytes: number,
    configSize: number,
    outResult: number,
  ): number;
  _rac_lora_apply_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_remove_proto?(
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;
  _rac_lora_list_proto?(
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;
  _rac_lora_state_proto?(
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;

  _rac_structured_output_parse_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_tool_call_parse_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_tool_call_validate_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_tool_call_format_prompt_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  /**
   * ToolValue <-> JSON bridge — the recursive walk lives in commons so every
   * SDK shares one source of truth (Swift parity: ToolValueJSONABI,
   * ToolCallingTypes.swift). Request/response are serialized
   * `runanywhere.v1.ToolValueJSON` / `runanywhere.v1.ToolValue` protos.
   */
  _rac_tool_value_to_json_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_tool_value_from_json_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  /**
   * Session-based tool-calling ABI. The Web SDK uses these
   * (instead of the synchronous `_rac_tool_calling_run_loop_proto`) so that
   * TypeScript executors returning `Promise<ToolResult>` can be awaited
   * between commons-driven generate -> parse -> validate cycles.
   *
   * `_rac_tool_calling_session_create_proto(requestBytes, requestSize, eventCallbackPtr, eventUserData, handleCallbackPtr, handleUserData)`:
   *   callbackPtr is a function-table index obtained from `addFunction(fn, 'viii')`
   *   whose JS implementation receives `(eventBytesPtr, eventSize, userData)` and
   *   decodes a serialized `runanywhere.v1.ToolCallingSessionEvent`.
   *   handleCallbackPtr uses `addFunction(fn, 'vji')`; commons invokes it
   *   synchronously with the uint64 session handle before initial generation.
   */
  _rac_tool_calling_session_create_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
    handleCallbackPtr: number,
    handleUserData: number,
  ): number;
  /**
   * `_rac_tool_calling_session_step_with_result_proto(requestBytes, requestSize)`:
   *   Accepts a serialized `runanywhere.v1.ToolCallingSessionStepWithResultRequest`
   *   and resumes the run loop. WebGPU hosts must await it through Asyncify-aware
   *   `ccall`; any new events (further tool_call, final_result, or error) fire via
   *   the callback installed at session create before that call resolves.
   */
  _rac_tool_calling_session_step_with_result_proto?(
    requestBytes: number,
    requestSize: number,
  ): number;
  /**
   * `_rac_tool_calling_session_destroy_proto(sessionHandle)`:
   *   Tears down session state. Idempotent / safe to call after final_result.
   *   Used by the TS `generateWithTools` for both normal completion and abort.
   *   `sessionHandle` is the uint64 returned by session_create (matches
   *   `_rac_sdk_event_unsubscribe` — receives a bigint because every shipped
   *   Web artifact is linked with `-sWASM_BIGINT=1`.
   */
  _rac_tool_calling_session_destroy_proto?(
    sessionHandle: bigint,
  ): number;
  /**
   * `_rac_tool_calling_session_cancel_proto(sessionHandle)`:
   *   Latches a cancel-requested flag on the session and asks the in-flight
   *   LifecycleLlmRef to interrupt the underlying backend `ops->generate`.
   *   Distinct from `_rac_tool_calling_session_destroy_proto` — the host
   *   should still call destroy once the in-flight call has resolved. Safe
   *   to call from any context. Asyncify-backed calls yield to the browser
   *   event loop, so an AbortSignal callback can latch cancellation after the
   *   session handle is published; native inference workers may still run on
   *   their own execution backend.
   */
  _rac_tool_calling_session_cancel_proto?(
    sessionHandle: bigint,
  ): number;
  _rac_structured_output_prepare_prompt_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_structured_output_validate_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  /**
   * `rac_result_t rac_structured_output_schema_to_json_proto(
   *    const uint8_t* schema_bytes, size_t size, rac_proto_buffer_t* out);`
   *
   * Request: serialized `JSONSchema` bytes; result buffer carries the raw
   * UTF-8 JSON Schema text (NOT proto bytes). Backs the Web port of Swift's
   * `RAJSONSchema.jsonSchemaString` (StructuredOutputProto+Helpers.swift:38).
   */
  _rac_structured_output_schema_to_json_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;

  // -----------------------------------------------------------------------------
  // Model-path helpers
  // -----------------------------------------------------------------------------

  /**
   * `rac_result_t rac_inference_framework_from_proto(int32_t proto_value,
   *    rac_inference_framework_t* out);`
   *
   * Converts a proto enum integer (the JS `InferenceFramework` rawValue) to
   * the C `rac_inference_framework_t` enum value required by path helpers.
   * `outPtr` must point to a 4-byte malloc'd slot; read back with HEAP32.
   */
  _rac_inference_framework_from_proto?(protoValue: number, outPtr: number): number;

  /**
   * `const char* rac_framework_raw_value(rac_inference_framework_t framework);`
   *
   * Returns a statically-allocated C string with the directory-name component
   * used under `/opfs/RunAnywhere/Models/<dir>/<modelId>/` (e.g. "LlamaCpp",
   * "ONNX"). Returns "Unknown" for unrecognized values. The pointer is valid
   * for the lifetime of the WASM module; callers must NOT free it.
   */
  _rac_framework_raw_value?(frameworkCEnum: number): number;

  // -----------------------------------------------------------------------------
  // SDK initialization / auth state
  // -----------------------------------------------------------------------------
  _rac_sdk_init_phase1_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_sdk_init_phase2_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_sdk_retry_http_proto?(outResult: number): number;
  _rac_wasm_set_client_info?(
    sdkBinding: number,
    appIdentifier: number,
    appName: number,
    appVersion: number,
    appBuild: number,
    locale: number,
    timezone: number,
  ): void;
  _rac_auth_is_authenticated?(): number;
  _rac_auth_get_user_id?(): number;
  _rac_auth_get_organization_id?(): number;
  _rac_state_is_device_registered?(): number;
  _rac_device_manager_register_if_needed?(environment: number, buildTokenPtr: number): number;

  // -----------------------------------------------------------------------------
  // Solutions runtime — `rac/solutions/rac_solution.h`
  // -----------------------------------------------------------------------------
  // Backing the `RunAnywhere.solutions.run(...)` capability. `_create_from_proto`
  // takes a `(bytesPtr, bytesLen, outHandlePtr)` triple and populates the
  // out-pointer with an opaque handle on success; the lifecycle verbs operate
  // on that handle. The proto-byte path requires the WASM module to be built
  // with Protobuf support (`RAC_WASM_PROTOBUF=ON`), otherwise it returns
  // `RAC_ERROR_FEATURE_NOT_AVAILABLE`.

  /**
   * `rac_result_t rac_solution_create_from_proto(
   *    const void* proto_bytes, size_t len,
   *    rac_solution_handle_t* out_handle);`
   */
  _rac_solution_create_from_proto(
    bytesPtr: number,
    bytesLen: number,
    outHandlePtr: number,
  ): number;

  /**
   * `rac_result_t rac_solution_create_from_yaml(
   *    const char* yaml_text,
   *    rac_solution_handle_t* out_handle);`
   */
  _rac_solution_create_from_yaml(
    yamlPtr: number,
    outHandlePtr: number,
  ): number;

  _rac_solution_start(handle: number): number;
  _rac_solution_stop(handle: number): number;
  _rac_solution_cancel(handle: number): number;
  _rac_solution_feed(handle: number, itemPtr: number): number;
  _rac_solution_close_input(handle: number): number;
  _rac_solution_destroy(handle: number): void;

  // -----------------------------------------------------------------------------
  // Model registry proto-byte ABI
  // -----------------------------------------------------------------------------
  // These are mandatory for every current RunAnywhere WASM artifact.
  _rac_get_model_registry(): number;
  _rac_model_registry_refresh_proto(
    handle: number,
    requestBytes: number,
    requestSize: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_register_proto(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_update_proto(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_update_download_status(
    handle: number,
    modelId: number,
    localPath: number,
  ): number;
  _rac_model_registry_get_proto(
    handle: number,
    modelId: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_proto(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_query_proto(
    handle: number,
    queryProtoBytes: number,
    queryProtoSize: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_downloaded_proto(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_remove_proto(
    handle: number,
    modelId: number,
  ): number;
  _rac_model_registry_import_proto(
    handle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_model_registry_proto_free(protoBytes: number): void;

  // -----------------------------------------------------------------------------
  // Model lifecycle proto-byte ABI
  // -----------------------------------------------------------------------------
  _rac_model_lifecycle_load_proto?(
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_model_lifecycle_unload_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_model_lifecycle_current_model_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_component_lifecycle_snapshot_proto?(
    component: number,
    outSnapshot: number,
  ): number;
  _rac_model_lifecycle_reset?(): void;

  // -----------------------------------------------------------------------------
  // Shared proto-buffer ABI
  // -----------------------------------------------------------------------------
  _rac_proto_buffer_init?(bufferPtr: number): void;
  _rac_proto_buffer_free?(bufferPtr: number): void;
  _rac_wasm_sizeof_proto_buffer?(): number;
  _rac_wasm_offsetof_proto_buffer_data?(): number;
  _rac_wasm_offsetof_proto_buffer_size?(): number;
  _rac_wasm_offsetof_proto_buffer_status?(): number;
  _rac_wasm_offsetof_proto_buffer_error_message?(): number;

  /**
   * Canonical rac_result_t -> serialized SDKError proto mapping.
   * Lets SDKException route error construction through the
   * shared commons helper rac_result_to_proto_error.
   */
  _rac_wasm_result_to_proto_error?(code: number, outBufferPtr: number): number;

  // -----------------------------------------------------------------------------
  // Storage analyzer proto-byte ABI
  // -----------------------------------------------------------------------------
  _rac_storage_analyzer_create?(callbacksPtr: number, outHandlePtr: number): number;
  _rac_storage_analyzer_destroy?(handle: number): void;
  _rac_storage_analyzer_info_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_availability_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_delete_plan_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_delete_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_wasm_sizeof_storage_callbacks?(): number;
  _rac_wasm_offsetof_storage_callbacks_calculate_dir_size?(): number;
  _rac_wasm_offsetof_storage_callbacks_get_file_size?(): number;
  _rac_wasm_offsetof_storage_callbacks_path_exists?(): number;
  _rac_wasm_offsetof_storage_callbacks_get_available_space?(): number;
  _rac_wasm_offsetof_storage_callbacks_get_total_space?(): number;
  _rac_wasm_offsetof_storage_callbacks_delete_path?(): number;
  _rac_wasm_offsetof_storage_callbacks_is_model_loaded?(): number;
  _rac_wasm_offsetof_storage_callbacks_unload_model?(): number;
  _rac_wasm_offsetof_storage_callbacks_user_data?(): number;

  // -----------------------------------------------------------------------------
  // Download proto-byte ABI
  // -----------------------------------------------------------------------------
  _rac_download_set_progress_proto_callback?(
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_download_plan_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_download_start_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_download_cancel_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_download_resume_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_download_progress_poll_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;

  // -----------------------------------------------------------------------------
  // SDKEvent proto-byte event stream ABI
  // -----------------------------------------------------------------------------
  _rac_sdk_event_subscribe?(callbackPtr: number, userData: number): bigint;
  _rac_sdk_event_unsubscribe?(subscriptionId: bigint): void;
  _rac_sdk_event_quiesce?(): void;
  _rac_sdk_event_publish_proto?(protoBytes: number, protoSize: number): number;
  _rac_sdk_event_poll?(outEvent: number): number;
  _rac_sdk_event_publish_failure?(
    errorCode: number,
    message: number,
    component: number,
    operation: number,
    recoverable: number,
  ): number;
  _rac_sdk_event_clear_queue?(): void;

  // =============================================================================
  // Emscripten runtime helpers
  // =============================================================================

  /**
   * Read a scalar value from the WASM heap at `ptr`.
   * `type` is an Emscripten type string: `'i8'`, `'i16'`, `'i32'`, `'i64'`,
   * `'float'`, `'double'`, or `'*'` (pointer-width integer).
   */
  getValue(ptr: number, type: string): number;

  /**
   * Write a scalar value to the WASM heap at `ptr`.
   * `type` mirrors the `getValue` type string vocabulary.
   */
  setValue(ptr: number, value: number, type: string): void;

  /** Raw heap as a typed array — only valid until the next WASM alloc. */
  readonly HEAPU8: Uint8Array;
  readonly HEAP32: Int32Array;
  readonly HEAPU32: Uint32Array;

  /**
   * Install a JS function into the WASM function table and return its
   * index, suitable for passing as a C function pointer. `signature` is
   * an Emscripten sig string: `'v'`=void, `'i'`=i32, `'j'`=i64,
   * `'f'`=f32, `'d'`=f64, `'p'`=pointer. Return type is the first char.
   *
   * Requires `-sEXPORTED_RUNTIME_METHODS=['addFunction','removeFunction']`
   * and `-sALLOW_TABLE_GROWTH=1` at link time.
   */
  addFunction(fn: (...args: never[]) => number | bigint | void, signature: string): number;

  /** Remove a previously-installed JS callback. Idempotent. */
  removeFunction(ptr: number): void;

  /** Allocate `size` bytes in the WASM heap. Returns a pointer. */
  _malloc(size: number): number;
  /** Free a pointer previously returned by `_malloc` / equivalent. */
  _free(ptr: number): void;

  /** Read a UTF-8 C string at `ptr` into a JS string. Stops at NUL. */
  UTF8ToString(ptr: number, maxBytesToRead?: number): string;

  /** Write a UTF-8 string into the WASM heap at `ptr`, NUL-terminated.
   *  Requires `ptr` to point at a buffer of at least
   *  `lengthBytesUTF8(str) + 1` bytes. */
  stringToUTF8(str: string, ptr: number, maxBytesToWrite: number): number;

  /** UTF-8 byte-length of a JS string (excluding the trailing NUL). */
  lengthBytesUTF8(str: string): number;

  /** Emscripten's main-thread invocation helper (ccall). Rarely used. */
  ccall?: (
    fname: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ) => unknown;
}

// ---------------------------------------------------------------------------
// Capability-aware module registry
// ---------------------------------------------------------------------------
// The Web SDK ships three independent WASM artifacts (commons / llamacpp /
// onnx-sherpa). Each backend bridge registers its module against the
// capabilities it serves. Operation-level facade dispatch then looks up the
// correct module per capability — without colliding with the other modules.
//
// Capability ownership (typical layout):
//   - racommons.wasm           → 'commons'
//   - racommons-llamacpp.wasm  → 'llm', 'vlm', 'embedding',
//                                 'structured-output', 'tool-calling', 'lora'
//   - racommons-onnx-sherpa.wasm → 'stt', 'tts', 'vad', 'embedding',
//                                  'segmentation', 'vocoder', 'rag'
//
// The same module may register multiple capabilities; duplicate registration
// of a capability replaces the previous owner (last-writer-wins per
// capability, NOT per module).

/**
 * Cross-cutting capability tag used by the Web SDK's facade to route each
 * operation to the WASM module that actually exports the relevant proto
 * symbols. See `getModuleForCapability` for the lookup contract.
 */
export type WasmCapability =
  | 'commons'           // SDK init/lifecycle, model registry, events, etc.
  | 'llm'               // LLM ops (text generation)
  | 'vlm'               // VLM ops (vision-language); typically same module as 'llm'
  | 'stt'               // Speech-to-text
  | 'tts'               // Text-to-speech
  | 'vad'               // Voice activity detection
  | 'embedding'         // Embeddings
  | 'segmentation'      // Semantic image segmentation
  | 'vocoder'           // Mel-spectrogram to waveform vocoding
  | 'rag'               // RAG pipeline (embeddings + retrieval)
  | 'diffusion'         // Diffusion (image generation)
  | 'structured-output' // Structured-output parse/validate/prepare-prompt
  | 'tool-calling'      // Tool-calling session ABI
  | 'lora'              // LoRA registry/apply/state
  | 'voice-agent';      // Voice-agent component (lives in same module as STT/TTS/VAD)

/** Capability → module map. Backends register; facade looks up. */
const _moduleByCapability = new Map<WasmCapability, EmscriptenRunanywhereModule>();
const _modulesByCapability = new Map<
  WasmCapability,
  EmscriptenRunanywhereModule[]
>();

/**
 * Framework → module map. Each backend WASM owns its own static
 * `s_plugin_registry`; the plugin registry lookup (`rac_plugin_find*`) only
 * finds the framework's plugin inside the WASM that ran the backend's
 * `rac_backend_*_register()` call. Web-only: native SDKs share a single
 * process-wide plugin registry.
 */
const _moduleByFramework = new Map<string, EmscriptenRunanywhereModule>();
const _modulesByFramework = new Map<string, EmscriptenRunanywhereModule[]>();

const BACKEND_CAPABILITY_PRECEDENCE: readonly WasmCapability[] = [
  'llm',
  'vlm',
  'stt',
  'tts',
  'vad',
  'embedding',
  'segmentation',
  'vocoder',
  'rag',
  'diffusion',
];

function reelectLifecycleAndRegistryPrimary(): void {
  let primary: EmscriptenRunanywhereModule | null = null;
  for (const capability of BACKEND_CAPABILITY_PRECEDENCE) {
    const candidate = _moduleByCapability.get(capability);
    if (candidate) {
      primary = candidate;
      break;
    }
  }
  primary ??= _moduleByCapability.get('commons') ?? null;

  if (primary) {
    ModelLifecycleAdapter.setDefaultModule(primary);
    ModelRegistryAdapter.setDefaultModule(primary);
  } else {
    ModelLifecycleAdapter.clearDefaultModule();
    ModelRegistryAdapter.clearDefaultModule();
  }
}

/** Look up which WASM owns the registered plugin for a model framework. */
export function getModuleForFramework(framework: string): EmscriptenRunanywhereModule | null {
  if (!framework) return null;
  return _moduleByFramework.get(framework.toLowerCase()) ?? null;
}

/**
 * Register a module against one or more capabilities. Replaces any prior
 * owner of those capabilities (last-writer-wins per capability). Also
 * forwards the module to the applicable adapter slots,
 * keyed by which capabilities are claimed — so e.g. an LLM-only bridge no
 * longer overwrites the commons-installed `ModelRegistryAdapter`.
 *
 * The same module instance may be registered against any subset of
 * capabilities — duplicate calls are idempotent for that capability.
 */
export function registerWasmModule(
  capabilities: readonly WasmCapability[],
  mod: EmscriptenRunanywhereModule,
  frameworks: readonly string[] = [],
): void {
  for (const cap of capabilities) {
    const owners = (_modulesByCapability.get(cap) ?? []).filter((owner) => owner !== mod);
    owners.push(mod);
    _modulesByCapability.set(cap, owners);
    _moduleByCapability.set(cap, mod);
  }
  for (const fw of frameworks) {
    if (fw) {
      const key = fw.toLowerCase();
      const owners = (_modulesByFramework.get(key) ?? []).filter((owner) => owner !== mod);
      owners.push(mod);
      _modulesByFramework.set(key, owners);
      _moduleByFramework.set(key, mod);
    }
  }
  // Commons-level adapters (model registry, downloads, events)
  // follow the 'commons' capability — they target SDK-state surface exports
  // that live in racommons.wasm. Routing them by capability prevents a
  // later llamacpp/onnx bridge from clobbering the core's installed
  // adapters when it registers its own narrower capabilities.
  if (capabilities.includes('commons')) {
    DownloadAdapter.setDefaultModule(mod);
    ModelRegistryAdapter.setDefaultModule(mod);
    SDKEventStreamAdapter.setDefaultModule(mod);
    // Pre-bind ModelLifecycleAdapter to commons too — backend bridges
    // overwrite this when they register (see below), but a bare commons
    // module still answers `currentModel` / `componentLifecycleSnapshot`
    // for inspect-only use cases that don't require a plugin route.
    ModelLifecycleAdapter.setDefaultModule(mod);
  }
  // Model lifecycle + model registry routing — special case. The C++
  // plugin-registry route (driven by ModelLifecycleAdapter.load) lives
  // inside whichever WASM module's `s_plugin_registry` was populated by
  // the backend's `rac_backend_*_register()` call. The commons artifact
  // has NO backend plugins linked in, so routing model loads through
  // commons fails with "no backend route supports model". The model
  // REGISTRY (catalog) is per-module too, so it must point at the SAME
  // module as the lifecycle adapter or `loadModel` looks up the model in
  // an empty registry. When any backend bridge (LlamaCPP, ONNX) registers,
  // repoint BOTH adapters at THAT module. Last-writer-wins per
  // registration.
  if (BACKEND_CAPABILITY_PRECEDENCE.some((cap) => capabilities.includes(cap))) {
    ModelLifecycleAdapter.setDefaultModule(mod);
    ModelRegistryAdapter.setDefaultModule(mod);
  }
  // The ModalityProtoAdapter's internal per-capability slot is the canonical
  // dispatch table for the modality verbs (LLM/VLM/STT/TTS/VAD/embedding/
  // segmentation/vocoder/diffusion/rag/lora/voice-agent/structured-output). Push the module into
  // every claimed slot so per-modality `tryDefault()` calls find it.
  ModalityProtoAdapter.registerModuleCapabilities(capabilities, mod);
}

/**
 * Drop a single module from the registry. All capability slots that
 * point at this module are removed, and downstream adapters are cleared
 * if they were tracking it. Use this on backend teardown / acceleration
 * switch — it lets siblings keep their slots intact.
 */
export function unregisterWasmModule(mod: EmscriptenRunanywhereModule): void {
  for (const [fw, owners] of Array.from(_modulesByFramework.entries())) {
    const survivors = owners.filter((owner) => owner !== mod);
    if (survivors.length === owners.length) continue;
    if (survivors.length === 0) {
      _modulesByFramework.delete(fw);
      _moduleByFramework.delete(fw);
    } else {
      _modulesByFramework.set(fw, survivors);
      _moduleByFramework.set(fw, survivors[survivors.length - 1]!);
    }
  }
  const releasedCapabilities: WasmCapability[] = [];
  const restoredCapabilities: Array<{
    capability: WasmCapability;
    module: EmscriptenRunanywhereModule;
  }> = [];
  for (const [cap, owners] of Array.from(_modulesByCapability.entries())) {
    const current = _moduleByCapability.get(cap);
    const survivors = owners.filter((owner) => owner !== mod);
    if (survivors.length === owners.length) continue;
    if (survivors.length === 0) {
      _modulesByCapability.delete(cap);
      _moduleByCapability.delete(cap);
    } else {
      _modulesByCapability.set(cap, survivors);
      const restored = survivors[survivors.length - 1]!;
      _moduleByCapability.set(cap, restored);
      if (current === mod) restoredCapabilities.push({ capability: cap, module: restored });
    }
    if (current === mod) releasedCapabilities.push(cap);
  }
  // Drop THIS module from the ModelRegistryAdapter broadcast set
  // regardless of which capability it owned — the broadcast list mirrors
  // every WASM that has registered. If commons was
  // released we also clear the commons-only adapters. Lifecycle and registry
  // primaries are re-elected below because a sibling backend or commons module
  // may still be alive.
  ModelRegistryAdapter.unregisterModule(mod);
  if (releasedCapabilities.includes('commons')) {
    DownloadAdapter.clearDefaultModule();
    SDKEventStreamAdapter.clearDefaultModule();
  }
  ModalityProtoAdapter.unregisterModuleCapabilities(releasedCapabilities, mod);
  for (const restored of restoredCapabilities) {
    ModalityProtoAdapter.registerModuleCapabilities([restored.capability], restored.module);
  }
  const restoredCommons = _moduleByCapability.get('commons');
  if (releasedCapabilities.includes('commons') && restoredCommons) {
    DownloadAdapter.setDefaultModule(restoredCommons);
    SDKEventStreamAdapter.setDefaultModule(restoredCommons);
  }
  reelectLifecycleAndRegistryPrimary();
}

/**
 * Look up the module that owns a given capability. Returns null when no
 * backend has registered for that capability — facade verbs should throw
 * a `SDKException.backendNotAvailable(...)` in that case to surface the
 * missing backend clearly.
 */
export function getModuleForCapability(
  cap: WasmCapability,
): EmscriptenRunanywhereModule | null {
  return _moduleByCapability.get(cap) ?? null;
}

/**
 * Enumerate every distinct WASM module currently registered. Useful when
 * a caller needs to fan an operation out across every backend (e.g. OPFS
 * MEMFS restore — see `OPFSBridge.restoreToMemfsAll`), because each
 * Emscripten WASM owns a private MEMFS and writing into one is invisible
 * to another.
 *
 * Returns an empty array when no backend has registered. Order is not
 * guaranteed; callers should treat the list as a set.
 */
export function getAllRegisteredModules(): EmscriptenRunanywhereModule[] {
  const unique = new Set<EmscriptenRunanywhereModule>();
  for (const owners of _modulesByCapability.values()) {
    for (const mod of owners) unique.add(mod);
  }
  return Array.from(unique);
}

/** Clear the entire registry during full SDK shutdown. */
export function clearRunanywhereModule(): void {
  _moduleByCapability.clear();
  _modulesByCapability.clear();
  // Framework→module map mirrors the capability registry and is populated
  // alongside it via `registerWasmModule(_, _, frameworks)`. Without this
  // clear, a fresh tab boot followed by re-registration would see stale
  // framework rows from the previous session (e.g. plugin-route lookups
  // routing 'llamacpp' to a torn-down WASM instance).
  _moduleByFramework.clear();
  _modulesByFramework.clear();
  DownloadAdapter.clearDefaultModule();
  ModelLifecycleAdapter.clearDefaultModule();
  ModelRegistryAdapter.clearDefaultModule();
  ModalityProtoAdapter.clearDefaultModule();
  SDKEventStreamAdapter.clearDefaultModule();
}

/**
 * Canonical fallback precedence for `tryRunanywhereModule()` when no
 * 'commons' module is registered. Insertion order of `_moduleByCapability`
 * is not load-order deterministic (backends may register/unregister at
 * runtime), so callers used to see different "primary" modules based on
 * which backend booted first. Pin the order explicitly: LLM-bearing
 * backends first (most likely to expose SDK-state proto exports), then
 * speech, then the remaining specialized capabilities.
 */
const FALLBACK_CAPABILITY_PRECEDENCE: readonly WasmCapability[] = [
  'llm',
  'vlm',
  'embedding',
  'segmentation',
  'vocoder',
  'rag',
  'tool-calling',
  'structured-output',
  'lora',
  'diffusion',
  'stt',
  'tts',
  'vad',
  'voice-agent',
];

/**
 * Return the COMMONS module, if registered. This is the closest analog of
 * the old monolithic singleton — facade reads that touch SDK-state surface
 * (init, auth, model registry, lifecycle, events) route through this.
 * Modality verbs should use `getModuleForCapability(...)` instead.
 */
export function tryRunanywhereModule(): EmscriptenRunanywhereModule | null {
  // Prefer the commons module; fall back to a canonical precedence order
  // (see FALLBACK_CAPABILITY_PRECEDENCE) so the SDK-state APIs continue to
  // work when only a backend (not commons) is loaded. Deterministic
  // precedence (rather than insertion order) keeps `tryRunanywhereModule`
  // stable across register/unregister churn.
  const commons = _moduleByCapability.get('commons');
  if (commons) return commons;
  for (const cap of FALLBACK_CAPABILITY_PRECEDENCE) {
    const candidate = _moduleByCapability.get(cap);
    if (candidate) return candidate;
  }
  return null;
}

/**
 * Typed accessor for the runanywhere WASM module.
 *
 * Throws a descriptive error if the module hasn't been installed yet —
 * better than getting a TypeError on `undefined._rac_voice_agent_*` at
 * a call site.
 *
 * Usage:
 *
 *     import { runanywhereModule } from '../runtime/EmscriptenModule';
 *     const rc = runanywhereModule._rac_voice_agent_set_proto_callback(h, 0, 0);
 */
export const runanywhereModule: EmscriptenRunanywhereModule = new Proxy(
  {} as EmscriptenRunanywhereModule,
  {
    get(_target, prop) {
      const mod = tryRunanywhereModule();
      if (mod == null) {
        throw new Error(
          `RunAnywhere WASM module is not initialized. Call ` +
            `registerWasmModule(capabilities, mod) during app init before touching ` +
            `any RunAnywhere.* API that reaches into C++. Property accessed: ${String(prop)}`,
        );
      }
      const value = (mod as unknown as Record<string | symbol, unknown>)[prop];
      // Bind methods so `this` is the real Emscripten module.
      return typeof value === 'function'
        ? (value as (...args: unknown[]) => unknown).bind(mod)
        : value;
    },
  },
);
