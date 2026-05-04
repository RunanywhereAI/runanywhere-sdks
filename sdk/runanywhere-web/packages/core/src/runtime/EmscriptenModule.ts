/**
 * EmscriptenModule.ts
 *
 * v3-readiness Phase A4. Typed surface over the Emscripten-compiled
 * RACommons module so TypeScript call sites (VoiceAgentStreamAdapter,
 * LlmThinking, future ccall wrappers) can reference `runanywhereModule`
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
import { ModelLifecycleAdapter } from '../Adapters/ModelLifecycleAdapter';
import { ModalityProtoAdapter } from '../Adapters/ModalityProtoAdapter';
import { SDKEventStreamAdapter } from '../Adapters/SDKEventStreamAdapter';

/**
 * Minimal subset of the Emscripten Module object that this SDK uses.
 * Add exported-function signatures here as they're wired through the
 * TS surface (e.g. `_rac_llm_extract_thinking` in Phase A11).
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

  _rac_lora_register_proto?(
    registry: number,
    entryBytes: number,
    entrySize: number,
    outEntry: number,
  ): number;
  _rac_lora_compatibility_proto?(
    llmComponent: number,
    configBytes: number,
    configSize: number,
    outResult: number,
  ): number;
  _rac_lora_load_proto?(
    llmComponent: number,
    configBytes: number,
    configSize: number,
    outInfo: number,
  ): number;
  _rac_lora_remove_proto?(
    llmComponent: number,
    configBytes: number,
    configSize: number,
    outInfo: number,
  ): number;
  _rac_lora_clear_proto?(llmComponent: number, outInfo: number): number;

  // -----------------------------------------------------------------------------
  // LLM Thinking (v3 Phase A11 / GAP 08 #6)
  // -----------------------------------------------------------------------------
  // Reach these via ccall wrappers in LlmThinking.ts — they take char*
  // pointers via _malloc + stringToUTF8 and out-pointers via _malloc for
  // out-char** / out-size_t / out-int32_t slots.

  /**
   * `rac_result_t rac_llm_extract_thinking(
   *    const char* text,
   *    const char** out_response, size_t* out_response_len,
   *    const char** out_thinking, size_t* out_thinking_len);`
   */
  _rac_llm_extract_thinking(
    textPtr: number,
    outRespPtrPtr: number,
    outRespLenPtr: number,
    outThinkPtrPtr: number,
    outThinkLenPtr: number,
  ): number;

  /**
   * `rac_result_t rac_llm_strip_thinking(
   *    const char* text,
   *    const char** out_stripped, size_t* out_stripped_len);`
   */
  _rac_llm_strip_thinking(
    textPtr: number,
    outPtrPtr: number,
    outLenPtr: number,
  ): number;

  /**
   * `rac_result_t rac_llm_split_thinking_tokens(
   *    int32_t total_completion_tokens,
   *    const char* response_text,
   *    const char* thinking_text,
   *    int32_t* out_thinking_tokens,
   *    int32_t* out_response_tokens);`
   */
  _rac_llm_split_thinking_tokens(
    totalCompletionTokens: number,
    respTextPtr: number,
    thinkTextPtr: number,
    outThinkingTokensPtr: number,
    outResponseTokensPtr: number,
  ): number;

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
  addFunction(fn: (...args: number[]) => number | void, signature: string): number;

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
  ) => unknown;
}

let _module: EmscriptenRunanywhereModule | null = null;

/**
 * Install the loaded Emscripten module so the rest of the SDK can
 * reach it. Call once during app init after your WASM loader resolves.
 */
export function setRunanywhereModule(mod: EmscriptenRunanywhereModule): void {
  _module = mod;
  DownloadAdapter.setDefaultModule(mod);
  ModelLifecycleAdapter.setDefaultModule(mod);
  ModalityProtoAdapter.setDefaultModule(mod);
  SDKEventStreamAdapter.setDefaultModule(mod);
}

/** Clear the singleton module during backend shutdown. */
export function clearRunanywhereModule(): void {
  DownloadAdapter.clearDefaultModule();
  ModelLifecycleAdapter.clearDefaultModule();
  ModalityProtoAdapter.clearDefaultModule();
  SDKEventStreamAdapter.clearDefaultModule();
  _module = null;
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
      if (_module == null) {
        throw new Error(
          `RunAnywhere WASM module is not initialized. Call ` +
            `setRunanywhereModule(mod) during app init before touching ` +
            `any RunAnywhere.* API that reaches into C++. Property accessed: ${String(prop)}`,
        );
      }
      const value = (_module as unknown as Record<string | symbol, unknown>)[prop];
      // Bind methods so `this` is the real Emscripten module.
      return typeof value === 'function'
        ? (value as (...args: unknown[]) => unknown).bind(_module)
        : value;
    },
  },
);
