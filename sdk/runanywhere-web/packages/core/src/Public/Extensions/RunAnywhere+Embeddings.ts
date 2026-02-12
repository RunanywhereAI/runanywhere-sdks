/**
 * RunAnywhere Web SDK - Embeddings Extension
 *
 * Adds text embedding generation capabilities via RACommons WASM.
 * Uses the rac_embeddings_component_* C API for model lifecycle
 * and embedding generation.
 *
 * Embeddings convert text into fixed-dimensional dense vectors
 * useful for semantic search, clustering, and RAG.
 *
 * Backend: llama.cpp (GGUF embedding models like nomic-embed-text)
 *
 * Usage:
 *   import { Embeddings } from '@runanywhere/web';
 *
 *   await Embeddings.loadModel('/models/nomic-embed-text-v1.5.Q4_K_M.gguf', 'nomic-embed');
 *   const result = await Embeddings.embed('Hello, world!');
 *   console.log('Dimension:', result.dimension);
 *   console.log('Vector:', result.embeddings[0].data);
 *
 *   // Batch embedding
 *   const batch = await Embeddings.embedBatch(['text1', 'text2', 'text3']);
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType } from '../../types/enums';

const logger = new SDKLogger('Embeddings');

let _embeddingsComponentHandle = 0;

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return WASMBridge.shared;
}

function ensureEmbeddingsComponent(): number {
  if (_embeddingsComponentHandle !== 0) return _embeddingsComponentHandle;

  const bridge = requireBridge();
  const m = bridge.module;
  const handlePtr = m._malloc(4);
  const result = m.ccall('rac_embeddings_component_create', 'number', ['number'], [handlePtr]) as number;

  if (result !== 0) {
    m._free(handlePtr);
    bridge.checkResult(result, 'rac_embeddings_component_create');
  }

  _embeddingsComponentHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);
  logger.debug('Embeddings component created');
  return _embeddingsComponentHandle;
}

// ---------------------------------------------------------------------------
// Embeddings Types
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Embeddings Extension
// ---------------------------------------------------------------------------

export const Embeddings = {
  /**
   * Load an embedding model (GGUF format).
   */
  async loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureEmbeddingsComponent();

    logger.info(`Loading embeddings model: ${modelId} from ${modelPath}`);
    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId, component: 'embeddings' });

    const pathPtr = bridge.allocString(modelPath);
    const idPtr = bridge.allocString(modelId);
    const namePtr = bridge.allocString(modelName ?? modelId);

    try {
      const result = m.ccall(
        'rac_embeddings_component_load_model', 'number',
        ['number', 'number', 'number', 'number'],
        [handle, pathPtr, idPtr, namePtr],
      ) as number;
      bridge.checkResult(result, 'rac_embeddings_component_load_model');
      logger.info(`Embeddings model loaded: ${modelId}`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId, component: 'embeddings' });
    } finally {
      bridge.free(pathPtr);
      bridge.free(idPtr);
      bridge.free(namePtr);
    }
  },

  /** Unload the embeddings model. */
  async unloadModel(): Promise<void> {
    if (_embeddingsComponentHandle === 0) return;
    const bridge = requireBridge();
    const result = bridge.module.ccall(
      'rac_embeddings_component_unload', 'number', ['number'], [_embeddingsComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_embeddings_component_unload');
    logger.info('Embeddings model unloaded');
  },

  /** Check if an embeddings model is loaded. */
  get isModelLoaded(): boolean {
    if (_embeddingsComponentHandle === 0) return false;
    try {
      return (WASMBridge.shared.module.ccall(
        'rac_embeddings_component_is_loaded', 'number', ['number'], [_embeddingsComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  },

  /**
   * Generate embedding for a single text.
   */
  async embed(text: string, options: EmbeddingsOptions = {}): Promise<EmbeddingsResult> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureEmbeddingsComponent();

    if (!Embeddings.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No embeddings model loaded. Call loadModel() first.');
    }

    logger.debug(`Embedding text (${text.length} chars)`);

    const textPtr = bridge.allocString(text);

    // Build rac_embeddings_options_t
    const optSize = 12;
    const optPtr = m._malloc(optSize);
    m.setValue(optPtr, options.normalize !== undefined ? options.normalize : -1, 'i32');
    m.setValue(optPtr + 4, options.pooling !== undefined ? options.pooling : -1, 'i32');
    m.setValue(optPtr + 8, 0, 'i32'); // n_threads = auto

    // Result struct
    const resSize = 32;
    const resPtr = m._malloc(resSize);

    try {
      const r = m.ccall(
        'rac_embeddings_component_embed', 'number',
        ['number', 'number', 'number', 'number'],
        [handle, textPtr, optPtr, resPtr],
      ) as number;
      bridge.checkResult(r, 'rac_embeddings_component_embed');

      return readEmbeddingsResult(bridge, m, resPtr);
    } finally {
      bridge.free(textPtr);
      m._free(optPtr);
    }
  },

  /**
   * Generate embeddings for multiple texts at once.
   */
  async embedBatch(texts: string[], options: EmbeddingsOptions = {}): Promise<EmbeddingsResult> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureEmbeddingsComponent();

    if (!Embeddings.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No embeddings model loaded. Call loadModel() first.');
    }

    logger.debug(`Embedding batch of ${texts.length} texts`);

    // Allocate array of string pointers
    const textPtrs: number[] = [];
    const textArrayPtr = m._malloc(texts.length * 4);

    for (let i = 0; i < texts.length; i++) {
      const ptr = bridge.allocString(texts[i]);
      textPtrs.push(ptr);
      m.setValue(textArrayPtr + i * 4, ptr, '*');
    }

    // Options
    const optSize = 12;
    const optPtr = m._malloc(optSize);
    m.setValue(optPtr, options.normalize !== undefined ? options.normalize : -1, 'i32');
    m.setValue(optPtr + 4, options.pooling !== undefined ? options.pooling : -1, 'i32');
    m.setValue(optPtr + 8, 0, 'i32');

    // Result
    const resSize = 32;
    const resPtr = m._malloc(resSize);

    try {
      const r = m.ccall(
        'rac_embeddings_component_embed_batch', 'number',
        ['number', 'number', 'number', 'number', 'number'],
        [handle, textArrayPtr, texts.length, optPtr, resPtr],
      ) as number;
      bridge.checkResult(r, 'rac_embeddings_component_embed_batch');

      return readEmbeddingsResult(bridge, m, resPtr);
    } finally {
      for (const ptr of textPtrs) bridge.free(ptr);
      m._free(textArrayPtr);
      m._free(optPtr);
    }
  },

  /**
   * Compute cosine similarity between two embedding vectors.
   * Pure TypeScript utility -- no WASM call needed.
   */
  cosineSimilarity(a: Float32Array, b: Float32Array): number {
    if (a.length !== b.length) throw new Error('Vectors must have the same dimension');

    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    const denominator = Math.sqrt(normA) * Math.sqrt(normB);
    return denominator === 0 ? 0 : dot / denominator;
  },

  /** Clean up the embeddings component. */
  cleanup(): void {
    if (_embeddingsComponentHandle !== 0) {
      try {
        WASMBridge.shared.module.ccall(
          'rac_embeddings_component_destroy', null, ['number'], [_embeddingsComponentHandle],
        );
      } catch { /* ignore */ }
      _embeddingsComponentHandle = 0;
    }
  },
};

// ---------------------------------------------------------------------------
// Helper: Read rac_embeddings_result_t from WASM memory
// ---------------------------------------------------------------------------

function readEmbeddingsResult(
  _bridge: WASMBridge,
  m: WASMBridge['module'],
  resPtr: number,
): EmbeddingsResult {
  // rac_embeddings_result_t: { embeddings*, num_embeddings, dimension, processing_time_ms, total_tokens }
  const embeddingsArrayPtr = m.getValue(resPtr, '*');
  const numEmbeddings = m.getValue(resPtr + 4, 'i32');
  const dimension = m.getValue(resPtr + 8, 'i32');
  const processingTimeMs = m.getValue(resPtr + 12, 'i32');
  const totalTokens = m.getValue(resPtr + 16, 'i32');

  const embeddings: EmbeddingVector[] = [];

  for (let i = 0; i < numEmbeddings; i++) {
    // Each rac_embedding_vector_t: { data*, dimension }
    const vecPtr = embeddingsArrayPtr + i * 8; // sizeof(rac_embedding_vector_t) = 8
    const dataPtr = m.getValue(vecPtr, '*');
    const vecDim = m.getValue(vecPtr + 4, 'i32');

    const data = new Float32Array(vecDim);
    if (dataPtr && vecDim > 0) {
      data.set(new Float32Array(m.HEAPU8.buffer, dataPtr, vecDim));
    }

    embeddings.push({ data, dimension: vecDim });
  }

  // Free C result
  m.ccall('rac_embeddings_result_free', null, ['number'], [resPtr]);

  EventBus.shared.emit('embeddings.generated', SDKEventType.Generation, {
    numEmbeddings,
    dimension,
    processingTimeMs,
  });

  return { embeddings, dimension, processingTimeMs, totalTokens };
}
