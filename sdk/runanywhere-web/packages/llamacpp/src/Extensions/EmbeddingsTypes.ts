/**
 * RunAnywhere Web SDK - Embeddings Types (LlamaCpp Backend).
 *
 * Wave 2: This module replaces the deleted hand-rolled types and re-exports
 * the proto-ts canonical shapes. The Web SDK additionally exposes a
 * Float32Array-typed `EmbeddingVector` for direct interop with browser audio
 * / numeric APIs (proto carries `values: number[]`).
 *
 * Source of truth (wire shape): idl/embeddings_options.proto
 * → @runanywhere/proto-ts/embeddings_options
 */

// Proto canonical types (re-exported with their canonical names).
export type {
  EmbeddingsConfiguration,
  EmbeddingsOptions,
} from '@runanywhere/proto-ts/embeddings_options';

/** Web-only embedding vector — Float32Array for direct DSP interop. */
export interface EmbeddingVector {
  /** Dense float vector */
  data: Float32Array;
  /** Dimension */
  dimension: number;
}

/** Web-only embeddings result — uses Float32Array vectors. */
export interface EmbeddingsResult {
  /** Array of embedding vectors (one per input text) */
  vectors: EmbeddingVector[];
  /** Embedding dimension */
  dimension: number;
  /** Processing time in milliseconds */
  processingTimeMs: number;
  /** Total tokens processed */
  tokensUsed: number;
}

export enum EmbeddingsNormalize {
  None = 0,
  L2 = 1,
}

export enum EmbeddingsPooling {
  Mean = 0,
  CLS = 1,
  Last = 2,
}

/**
 * Per-call ergonomic options. Differs from proto's `EmbeddingsOptions` by
 * exposing the Web-side normalize/pooling enums (proto stores normalize as a
 * bool only).
 */
export interface EmbeddingsCallOptions {
  /** Normalization mode override */
  normalize?: EmbeddingsNormalize;
  /** Pooling strategy override */
  pooling?: EmbeddingsPooling;
}
