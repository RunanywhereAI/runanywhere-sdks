/**
 * Cosine similarity via SDK commons (`rac_embeddings_similarity`).
 * The app never computes the formula locally — same contract as the legacy
 * renderer (`ra.embeddings.cosineSimilarity`).
 */
export type CosineVector = Float32Array | { readonly vector: Float32Array };

export function cosineSimilarity(a: CosineVector, b: CosineVector): Promise<number> {
  const lhs = a instanceof Float32Array ? a : a.vector;
  const rhs = b instanceof Float32Array ? b : b.vector;
  return window.runanywhere.embeddings.cosineSimilarity(lhs, rhs);
}
