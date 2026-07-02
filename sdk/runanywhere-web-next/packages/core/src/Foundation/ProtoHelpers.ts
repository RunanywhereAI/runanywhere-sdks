import type { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';

export function tokensUsed(r: LLMGenerationResult): number {
  return r.tokensGenerated;
}

export function latencyMs(r: LLMGenerationResult): number {
  return r.generationTimeMs;
}
