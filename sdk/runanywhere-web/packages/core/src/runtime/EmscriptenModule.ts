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
