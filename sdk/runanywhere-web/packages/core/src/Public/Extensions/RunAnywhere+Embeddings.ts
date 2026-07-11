/**
 * RunAnywhere+Embeddings.ts
 *
 * Public Embeddings facade — namespaced under `RunAnywhere.embeddings.*`
 * per the canonical cross-SDK spec. Mirrors the Swift
 * `RunAnywhere+Embeddings.swift` API so embedding generation is reachable
 * from every SDK against the same commons embedding lifecycle.
 *
 * Lifecycle (load / current / unload) delegates to the commons model lifecycle
 * service via `RunAnywhere.loadModel` / `RunAnywhere.unloadModel`. Embedding
 * calls dispatch through `EmbeddingsProtoAdapter.embedBatch(...)`.
 */

import { ModelCategory, type ModelLoadResult, type ModelUnloadResult } from '@runanywhere/proto-ts/model_types';
import { SDKComponent } from '@runanywhere/proto-ts/sdk_events';
import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import type {
  EmbeddingVector,
  EmbeddingsOptions,
  EmbeddingsRequest,
  EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import { EmbeddingsProtoAdapter } from '../../Adapters/EmbeddingsProtoAdapter.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

const logger = new SDKLogger('Embeddings');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireAdapter(): EmbeddingsProtoAdapter {
  const adapter = EmbeddingsProtoAdapter.tryDefault();
  if (!adapter) {
    throw SDKException.backendNotAvailable(
      'Embeddings',
      'No backend is registered for the Embeddings capability. Register a backend WASM module (e.g. OnnxRuntime.register()) during app init.',
    );
  }
  if (!adapter.supportsProtoEmbeddings()) {
    throw SDKException.backendNotAvailable(
      'Embeddings',
      'The active Web WASM build does not export _rac_embeddings_embed_batch_proto. Rebuild with RAC_BACKEND_EMBEDDINGS=ON.',
    );
  }
  return adapter;
}

function requireInitialized(): void {
  // Mirrors Swift's `guard RunAnywhere.isInitialized` check at the top of
  // every verb. The Web SDK exposes this via the WebModelLifecycle adapter
  // presence: if no adapter exists the SDK was never initialized with a
  // backend that can serve the WASM.
  if (!WebModelLifecycle.supportsNativeLifecycle()) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      'SDK not initialized or no backend registered',
      'Embeddings',
    );
  }
}

// ---------------------------------------------------------------------------
// ensureLoaded — mirrors Swift private func ensureLoaded(modelID:)
// ---------------------------------------------------------------------------

async function ensureLoaded(modelID: string): Promise<void> {
  const snapshot = WebModelLifecycle.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_EMBEDDINGS);
  if (snapshot?.state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY
      && snapshot.modelId === modelID) {
    return;
  }

  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    includeModelMetadata: false,
  });
  if (current?.found && current.modelId === modelID) {
    return;
  }

  const result: ModelLoadResult | null = await WebModelLifecycle.loadModelAsync({
    modelId: modelID,
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    forceReload: true,
    validateAvailability: true,
  });

  if (!result?.success) {
    const msg = result?.errorMessage || 'Embeddings lifecycle load failed';
    logger.warning(`ensureLoaded(${modelID}) failed: ${msg}`);
    throw SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED, msg, 'Embeddings.ensureLoaded');
  }
}

// ---------------------------------------------------------------------------
// Public verb implementations
// ---------------------------------------------------------------------------

async function embed(
  text: string,
  modelID: string,
  options?: EmbeddingsOptions,
): Promise<EmbeddingsResult> {
  const request: EmbeddingsRequest = {
    texts: [text],
    options,
    requestId: '',
    modelId: modelID,
    metadata: {},
  };
  return embedBatch(request, modelID);
}

async function embedBatch(
  request: EmbeddingsRequest,
  modelID: string,
): Promise<EmbeddingsResult> {
  requireInitialized();

  if (request.modelId !== undefined && request.modelId !== '' && request.modelId !== modelID) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_INVALID_PARAMETER,
      'EmbeddingsRequest.modelId does not match requested modelID',
      'Embeddings.embedBatch',
    );
  }

  await ensureLoaded(modelID);

  const lifecycleRequest: EmbeddingsRequest = { ...request, modelId: modelID };

  const adapter = requireAdapter();

  // EmbeddingsProtoAdapter.embedBatch requires a numeric handle. The Web
  // adapter tracks state through the WASM modality slot (adapterState); a
  // handle of 0 is the sentinel that makes commons use the lifecycle-resolved
  // currently-loaded model, matching Swift's
  // `CppBridge.EmbeddingsProto.embedBatchLifecycle` which also operates on
  // the loaded model rather than an explicit handle.
  const result = await adapter.embedBatch(0, lifecycleRequest);

  if (!result) {
    throw SDKException.backendNotAvailable(
      'Embeddings.embedBatch',
      'embedBatch returned no result from the native WASM.',
    );
  }

  if (result.errorCode !== 0) {
    const msg = result.errorMessage || 'Embeddings embed failed';
    throw SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_GENERATION_FAILED, msg, 'Embeddings.embedBatch');
  }

  return result;
}

async function unload(): Promise<void> {
  requireInitialized();

  let modelID: string | undefined;

  const snapshot = WebModelLifecycle.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_EMBEDDINGS);
  if (snapshot?.modelId) {
    modelID = snapshot.modelId;
  } else {
    const current = WebModelLifecycle.currentModel({
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      includeModelMetadata: false,
    });
    modelID = current?.modelId;
  }

  if (!modelID) return;

  const result: ModelUnloadResult | null = await WebModelLifecycle.unloadModelAsync({
    modelId: modelID,
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    unloadAll: false,
  });

  if (!result?.success) {
    const msg = result?.errorMessage || 'Embeddings lifecycle unload failed';
    throw SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_GENERATION_FAILED, msg, 'Embeddings.unload');
  }
}

// ---------------------------------------------------------------------------
// isLoaded / currentModelID — mirrors Swift Embeddings struct properties
// ---------------------------------------------------------------------------

function isLoaded(): boolean {
  const snapshot = WebModelLifecycle.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_EMBEDDINGS);
  return snapshot?.state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY
    && Boolean(snapshot?.modelId);
}

function currentModelID(): string | null {
  const snapshot = WebModelLifecycle.componentLifecycleSnapshot(SDKComponent.SDK_COMPONENT_EMBEDDINGS);
  if (snapshot?.state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY
      && snapshot.modelId) {
    return snapshot.modelId;
  }
  return null;
}

// ---------------------------------------------------------------------------
// EmbeddingVector helpers — Swift parity: EmbeddingsProto+Helpers.swift
// ---------------------------------------------------------------------------

function l2Norm(values: number[]): number {
  let sumSquares = 0;
  for (const value of values) sumSquares += value * value;
  return Math.sqrt(sumSquares);
}

/**
 * Cosine similarity between two embedding vectors. Uses the precomputed
 * `norm` field when present, recomputing the L2 norm otherwise. Returns 0
 * for mismatched/empty vectors or zero norms.
 * Swift parity: `RAEmbeddingVector.cosineSimilarity(with:)`
 * (EmbeddingsProto+Helpers.swift:18).
 */
export function embeddingCosineSimilarity(a: EmbeddingVector, b: EmbeddingVector): number {
  if (a.values.length !== b.values.length || a.values.length === 0) return 0;
  let dot = 0;
  for (let i = 0; i < a.values.length; i += 1) dot += a.values[i]! * b.values[i]!;
  const aNorm = a.norm !== undefined ? a.norm : l2Norm(a.values);
  const bNorm = b.norm !== undefined ? b.norm : l2Norm(b.values);
  if (aNorm <= 0 || bNorm <= 0) return 0;
  return dot / (aNorm * bNorm);
}

/**
 * L2 norm of the vector's values.
 * Swift parity: `RAEmbeddingVector.computeNorm()` (EmbeddingsProto+Helpers.swift:28).
 */
export function embeddingComputeNorm(vector: EmbeddingVector): number {
  return l2Norm(vector.values);
}

/**
 * Processing time in seconds (from `processingTimeMs`).
 * Swift parity: `RAEmbeddingsResult.processingTime` (EmbeddingsProto+Helpers.swift:40).
 */
export function embeddingsResultProcessingTime(result: EmbeddingsResult): number {
  return result.processingTimeMs / 1000;
}

// ---------------------------------------------------------------------------
// Public namespace
// ---------------------------------------------------------------------------

/**
 * Public `RunAnywhere.embeddings.*` namespace. Mirrors the Swift
 * `RunAnywhere.Embeddings` struct: every modality is reachable through
 * `RunAnywhere.<modality>.<verb>` per AGENTS.md cross-SDK alignment.
 */
export const Embeddings = {
  /** True when commons lifecycle has a ready embeddings model. */
  get isLoaded(): boolean {
    return isLoaded();
  },

  /** Currently-loaded embeddings model id, or null. */
  get currentModelID(): string | null {
    return currentModelID();
  },

  /**
   * Generate an embedding vector for a single text.
   *
   * Loads the requested embedding model into the commons lifecycle if it is
   * not already loaded, then issues a single-text embed call.
   */
  embed,

  /**
   * Generate embeddings for a batch of texts.
   *
   * The request's `modelId` is honoured when set; otherwise the supplied
   * `modelID` argument is used.
   */
  embedBatch,

  /** Unload the currently-loaded embeddings model. No-op if none loaded. */
  unload,
};

export type { EmbeddingVector, EmbeddingsOptions, EmbeddingsRequest, EmbeddingsResult };
