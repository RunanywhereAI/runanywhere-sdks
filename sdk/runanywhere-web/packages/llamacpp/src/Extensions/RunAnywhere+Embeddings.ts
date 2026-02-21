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

import { RunAnywhere, SDKError, SDKErrorCode, SDKLogger, EventBus, SDKEventType } from '@runanywhere/web';
import { LlamaCppBridge } from '../Foundation/LlamaCppBridge';
import { Offsets } from '../Foundation/LlamaCppOffsets';
import type {
  EmbeddingVector,
  EmbeddingsResult,
  EmbeddingsOptions,
} from './EmbeddingsTypes';

export {
  EmbeddingsNormalize,
  EmbeddingsPooling,
  type EmbeddingVector,
  type EmbeddingsResult,
  type EmbeddingsOptions,
} from './EmbeddingsTypes';

const logger = new SDKLogger('Embeddings');

// ---------------------------------------------------------------------------
// Embeddings Extension
// ---------------------------------------------------------------------------

class EmbeddingsImpl {
  readonly extensionName = 'Embeddings';
  private _embeddingsComponentHandle = 0;

  private requireBridge(): LlamaCppBridge {
    if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
    return LlamaCppBridge.shared;
  }

  private ensureEmbeddingsComponent(): number {
    if (this._embeddingsComponentHandle !== 0) return this._embeddingsComponentHandle;

    const bridge = this.requireBridge();
    const m = bridge.module;
    const handlePtr = m._malloc(4);
    const result = bridge.callFunction<number>('rac_embeddings_component_create', 'number', ['number'], [handlePtr]);

    if (result !== 0) {
      m._free(handlePtr);
      bridge.checkResult(result, 'rac_embeddings_component_create');
    }

    this._embeddingsComponentHandle = m.getValue(handlePtr, 'i32');
    m._free(handlePtr);
    logger.debug('Embeddings component created');
    return this._embeddingsComponentHandle;
  }

  /**
   * Load an embedding model (GGUF format).
   */
  async loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void> {
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = this.ensureEmbeddingsComponent();

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
  }

  /** Unload the embeddings model. */
  async unloadModel(): Promise<void> {
    if (this._embeddingsComponentHandle === 0) return;
    const bridge = this.requireBridge();
    const result = bridge.module.ccall(
      'rac_embeddings_component_unload', 'number', ['number'], [this._embeddingsComponentHandle],
    ) as number;
    bridge.checkResult(result, 'rac_embeddings_component_unload');
    logger.info('Embeddings model unloaded');
  }

  /** Check if an embeddings model is loaded. */
  get isModelLoaded(): boolean {
    if (this._embeddingsComponentHandle === 0) return false;
    try {
      return (LlamaCppBridge.shared.module.ccall(
        'rac_embeddings_component_is_loaded', 'number', ['number'], [this._embeddingsComponentHandle],
      ) as number) === 1;
    } catch { return false; }
  }

  /**
   * Generate embedding for a single text.
   */
  async embed(text: string, options: EmbeddingsOptions = {}): Promise<EmbeddingsResult> {
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = this.ensureEmbeddingsComponent();

    if (!this.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No embeddings model loaded. Call loadModel() first.');
    }

    logger.debug(`Embedding text (${text.length} chars)`);

    const textPtr = bridge.allocString(text);

    // Build rac_embeddings_options_t
    const optSize = m._rac_wasm_sizeof_embeddings_options();
    const optPtr = m._malloc(optSize);
    const eOpt = Offsets.embeddingsOptions;
    m.setValue(optPtr + eOpt.normalize, options.normalize !== undefined ? options.normalize : -1, 'i32');
    m.setValue(optPtr + eOpt.pooling, options.pooling !== undefined ? options.pooling : -1, 'i32');
    m.setValue(optPtr + eOpt.nThreads, 0, 'i32'); // n_threads = auto

    // Result struct
    const resSize = m._rac_wasm_sizeof_embeddings_result();
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
  }

  /**
   * Generate embeddings for multiple texts at once.
   */
  async embedBatch(texts: string[], options: EmbeddingsOptions = {}): Promise<EmbeddingsResult> {
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = this.ensureEmbeddingsComponent();

    if (!this.isModelLoaded) {
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
    const optSize = m._rac_wasm_sizeof_embeddings_options();
    const optPtr = m._malloc(optSize);
    const eOpt2 = Offsets.embeddingsOptions;
    m.setValue(optPtr + eOpt2.normalize, options.normalize !== undefined ? options.normalize : -1, 'i32');
    m.setValue(optPtr + eOpt2.pooling, options.pooling !== undefined ? options.pooling : -1, 'i32');
    m.setValue(optPtr + eOpt2.nThreads, 0, 'i32');

    // Result
    const resSize = m._rac_wasm_sizeof_embeddings_result();
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
  }

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
  }

  /** Clean up the embeddings component. */
  cleanup(): void {
    if (this._embeddingsComponentHandle !== 0) {
      try {
        LlamaCppBridge.shared.module.ccall(
          'rac_embeddings_component_destroy', null, ['number'], [this._embeddingsComponentHandle],
        );
      } catch { /* ignore */ }
      this._embeddingsComponentHandle = 0;
    }
  }
}

export const Embeddings = new EmbeddingsImpl();

// ---------------------------------------------------------------------------
// Helper: Read rac_embeddings_result_t from WASM memory
// ---------------------------------------------------------------------------

function readEmbeddingsResult(
  bridge: LlamaCppBridge,
  m: LlamaCppBridge['module'],
  resPtr: number,
): EmbeddingsResult {
  // rac_embeddings_result_t (offsets from compiler via StructOffsets)
  const eRes = Offsets.embeddingsResult;
  const embeddingsArrayPtr = m.getValue(resPtr + eRes.embeddings, '*');
  const numEmbeddings = m.getValue(resPtr + eRes.numEmbeddings, 'i32');
  const dimension = m.getValue(resPtr + eRes.dimension, 'i32');
  const processingTimeMs = m.getValue(resPtr + eRes.processingTimeMs, 'i32'); // low 32 bits of int64
  const totalTokens = m.getValue(resPtr + eRes.totalTokens, 'i32');

  const embeddings: EmbeddingVector[] = [];
  const ev = Offsets.embeddingVector;

  for (let i = 0; i < numEmbeddings; i++) {
    // Each rac_embedding_vector_t
    const vecPtr = embeddingsArrayPtr + i * ev.structSize;
    const dataPtr = m.getValue(vecPtr + ev.data, '*');
    const vecDim = m.getValue(vecPtr + ev.dimension, 'i32');

    const data = new Float32Array(vecDim);
    if (dataPtr && vecDim > 0) {
      data.set(bridge.readFloat32Array(dataPtr, vecDim));
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
