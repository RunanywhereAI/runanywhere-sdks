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

import {
  type InferenceFramework,
  ModelCategory,
  type ModelLoadResult,
  type ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
import type {
  EmbeddingVector,
  EmbeddingsOptions,
  EmbeddingsRequest,
  EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import { EmbeddingsProtoAdapter } from '../../Adapters/EmbeddingsProtoAdapter.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';
import { ModelRegistry } from './RunAnywhere+ModelRegistry.js';

const logger = new SDKLogger('Embeddings');
let activeEmbedding: { modelID: string; framework?: InferenceFramework } | null = null;

interface EmbeddingsMathModule extends EmscriptenRunanywhereModule {
  _rac_embeddings_norm?(vectorPtr: number, dimension: number, outNormPtr: number): number;
  _rac_embeddings_similarity?(
    lhsPtr: number,
    lhsDimension: number,
    rhsPtr: number,
    rhsDimension: number,
    outSimilarityPtr: number,
  ): number;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireAdapter(framework?: InferenceFramework): EmbeddingsProtoAdapter {
  const adapter = EmbeddingsProtoAdapter.tryDefaultForFramework(framework);
  if (!adapter) {
    throw SDKException.backendNotAvailable(
      'Embeddings',
      'No backend is registered for the Embeddings capability. Register LlamaCPP or ONNX during app init.',
    );
  }
  if (!adapter.supportsLifecycleProtoEmbeddings()) {
    throw SDKException.backendNotAvailable(
      'Embeddings',
      'The active Web WASM build does not export _rac_embeddings_embed_batch_lifecycle_proto. Rebuild with RAC_BACKEND_EMBEDDINGS=ON.',
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

async function ensureLoaded(modelID: string): Promise<InferenceFramework | undefined> {
  let requestedFramework: InferenceFramework | undefined;
  try {
    requestedFramework = ModelRegistry.getModel(modelID)?.framework as
      | InferenceFramework
      | undefined;
  } catch {
    requestedFramework = undefined;
  }
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    framework: requestedFramework,
    includeModelMetadata: false,
  });
  if (current?.found && current.modelId === modelID) {
    activeEmbedding = { modelID, framework: current.framework };
    return current.framework;
  }

  const result: ModelLoadResult | null = await WebModelLifecycle.loadModelAsync({
    modelId: modelID,
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    forceReload: true,
    validateAvailability: true,
    backendPreferences: [],
  });

  if (!result || result.error) {
    const msg = result?.error?.message || 'Embeddings lifecycle load failed';
    logger.warning(`ensureLoaded(${modelID}) failed: ${msg}`);
    throw result?.error
      ? new SDKException(result.error)
      : SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED, msg, 'Embeddings.ensureLoaded');
  }
  const framework = result.framework ?? requestedFramework;
  activeEmbedding = { modelID, framework };
  return framework;
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

  const framework = await ensureLoaded(modelID);

  const lifecycleRequest: EmbeddingsRequest = { ...request, modelId: modelID };

  const adapter = requireAdapter(framework);

  // Use the handle-less lifecycle ABI, matching Swift's
  // `CppBridge.EmbeddingsProto.embedBatchLifecycle`. The handle-based
  // `_rac_embeddings_embed_batch_proto` rejects a null handle; zero is not a
  // lifecycle sentinel.
  const result = await adapter.embedBatchLifecycle(lifecycleRequest);

  if (!result) {
    throw SDKException.backendNotAvailable(
      'Embeddings.embedBatch',
      'embedBatch returned no result from the native WASM.',
    );
  }

  return result;
}

async function unload(): Promise<void> {
  requireInitialized();

  const result: ModelUnloadResult | null = await WebModelLifecycle.unloadModelAsync({
    modelId: '',
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    // Category-only requests fan out across every registered WASM module.
    // `unloadAll` must remain false: the native lifecycle gives that flag
    // precedence over `category`, which would also tear down active chat,
    // speech, and vision models in each module.
    unloadAll: false,
  });

  if (!result || result.error) {
    throw result?.error
      ? new SDKException(result.error)
      : SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_GENERATION_FAILED, 'Embeddings lifecycle unload failed', 'Embeddings.unload');
  }
  activeEmbedding = null;
}

// ---------------------------------------------------------------------------
// isLoaded / currentModelID — mirrors Swift Embeddings struct properties
// ---------------------------------------------------------------------------

function isLoaded(): boolean {
  return currentModelID() !== null;
}

function currentModelID(): string | null {
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    framework: activeEmbedding?.framework,
    includeModelMetadata: false,
  });
  if (!current?.found || !current.modelId) {
    activeEmbedding = null;
    return null;
  }
  activeEmbedding = { modelID: current.modelId, framework: current.framework };
  return current.modelId;
}

// ---------------------------------------------------------------------------
// EmbeddingVector helpers — Swift parity: EmbeddingsProto+Helpers.swift
// Norm / cosine similarity are owned by commons
// (`rac_embeddings_norm` / `rac_embeddings_similarity`) via WASM.
// ---------------------------------------------------------------------------

function requireEmbeddingsMathModule(): EmbeddingsMathModule {
  const module = (getModuleForCapability('embedding') ??
    getModuleForCapability('commons') ??
    getModuleForCapability('llm')) as EmbeddingsMathModule | null;
  if (!module) {
    throw SDKException.backendNotAvailable(
      'Embeddings',
      'No WASM module exporting rac_embeddings_* is registered. Call RunAnywhere.initialize() first.',
    );
  }
  return module;
}

function floatValuesToOwnedBytes(values: number[]): Uint8Array {
  const floats = new Float32Array(values.length);
  for (let i = 0; i < values.length; i += 1) floats[i] = values[i]!;
  const owned = new Uint8Array(floats.byteLength);
  owned.set(new Uint8Array(floats.buffer, floats.byteOffset, floats.byteLength));
  return owned;
}

function allocCopy(module: EmbeddingsMathModule, bytes: Uint8Array): number {
  const ptr = module._malloc(bytes.byteLength || 1);
  if (!ptr) throw SDKException.processingFailed('Failed to allocate WASM embedding buffer.');
  if (bytes.byteLength > 0) module.HEAPU8.set(bytes, ptr);
  return ptr;
}

function readFloatOut(
  module: EmbeddingsMathModule,
  fnName: string,
  invoke: (outPtr: number) => number,
): number {
  const outPtr = module._malloc(4);
  try {
    if (!outPtr) throw SDKException.processingFailed(`Failed to allocate ${fnName} output.`);
    const rc = invoke(outPtr);
    if (rc !== 0) {
      throw SDKException.processingFailed(`${fnName} failed (${rc}).`);
    }
    return module.getValue(outPtr, 'float');
  } finally {
    if (outPtr) module._free(outPtr);
  }
}

/**
 * Cosine similarity between two embedding vectors via
 * `rac_embeddings_similarity`. Returns 0 for mismatched/empty vectors or
 * zero norms (commons contract).
 * Swift parity: `RAEmbeddingVector.cosineSimilarity(with:)`
 */
export function embeddingCosineSimilarity(a: EmbeddingVector, b: EmbeddingVector): number {
  const module = requireEmbeddingsMathModule();
  if (typeof module._rac_embeddings_similarity !== 'function') {
    throw SDKException.backendNotAvailable(
      'Embeddings',
      'WASM build missing _rac_embeddings_similarity.',
    );
  }
  const lhsBytes = floatValuesToOwnedBytes(a.values);
  const rhsBytes = floatValuesToOwnedBytes(b.values);
  const lhsPtr = allocCopy(module, lhsBytes);
  const rhsPtr = allocCopy(module, rhsBytes);
  try {
    return readFloatOut(module, 'rac_embeddings_similarity', (outPtr) => (
      module._rac_embeddings_similarity!(
        lhsPtr,
        a.values.length,
        rhsPtr,
        b.values.length,
        outPtr,
      )
    ));
  } finally {
    module._free(lhsPtr);
    module._free(rhsPtr);
  }
}

/**
 * L2 norm of the vector's values via `rac_embeddings_norm`.
 * Swift parity: `RAEmbeddingVector.computeNorm()`
 */
export function embeddingComputeNorm(vector: EmbeddingVector): number {
  const module = requireEmbeddingsMathModule();
  if (typeof module._rac_embeddings_norm !== 'function') {
    throw SDKException.backendNotAvailable(
      'Embeddings',
      'WASM build missing _rac_embeddings_norm.',
    );
  }
  const bytes = floatValuesToOwnedBytes(vector.values);
  const vectorPtr = allocCopy(module, bytes);
  try {
    return readFloatOut(module, 'rac_embeddings_norm', (outPtr) => (
      module._rac_embeddings_norm!(vectorPtr, vector.values.length, outPtr)
    ));
  } finally {
    module._free(vectorPtr);
  }
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
