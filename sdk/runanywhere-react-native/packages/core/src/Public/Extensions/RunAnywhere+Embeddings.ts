/**
 * RunAnywhere+Embeddings.ts
 *
 * Embeddings extension (B10).
 *
 * STUB: this extension exposes the public `embed(...)` surface on
 * `RunAnywhere`, but the Nitro spec method `embed` / `embeddingsCreate`
 * / `embeddingsDestroy` has not been added to
 * `src/specs/RunAnywhereCore.nitro.ts` yet — regenerating the spec
 * requires running the Nitro codegen (`npm run nitro:generate`) and
 * implementing the matching iOS/Android JSI binding on the native side.
 *
 * TODO(B10): once the Nitro regen + native bindings land:
 *   1. Add three methods to RunAnywhereCore.nitro.ts:
 *        embeddingsCreate(modelId: string): Promise<number>  // handle
 *        embeddingsEmbed(
 *          handle: number, text: string, optionsJson: string
 *        ): Promise<ArrayBuffer>  // serialized EmbeddingsResult proto
 *        embeddingsDestroy(handle: number): void
 *   2. Implement the JSI bindings on iOS (Swift) and Android
 *      (JNI) by forwarding to rac_embeddings_create /
 *      rac_embeddings_embed / rac_embeddings_destroy.
 *   3. Replace the throw below with a real call that:
 *        - Caches the handle keyed on modelId (closure-scoped Map).
 *        - Serializes EmbeddingsOptions via @runanywhere/proto-ts.
 *        - Decodes EmbeddingsResult.decode(new Uint8Array(buffer)).
 *
 * Reference: sdk/runanywhere-swift/.../Public/Extensions/RunAnywhere+Embeddings.swift
 */

import type {
  EmbeddingsOptions,
  EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';

/**
 * Generate an embedding vector for a single text.
 *
 * Matches Swift: `RunAnywhere.embed(text:modelId:options:)`.
 *
 * @param text - The input text to embed.
 * @param modelId - The embeddings model identifier (registry id or path).
 * @param options - Optional per-call overrides.
 * @returns An {@link EmbeddingsResult} with one vector in `vectors[0]`.
 * @throws Error with a TODO(B10) marker until the Nitro spec + native
 *         bindings land.
 */
export async function embed(
  text: string,
  modelId: string,
  options?: EmbeddingsOptions
): Promise<EmbeddingsResult> {
  // Reference the args so lint/tsc don't flag them as unused while
  // this is a stub.
  void text;
  void modelId;
  void options;
  throw new Error(
    'TODO(B10): RunAnywhere.embed is not wired yet on React Native. ' +
      'The Nitro spec method (embeddingsCreate / embeddingsEmbed / ' +
      'embeddingsDestroy) and matching iOS/Android JSI bindings still ' +
      'need to be added. See the file header for the required pieces.'
  );
}
