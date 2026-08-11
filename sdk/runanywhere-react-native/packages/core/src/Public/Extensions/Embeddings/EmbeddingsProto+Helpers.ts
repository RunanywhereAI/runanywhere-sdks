/**
 * EmbeddingsProto+Helpers.ts
 *
 * Ergonomic helpers for canonical Embeddings proto types.
 * Norm / cosine similarity are owned by commons
 * (`rac_embeddings_norm` / `rac_embeddings_similarity`) via the Nitro bridge.
 */

import type { EmbeddingVector } from '@runanywhere/proto-ts/embeddings_options';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  isNativeModuleAvailable,
  requireNativeModule,
} from '../../../native';

function requireEmbeddingsNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

function floatValuesToBytes(values: number[]): ArrayBuffer {
  const out = new Float32Array(values.length);
  for (let i = 0; i < values.length; i++) {
    out[i] = values[i]!;
  }
  return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength);
}

/**
 * Cosine similarity between two embedding vectors via
 * `rac_embeddings_similarity`. Returns 0 for mismatched lengths, empty
 * vectors, or zero norms (commons contract).
 */
export function cosineSimilarity(
  a: EmbeddingVector,
  b: EmbeddingVector
): number {
  return requireEmbeddingsNative().embeddingsSimilarity(
    floatValuesToBytes(a.values),
    floatValuesToBytes(b.values)
  );
}

/**
 * L2 norm of an embedding vector's values via `rac_embeddings_norm`.
 */
export function computeNorm(vector: EmbeddingVector): number {
  return requireEmbeddingsNative().embeddingsNorm(
    floatValuesToBytes(vector.values)
  );
}
