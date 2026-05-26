/**
 * EmscriptenModule.ts
 *
 * v3-readiness Phase A4. Typed surface over the Emscripten-compiled
 * RACommons module so TypeScript call sites (VoiceAgentStreamAdapter,
 * future ccall wrappers) can reference `runanywhereModule`
 * without each site re-declaring the function signatures.
 *
 * Initialization pattern:
 *
 *     import { initRunanywhereModule } from '@runanywhere/web';
 *     await initRunanywhereModule(() => import('./runanywhere.wasm'));
 *     // now any RunAnywhere.* call can reach C++ via this module
 *
 * The actual WASM loader lives in each deployment harness (Vite,
 * webpack, the test runner etc.) — this file only exposes the typed
 * singleton + a setter so the core package stays pure-TS and doesn't
 * bundle its own loader.
 *
 * Matches the design intent called out in
 * `sdk/runanywhere-web/packages/core/src/Foundation/WASMBridge.ts`:
 * "Core is now pure TypeScript. The actual WASM bridge implementations
 *  live in each backend package".
 */

import { DownloadAdapter } from '../Adapters/DownloadAdapter';
import { HardwareAdapter } from '../Adapters/HardwareAdapter';
import { ModelLifecycleAdapter } from '../Adapters/ModelLifecycleAdapter';
import { ModelRegistryAdapter } from '../Adapters/ModelRegistryAdapter';
import { ModalityProtoAdapter } from '../Adapters/ModalityProtoAdapter';
import { SDKEventStreamAdapter } from '../Adapters/SDKEventStreamAdapter';

/**
 * Minimal subset of the Emscripten Module object that this SDK uses.
 * Add exported-function signatures here as they're wired through the
 * TS surface.
 */
export interface EmscriptenRunanywhereModule {
  // =============================================================================
  // Exported C functions (post-v3-readiness-PhaseA4)
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
   * v2 close-out Phase G-2:
   *
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

  _rac_vlm_process_proto?(
    handle: number,
    imageBytes: number,
    imageSize: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_vlm_process_stream_proto?(
    handle: number,
    imageBytes: number,
    imageSize: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
    outResult: number,
  ): number;
  _rac_vlm_cancel_proto?(handle: number): number;

  _rac_embeddings_embed_batch_proto?(
    handle: number,
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
   * pass2-syn-026: Session-based tool-calling ABI. The Web SDK uses these
   * (instead of the synchronous `_rac_tool_calling_run_loop_proto`) so that
   * TypeScript executors returning `Promise<ToolResult>` can be awaited
   * between commons-driven generate -> parse -> validate cycles.
   *
   * `_rac_tool_calling_session_create_proto(requestBytes, requestSize, callbackPtr, userData, outSessionHandle)`:
   *   callbackPtr is a function-table index obtained from `addFunction(fn, 'viii')`
   *   whose JS implementation receives `(eventBytesPtr, eventSize, userData)` and
   *   decodes a serialized `runanywhere.v1.ToolCallingSessionEvent`. Out-handle is
   *   written via the proto-buffer-or-uint64 contract (we pass a malloc'd 8-byte
   *   slot and read low/high 32-bit halves to reconstruct the uint64).
   */
  _rac_tool_calling_session_create_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
    outSessionHandlePtr: number,
  ): number;
  /**
   * `_rac_tool_calling_session_step_with_result_proto(requestBytes, requestSize)`:
   *   Accepts a serialized `runanywhere.v1.ToolCallingSessionStepWithResultRequest`
   *   and synchronously resumes the run loop. Any new events (further tool_call,
   *   final_result, or error) fire via the callback installed at session create.
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
   *   `_rac_sdk_event_unsubscribe` — accepts either number or bigint depending
   *   on whether the WASM module was linked with `-sWASM_BIGINT`).
   */
  _rac_tool_calling_session_destroy_proto?(
    sessionHandle: number | bigint,
  ): number;
  /**
   * pass2-syn-007: `_rac_tool_calling_session_cancel_proto(sessionHandle)`:
   *   Latches a cancel-requested flag on the session and asks the in-flight
   *   LifecycleLlmRef to interrupt the underlying backend `ops->generate`.
   *   Distinct from `_rac_tool_calling_session_destroy_proto` — the host
   *   should still call destroy once the in-flight call has resolved. Safe
   *   to call from any context; the WASM module is single-threaded so this
   *   actually fires after the current async tick returns control.
   */
  _rac_tool_calling_session_cancel_proto?(
    sessionHandle: number | bigint,
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
  _rac_auth_is_authenticated?(): number;
  _rac_auth_get_user_id?(): number;
  _rac_auth_get_organization_id?(): number;
  _rac_state_is_device_registered?(): number;

  // -----------------------------------------------------------------------------
  // Solutions runtime (T4.7 / T4.8) — `rac/solutions/rac_solution.h`
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
  // HTTP transport registry (Stage 3d — JS-side fetch adapter)
  // -----------------------------------------------------------------------------
  // The JS layer installs function-table indices (from `addFunction`) for the
  // transport vtable so HTTP requests route through `window.fetch()` directly
  // instead of bouncing through `emscripten_fetch`. See
  // `sdk/runanywhere-web/packages/core/src/Adapters/FetchHttpTransport.ts`
  // for the scaffold and `sdk/runanywhere-commons/src/infrastructure/http/
  // rac_http_client_emscripten.cpp` for the C side.
  //
  // Pass 0 for any slot to fall back to the emscripten_fetch adapter for
  // that op; all-zero unregisters and restores the libcurl/emscripten_fetch
  // default. Optional at type level: older WASM builds without the Stage 3d
  // export will simply be missing this symbol — callers check with
  // `typeof mod._rac_http_transport_register_from_js === 'function'`.
  _rac_http_transport_register_from_js?(
    requestSendPtr: number,
    requestStreamPtr: number,
    requestResumePtr: number,
  ): number;

  // -----------------------------------------------------------------------------
  // Model registry proto-byte ABI
  // -----------------------------------------------------------------------------
  // Optional because older Web WASM builds may only export the legacy struct
  // registry functions. ModelRegistryAdapter checks presence before calling.
  _rac_get_model_registry?(): number;
  _rac_model_registry_register_proto?(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_update_proto?(
    handle: number,
    protoBytes: number,
    protoSize: number,
  ): number;
  _rac_model_registry_get_proto?(
    handle: number,
    modelId: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_proto?(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_query_proto?(
    handle: number,
    queryProtoBytes: number,
    queryProtoSize: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_list_downloaded_proto?(
    handle: number,
    protoBytesOut: number,
    protoSizeOut: number,
  ): number;
  _rac_model_registry_remove_proto?(
    handle: number,
    modelId: number,
  ): number;
  _rac_model_registry_proto_free?(protoBytes: number): void;

  // -----------------------------------------------------------------------------
  // Hardware profile proto-byte ABI
  // -----------------------------------------------------------------------------
  _rac_hardware_profile_get?(protoBytesOut: number, protoSizeOut: number): number;
  _rac_hardware_profile_free?(protoBytes: number): void;
  _rac_hardware_get_accelerators?(protoBytesOut: number, protoSizeOut: number): number;
  _rac_hardware_set_accelerator_preference?(preference: number): number;

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
  _rac_sdk_event_subscribe?(callbackPtr: number, userData: number): number | bigint;
  _rac_sdk_event_unsubscribe?(subscriptionId: number | bigint): void;
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
  addFunction(fn: (...args: number[]) => number | bigint | void, signature: string): number;

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
//   - racommons-llamacpp.wasm  → 'llm', 'vlm', 'embedding', 'rag',
//                                 'diffusion', 'structured-output',
//                                 'tool-calling', 'lora'
//   - racommons-onnx-sherpa.wasm → 'stt', 'tts', 'vad'
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
  | 'rag'               // RAG pipeline (embeddings + retrieval)
  | 'diffusion'         // Diffusion (image generation)
  | 'structured-output' // Structured-output parse/validate/prepare-prompt
  | 'tool-calling'      // Tool-calling session ABI
  | 'lora'              // LoRA registry/apply/state
  | 'voice-agent';      // Voice-agent component (lives in same module as STT/TTS/VAD)

/**
 * Complete set of capabilities — used as the default for the legacy
 * `setRunanywhereModule()` alias, which registers a single module against
 * everything (matches pre-P4 monolithic behavior).
 */
const ALL_CAPABILITIES: readonly WasmCapability[] = [
  'commons',
  'llm',
  'vlm',
  'stt',
  'tts',
  'vad',
  'embedding',
  'rag',
  'diffusion',
  'structured-output',
  'tool-calling',
  'lora',
  'voice-agent',
];

/** Capability → module map. Backends register; facade looks up. */
const _moduleByCapability = new Map<WasmCapability, EmscriptenRunanywhereModule>();

/**
 * Framework → module map. Each backend WASM owns its own static
 * `s_plugin_registry`; `rac_plugin_route` only finds the framework's plugin
 * inside the WASM that ran the backend's `rac_backend_*_register()` call.
 * Web-only: native SDKs share a single process-wide plugin registry.
 */
const _moduleByFramework = new Map<string, EmscriptenRunanywhereModule>();

/** Look up which WASM owns the registered plugin for a model framework. */
export function getModuleForFramework(framework: string): EmscriptenRunanywhereModule | null {
  if (!framework) return null;
  return _moduleByFramework.get(framework.toLowerCase()) ?? null;
}

/**
 * Register a module against one or more capabilities. Replaces any prior
 * owner of those capabilities (last-writer-wins per capability). Also
 * forwards the module to the legacy `setDefaultModule()` adapter slots,
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
    _moduleByCapability.set(cap, mod);
  }
  for (const fw of frameworks) {
    if (fw) _moduleByFramework.set(fw.toLowerCase(), mod);
  }
  // Commons-level adapters (model registry, downloads, hardware, events)
  // follow the 'commons' capability — they target SDK-state surface exports
  // that live in racommons.wasm. Routing them by capability prevents a
  // later llamacpp/onnx bridge from clobbering the core's installed
  // adapters when it registers its own narrower capabilities.
  if (capabilities.includes('commons')) {
    DownloadAdapter.setDefaultModule(mod);
    HardwareAdapter.setDefaultModule(mod);
    ModelRegistryAdapter.setDefaultModule(mod);
    SDKEventStreamAdapter.setDefaultModule(mod);
    // Pre-bind ModelLifecycleAdapter to commons too — backend bridges
    // overwrite this when they register (see below), but a bare commons
    // module still answers `currentModel` / `componentLifecycleSnapshot`
    // for inspect-only use cases that don't require a plugin route.
    ModelLifecycleAdapter.setDefaultModule(mod);
  }
  // Model lifecycle + model registry routing — special case. The C++
  // `rac_plugin_route` call (driven by ModelLifecycleAdapter.load) lives
  // inside whichever WASM module's `s_plugin_registry` was populated by
  // the backend's `rac_backend_*_register()` call. The commons artifact
  // has NO backend plugins linked in, so routing model loads through
  // commons fails with "no backend route supports model". The model
  // REGISTRY (catalog) is per-module too, so it must point at the SAME
  // module as the lifecycle adapter or `loadModel` looks up the model in
  // an empty registry. When any backend bridge (LlamaCPP, ONNX) registers,
  // repoint BOTH adapters at THAT module. Last-writer-wins per
  // registration.
  const backendCapabilities: readonly WasmCapability[] = [
    'llm', 'vlm', 'stt', 'tts', 'vad', 'embedding', 'rag', 'diffusion',
  ];
  if (backendCapabilities.some((cap) => capabilities.includes(cap))) {
    ModelLifecycleAdapter.setDefaultModule(mod);
    ModelRegistryAdapter.setDefaultModule(mod);
  }
  // The ModalityProtoAdapter's internal per-capability slot is the canonical
  // dispatch table for the modality verbs (LLM/VLM/STT/TTS/VAD/embedding/
  // diffusion/rag/lora/voice-agent/structured-output). Push the module into
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
  for (const [fw, current] of Array.from(_moduleByFramework.entries())) {
    if (current === mod) _moduleByFramework.delete(fw);
  }
  const releasedCapabilities: WasmCapability[] = [];
  for (const [cap, current] of Array.from(_moduleByCapability.entries())) {
    if (current === mod) {
      _moduleByCapability.delete(cap);
      releasedCapabilities.push(cap);
    }
  }
  // Drop THIS module from the ModelRegistryAdapter broadcast set
  // regardless of which capability it owned — the broadcast list mirrors
  // every WASM that has ever called `setDefaultModule`. If commons was
  // released we also clear the other commons-level adapters (Download,
  // Hardware, ModelLifecycle, SDKEventStream) because they still track a
  // single primary slot. Re-registration by another module reinstalls them.
  ModelRegistryAdapter.unregisterModule(mod);
  if (releasedCapabilities.includes('commons')) {
    DownloadAdapter.clearDefaultModule();
    HardwareAdapter.clearDefaultModule();
    ModelLifecycleAdapter.clearDefaultModule();
    SDKEventStreamAdapter.clearDefaultModule();
  }
  ModalityProtoAdapter.unregisterModuleCapabilities(releasedCapabilities, mod);
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
  for (const mod of _moduleByCapability.values()) {
    unique.add(mod);
  }
  return Array.from(unique);
}

/**
 * @deprecated Prefer `registerWasmModule(capabilities, mod)` — calling
 * `setRunanywhereModule` claims every capability for the supplied module,
 * which collides with sibling backends that register their own narrower
 * capability sets. Kept for backwards compatibility with external apps that
 * used this API before the per-capability registry landed.
 */
export function setRunanywhereModule(mod: EmscriptenRunanywhereModule): void {
  registerWasmModule(ALL_CAPABILITIES, mod);
}

/** Clear the entire registry during full SDK shutdown. */
export function clearRunanywhereModule(): void {
  _moduleByCapability.clear();
  // Framework→module map mirrors the capability registry and is populated
  // alongside it via `registerWasmModule(_, _, frameworks)`. Without this
  // clear, a fresh tab boot followed by re-registration would see stale
  // framework rows from the previous session (e.g. plugin-route lookups
  // routing 'llamacpp' to a torn-down WASM instance).
  _moduleByFramework.clear();
  DownloadAdapter.clearDefaultModule();
  HardwareAdapter.clearDefaultModule();
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
            `registerWasmModule(capabilities, mod) (or the legacy ` +
            `setRunanywhereModule(mod)) during app init before touching ` +
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
