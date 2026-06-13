/**
 * EmbeddingsProto+Helpers.ts
 *
 * Ergonomic helpers for canonical Embeddings proto types.
 *
 * Mirrors Swift `EmbeddingsProto+Helpers.swift`
 * (`RAEmbeddingVector.cosineSimilarity(with:)` / `computeNorm()`).
 */

import type { EmbeddingVector } from '@runanywhere/proto-ts/embeddings_options';

function l2(values: number[]): number {
  let sumSquares = 0;
  for (const value of values) sumSquares += value * value;
  return Math.sqrt(sumSquares);
}

/**
 * Cosine similarity between two embedding vectors.
 *
 * Mirrors Swift `RAEmbeddingVector.cosineSimilarity(with:)`
 * (EmbeddingsProto+Helpers.swift:18-26): returns 0 for mismatched lengths,
 * empty vectors, or zero norms; uses the backend-provided `norm` when
 * present and recomputes the L2 norm otherwise.
 */
export function cosineSimilarity(
  a: EmbeddingVector,
  b: EmbeddingVector
): number {
  if (a.values.length !== b.values.length || a.values.length === 0) return 0;
  let dot = 0;
  for (let i = 0; i < a.values.length; i++) {
    dot += a.values[i]! * b.values[i]!;
  }
  const aNorm = a.norm !== undefined ? a.norm : l2(a.values);
  const bNorm = b.norm !== undefined ? b.norm : l2(b.values);
  if (aNorm <= 0 || bNorm <= 0) return 0;
  return dot / (aNorm * bNorm);
}

/**
 * L2 norm of an embedding vector's values.
 * Mirrors Swift `RAEmbeddingVector.computeNorm()`.
 */
export function computeNorm(vector: EmbeddingVector): number {
  return l2(vector.values);
}
