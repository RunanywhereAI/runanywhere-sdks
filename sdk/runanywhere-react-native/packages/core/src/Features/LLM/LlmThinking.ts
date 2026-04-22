/**
 * LlmThinking.ts
 *
 * v3-readiness Phase A10 / GAP 08 #6. TS facade over the
 * `rac_llm_thinking` C ABI via the Nitro RunAnywhereCore HybridObject.
 * Matches Swift's ThinkingContentParser + Kotlin's CppBridgeLlmThinking
 * + Dart's LlmThinking exactly.
 *
 * Internals: the C++ side (HybridRunAnywhereCore.cpp) returns the
 * tuple-shaped results as JSON strings; this TS wrapper does the
 * trivial JSON.parse so consumers get typed values without ever
 * seeing the wire format.
 */

import type { RunAnywhereCore } from '../../specs/RunAnywhereCore.nitro';
import { getNitroModulesProxySync } from '../../native/NitroModulesGlobalInit';

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

let _cachedCore: RunAnywhereCore | null = null;

function resolveCore(): RunAnywhereCore {
  if (_cachedCore != null) return _cachedCore;
  const NitroProxy = getNitroModulesProxySync();
  if (NitroProxy == null) {
    throw new Error(
      'NitroModules unavailable; LlmThinking requires RunAnywhereCore to be initialized.',
    );
  }
  _cachedCore = NitroProxy.createHybridObject('RunAnywhereCore') as RunAnywhereCore;
  return _cachedCore;
}

/**
 * Pure utility around the `rac_llm_thinking` C ABI — mirror of
 * Swift's `ThinkingContentParser`, Kotlin's `CppBridgeLlmThinking`,
 * and Dart's `LlmThinking`. Behavior is byte-for-byte identical across
 * all 5 SDKs.
 *
 * Each method is async because the underlying Nitro HybridObject
 * returns a Promise. The C ABI call itself is synchronous +
 * microsecond-fast; the Promise is just the Nitro transport shape.
 */
export class LlmThinking {
  private constructor() {}

  /**
   * Split a full LLM response on the FIRST `<think>...</think>` block.
   *
   * @param text Full LLM response text.
   * @returns Extraction result: the visible response + optional
   *   thinking chunk (null when no block was found).
   * @throws Error on JSON parse failure (shouldn't happen — the C++
   *   side always returns well-formed JSON).
   */
  static async extract(text: string): Promise<LlmThinkingExtraction> {
    const json = await resolveCore().llmExtractThinking(text);
    const parsed = JSON.parse(json) as Partial<LlmThinkingExtraction>;
    return {
      response: parsed.response ?? '',
      thinking: parsed.thinking ?? null,
    };
  }

  /**
   * Remove ALL `<think>...</think>` blocks (and trailing unclosed
   * `<think>`) from text.
   *
   * @param text Full LLM response text.
   * @returns The trimmed remainder. Empty string if C ABI failed.
   */
  static async strip(text: string): Promise<string> {
    return resolveCore().llmStripThinking(text);
  }

  /**
   * Apportion a total token count between thinking + response segments
   * proportionally by character length.
   *
   * If `thinking` is empty, returns `{ thinkingTokens: 0,
   * responseTokens: totalCompletionTokens }`. Else: proportional split
   * with `thinkingTokens + responseTokens == totalCompletionTokens`.
   *
   * @throws Error on JSON parse failure.
   */
  static async splitTokens(params: {
    totalCompletionTokens: number;
    response?: string;
    thinking?: string;
  }): Promise<LlmThinkingTokenSplit> {
    const json = await resolveCore().llmSplitThinkingTokens(
      params.totalCompletionTokens,
      params.response ?? '',
      params.thinking ?? '',
    );
    const parsed = JSON.parse(json) as { thinking?: number; response?: number };
    return {
      thinkingTokens: parsed.thinking ?? 0,
      responseTokens: parsed.response ?? params.totalCompletionTokens,
    };
  }
}
