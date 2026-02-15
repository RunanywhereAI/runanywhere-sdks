/** RunAnywhere Web SDK - Embeddings Types */

export enum EmbeddingsNormalize {
  None = 0,
  L2 = 1,
}

export enum EmbeddingsPooling {
  Mean = 0,
  CLS = 1,
  Last = 2,
}

export interface EmbeddingVector {
  /** Dense float vector */
  data: Float32Array;
  /** Dimension */
  dimension: number;
}

export interface EmbeddingsResult {
  /** Array of embedding vectors (one per input text) */
  embeddings: EmbeddingVector[];
  /** Embedding dimension */
  dimension: number;
  /** Processing time in milliseconds */
  processingTimeMs: number;
  /** Total tokens processed */
  totalTokens: number;
}

export interface EmbeddingsOptions {
  /** Normalization mode override */
  normalize?: EmbeddingsNormalize;
  /** Pooling strategy override */
  pooling?: EmbeddingsPooling;
}
