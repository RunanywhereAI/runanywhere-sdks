/**
 * LlmThinking.ts — Web (WASM) facade over the rac_llm_thinking C ABI.
 *
 * v3-readiness Phase A11 / GAP 08 #6. Cross-SDK parity with:
 *   - Swift: CppBridge+LLMThinking.swift / ThinkingContentParser
 *   - Kotlin: CppBridgeLlmThinking
 *   - Dart: LlmThinking (capabilities/llm/llm_thinking.dart)
 *   - RN:   Features/LLM/LlmThinking.ts (Nitro-backed)
 *
 * Behavior is byte-for-byte identical across all 5 SDKs — the same
 * C ABI fires the same arena-backed parser in every case.
 *
 * Internals: wraps `_rac_llm_{extract,strip,split}_thinking` via
 * `_malloc` + `stringToUTF8` + `HEAPU32` reads. No ccall — the direct
 * pointer dance is straightforward here and avoids ccall's string-
 * copying overhead for hot-path tokens.
 */

import { runanywhereModule } from '../../runtime/EmscriptenModule';

/** Result of {@link LlmThinking.extract}. */
export interface LlmThinkingExtraction {
  /** Text outside the think block (never null). Empty when input is only a `<think>...</think>`. */
  response: string;
  /** Text inside the first think block, or `null` when no block was found. */
  thinking: string | null;
}

/** Result of {@link LlmThinking.splitTokens}. */
export interface LlmThinkingTokenSplit {
  thinkingTokens: number;
  responseTokens: number;
}

// =============================================================================
// Heap marshalling helpers
// =============================================================================

/** Copy a JS string into a freshly-allocated NUL-terminated WASM buffer.
 *  Caller is responsible for `_free`-ing the returned pointer. */
function allocUtf8(s: string): number {
  const m = runanywhereModule;
  const byteLen = m.lengthBytesUTF8(s) + 1; // +1 for NUL
  const ptr = m._malloc(byteLen);
  m.stringToUTF8(s, ptr, byteLen);
  return ptr;
}

/** Read a length-bounded UTF-8 string from `ptr` — the C ABI returns
 *  a (ptr, length) pair where `ptr` may not be NUL-terminated at
 *  `length` (the thread_local arena could reuse bytes past it). */
function readUtf8(ptr: number, len: number): string {
  if (ptr === 0 || len === 0) return '';
  const m = runanywhereModule;
  const bytes = m.HEAPU8.subarray(ptr, ptr + len);
  // TextDecoder is the fast path in modern browsers.
  return new TextDecoder('utf-8').decode(bytes);
}

// =============================================================================
// Public facade
// =============================================================================

/**
 * Pure utility around the `rac_llm_thinking` C ABI.
 *
 * Each method is synchronous. The C ABI call is microsecond-fast and
 * the TS-side marshalling is a few heap writes + reads; no Promise
 * needed. This matches the Swift/Kotlin/Dart signatures (only RN is
 * async, and only because Nitro HybridObjects always return Promises).
 */
export class LlmThinking {
  private constructor() {}

  /** Split a full LLM response on the FIRST `<think>...</think>` block. */
  static extract(text: string): LlmThinkingExtraction {
    const m = runanywhereModule;
    const textPtr = allocUtf8(text);
    // Slot layout (5 x uint32):
    //   [0] out_response*   (char**)
    //   [1] out_resp_len    (size_t*)
    //   [2] out_thinking*   (char**)
    //   [3] out_think_len   (size_t*)
    const outs = m._malloc(4 * 4);
    try {
      // Zero-init so C can detect unset slots.
      m.HEAPU32[(outs >> 2) + 0] = 0;
      m.HEAPU32[(outs >> 2) + 1] = 0;
      m.HEAPU32[(outs >> 2) + 2] = 0;
      m.HEAPU32[(outs >> 2) + 3] = 0;

      const rc = m._rac_llm_extract_thinking(
        textPtr,
        outs + 0,
        outs + 4,
        outs + 8,
        outs + 12,
      );
      if (rc !== 0) {
        throw new Error(`rac_llm_extract_thinking failed: ${rc}`);
      }
      const respPtr  = m.HEAPU32[(outs >> 2) + 0];
      const respLen  = m.HEAPU32[(outs >> 2) + 1];
      const thinkPtr = m.HEAPU32[(outs >> 2) + 2];
      const thinkLen = m.HEAPU32[(outs >> 2) + 3];

      const response = readUtf8(respPtr, respLen);
      const thinking = thinkPtr === 0 ? null : readUtf8(thinkPtr, thinkLen);
      return { response, thinking };
    } finally {
      m._free(outs);
      m._free(textPtr);
    }
  }

  /** Remove ALL `<think>...</think>` blocks from text. */
  static strip(text: string): string {
    const m = runanywhereModule;
    const textPtr = allocUtf8(text);
    const outs = m._malloc(2 * 4); // out_stripped*, out_stripped_len
    try {
      m.HEAPU32[(outs >> 2) + 0] = 0;
      m.HEAPU32[(outs >> 2) + 1] = 0;
      const rc = m._rac_llm_strip_thinking(textPtr, outs + 0, outs + 4);
      if (rc !== 0) throw new Error(`rac_llm_strip_thinking failed: ${rc}`);
      const outPtr = m.HEAPU32[(outs >> 2) + 0];
      const outLen = m.HEAPU32[(outs >> 2) + 1];
      if (outPtr === 0) return '';
      return readUtf8(outPtr, outLen);
    } finally {
      m._free(outs);
      m._free(textPtr);
    }
  }

  /** Apportion a total token count between thinking + response segments. */
  static splitTokens(params: {
    totalCompletionTokens: number;
    response?: string;
    thinking?: string;
  }): LlmThinkingTokenSplit {
    const m = runanywhereModule;
    const respPtr =
      params.response == null || params.response.length === 0
        ? 0
        : allocUtf8(params.response);
    const thinkPtr =
      params.thinking == null || params.thinking.length === 0
        ? 0
        : allocUtf8(params.thinking);
    const outs = m._malloc(2 * 4); // out_thinking_tokens (int32), out_response_tokens (int32)
    try {
      m.HEAP32[(outs >> 2) + 0] = 0;
      m.HEAP32[(outs >> 2) + 1] = 0;
      const rc = m._rac_llm_split_thinking_tokens(
        params.totalCompletionTokens,
        respPtr,
        thinkPtr,
        outs + 0,
        outs + 4,
      );
      if (rc !== 0) {
        throw new Error(`rac_llm_split_thinking_tokens failed: ${rc}`);
      }
      return {
        thinkingTokens: m.HEAP32[(outs >> 2) + 0] ?? 0,
        responseTokens: m.HEAP32[(outs >> 2) + 1] ?? 0,
      };
    } finally {
      m._free(outs);
      if (respPtr !== 0) m._free(respPtr);
      if (thinkPtr !== 0) m._free(thinkPtr);
    }
  }
}
