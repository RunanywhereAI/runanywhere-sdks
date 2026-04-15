/**
 * EmbeddingsTypes
 * -----------------------------------------------------------------------------
 * Configuration types for RAG text embeddings.
 *
 * Mirrors the native layout in
 * `sdk/runanywhere-commons/include/rac/backends/rac_embeddings_onnx.h` so the
 * same ONNX model files work on web and native.
 *
 * The implementation (`RunAnywhere+Embeddings.ts`) runs a BERT-style encoder
 * using `onnxruntime-web` via ORTRuntimeBridge and produces fixed-dimension
 * embedding vectors suitable for cosine-similarity search.
 */

export interface EmbeddingsModelConfig {
  /** Path / URL / ArrayBuffer for the encoder .onnx (e.g. all-MiniLM-L6-v2). */
  model: string | ArrayBuffer | Uint8Array;
  /**
   * Path / URL / ArrayBuffer for the tokenizer vocabulary (vocab.txt or
   * tokenizer.json). Tokenization is the non-trivial bit — see implementation
   * notes in `RunAnywhere+Embeddings.ts`.
   */
  tokenizer: string | ArrayBuffer | Uint8Array;
  /** Dimensionality of the output embedding. Default: 384 (all-MiniLM-L6-v2). */
  embeddingDim?: number;
  /** Max input tokens. Default: 512. */
  maxSeqLength?: number;
  /** L2-normalize the output vector. Default: true (standard for RAG). */
  normalize?: boolean;
}

export interface EmbedOptions {
  /**
   * Override the config's normalize flag for this call.
   */
  normalize?: boolean;
}

export interface EmbeddingResult {
  /** Fixed-dimension embedding vector. */
  vector: Float32Array;
  /** Dimensionality — always equals `EmbeddingsModelConfig.embeddingDim`. */
  dim: number;
  /** Token count actually fed to the encoder (after truncation / padding). */
  tokenCount: number;
}
