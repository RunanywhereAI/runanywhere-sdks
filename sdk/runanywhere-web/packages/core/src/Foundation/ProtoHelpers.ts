/**
 * RunAnywhere Web SDK - Proto Helpers.
 *
 * Wave 2: The Web SDK now uses proto-ts types directly (no Web-only
 * duplicates). The previous `*toProto` / `*FromProto` bridges that translated
 * between Web and proto field names are no longer needed because the Web call
 * sites use proto field names directly. This module retains a small set of
 * accessor helpers callers may use for symmetry with other SDKs.
 */

import type { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';

// ---------------------------------------------------------------------------
// LLM helpers — accessors for proto field names that match Web event payloads.
// ---------------------------------------------------------------------------

/** Read the "tokens generated" count from a proto LLMGenerationResult. */
export function tokensUsed(r: LLMGenerationResult): number {
  return r.tokensGenerated;
}

/** Read the "generation time" from a proto LLMGenerationResult, in ms. */
export function latencyMs(r: LLMGenerationResult): number {
  return r.generationTimeMs;
}
