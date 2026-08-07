// Public option objects and their mapping onto the generated protos. Public
// names follow the cross-SDK spec; defaults come from the rac_default
// annotations on LLMGenerationOptions in idl/llm_options.proto.

import type { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import { ReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';

/** Reasoning/thinking controls. Mirrors Swift `ReasoningOptions`. */
export interface ReasoningOption {
  /** `on` requests thinking on models where it is optional; `off` suppresses it. */
  mode?: 'on' | 'off';
  /** Keep the reasoning inline in the answer text rather than splitting it out. */
  includeInOutput?: boolean;
  /** Custom think-tag name (without brackets), e.g. "think". */
  pattern?: string;
}

/** Per-request generation controls for llm and vlm. */
export interface LlmOptions {
  /** Model id to run; if not already resident it is loaded (and downloaded) first. */
  model?: string;
  maxOutputTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  minP?: number;
  repetitionPenalty?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  seed?: number;
  stopSequences?: string[];
  systemPrompt?: string;
  reasoning?: ReasoningOption;
  /** Thread count for CPU decode; absent uses the engine default. */
  threads?: number;
}

/** Sampling defaults, transcribed from the proto rac_default annotations. */
export const LLM_DEFAULTS = {
  maxOutputTokens: 512,
  temperature: 0.7,
  topP: 1.0,
} as const;

/** Map {@link LlmOptions} onto an LLMGenerationOptions partial for fromPartial(). */
export function toLlmGenerationOptions(o: LlmOptions = {}): Partial<LLMGenerationOptions> {
  const out: Partial<LLMGenerationOptions> = {
    maxOutputTokens: o.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
    temperature: o.temperature ?? LLM_DEFAULTS.temperature,
    topP: o.topP ?? LLM_DEFAULTS.topP,
  };
  if (o.topK !== undefined) out.topK = o.topK;
  if (o.minP !== undefined) out.minP = o.minP;
  if (o.repetitionPenalty !== undefined) out.repetitionPenalty = o.repetitionPenalty;
  if (o.frequencyPenalty !== undefined) out.frequencyPenalty = o.frequencyPenalty;
  if (o.presencePenalty !== undefined) out.presencePenalty = o.presencePenalty;
  if (o.seed !== undefined) out.seed = o.seed;
  if (o.systemPrompt !== undefined) out.systemPrompt = o.systemPrompt;
  if (o.threads !== undefined) out.nThreads = o.threads;
  if (o.stopSequences && o.stopSequences.length) out.stopSequences = [...o.stopSequences];
  if (o.reasoning) {
    out.reasoning = {
      mode:
        o.reasoning.mode === 'on'
          ? ReasoningMode.REASONING_MODE_ON
          : o.reasoning.mode === 'off'
            ? ReasoningMode.REASONING_MODE_OFF
            : ReasoningMode.REASONING_MODE_UNSPECIFIED,
      // Default true so thoughts stream to the caller as THOUGHT events (a live
      // reasoning view), not just a final blob. Callers can opt out explicitly.
      includeInOutput: o.reasoning.includeInOutput ?? true,
      ...(o.reasoning.pattern
        ? { pattern: { openTag: `<${o.reasoning.pattern}>`, closeTag: `</${o.reasoning.pattern}>` } }
        : {}),
    };
  }
  return out;
}
