/**
 * RunAnywhere+Embeddings.ts
 *
 * Public Embeddings facade — namespaced under `RunAnywhere.embeddings.*`
 * per the canonical cross-SDK spec. Mirrors Swift
 * `RunAnywhere+Embeddings.swift` (embed / embedBatch / unload / isLoaded /
 * currentModelID) so embedding generation is reachable from every SDK
 * against the same commons embedding lifecycle.
 *
 * Lifecycle (load / current / unload) delegates to the commons model
 * lifecycle service via `loadModel` / `unloadModel`. Embedding calls
 * dispatch through the lifecycle-aware ABI symbol
 * `rac_embeddings_embed_batch_lifecycle_proto` (Nitro
 * `embeddingsEmbedBatchLifecycleProto`) — the lifecycle owns the component,
 * so no handle crosses the bridge.
 *
 * RN deviation: Swift's `isLoaded` / `currentModelID` read the sync
 * component-lifecycle snapshot; RN's snapshot is async over the bridge, so
 * the sync getters are backed by a TS-side cached model id maintained on
 * successful load / unload.
 */
import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsOptions,
} from '@runanywhere/proto-ts/embeddings_options';
import {
  CurrentModelRequest,
  ModelCategory,
  ModelLoadRequest,
  ModelUnloadRequest,
} from '@runanywhere/proto-ts/model_types';
import {
  ErrorCategory,
  ErrorCode,
} from '@runanywhere/proto-ts/errors';
import {
  bytesToArrayBuffer,
  arrayBufferToBytes,
} from '../../../services/ProtoBytes';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { ensureServicesReadyOrIgnore } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';
import {
  currentModel,
  loadModel,
  unloadModel,
} from '../Models/RunAnywhere+ModelLifecycle';

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

/**
 * Stateful namespace exposing the canonical Embeddings surface.
 * Mirrors Swift `RunAnywhere.embeddings` (`RunAnywhere+Embeddings.swift`).
 */
export class EmbeddingsCapability {
  private loadedModelID: string | null = null;

  /** True when an embeddings model is loaded and ready. */
  get isLoaded(): boolean {
    return this.loadedModelID !== null;
  }

  /** Currently-loaded embeddings model id, or null. */
  get currentModelID(): string | null {
    return this.loadedModelID;
  }

  /**
   * Generate an embedding vector for a single text.
   *
   * Loads the requested embedding model if it is not already loaded, then
   * issues a single-text embed call. Mirrors Swift `embeddings.embed(_:modelID:options:)`.
   */
  async embed(
    text: string,
    modelID: string,
    options?: EmbeddingsOptions
  ): Promise<EmbeddingsResult> {
    const request = EmbeddingsRequest.fromPartial({
      texts: [text],
      options,
    });
    return this.embedBatch(request, modelID);
  }

  /**
   * Generate embeddings for a batch of texts.
   *
   * The request's `modelId` is honoured when set; otherwise the supplied
   * `modelID` argument is used. Mirrors Swift `embeddings.embedBatch(_:modelID:)`.
   */
  async embedBatch(
    request: EmbeddingsRequest,
    modelID: string
  ): Promise<EmbeddingsResult> {
    // Swift parity: guard isInitialized (RunAnywhere+Embeddings.swift:76-82).
    requireInitialized();
    const native = ensureNative();
    // Swift parity: embeddings loads via the lifecycle path whose guard is
    // `try?` — a transient Phase-2 failure must not block local embedding.
    await ensureServicesReadyOrIgnore();

    await this.ensureLoaded(modelID);

    if (request.modelId && request.modelId !== modelID) {
      throw SDKException.invalidInput(
        'EmbeddingsRequest.model_id does not match requested modelID'
      );
    }

    const lifecycleRequest = EmbeddingsRequest.fromPartial({
      ...request,
      modelId: modelID,
    });
    const requestBytes = bytesToArrayBuffer(
      EmbeddingsRequest.encode(lifecycleRequest).finish()
    );
    const resultBuffer =
      await native.embeddingsEmbedBatchLifecycleProto(requestBytes);
    const resultBytes = arrayBufferToBytes(resultBuffer);
    if (resultBytes.byteLength === 0) {
      throw SDKException.generationFailedWith(
        `Embeddings batch failed for model ${modelID}`
      );
    }
    return EmbeddingsResult.decode(resultBytes);
  }

  /**
   * Unload the currently-loaded embeddings model. No-op if none.
   *
   * Mirrors Swift `embeddings.unload()` (RunAnywhere+Embeddings.swift:101-133):
   * resolves the model id (cached → lifecycle snapshot fallback) and unloads
   * it through the shared model-lifecycle unload, throwing `processingFailed`
   * when the lifecycle reports failure.
   */
  async unload(): Promise<void> {
    // Swift parity: guard isInitialized (RunAnywhere+Embeddings.swift:102-108).
    requireInitialized();

    const cachedModelID = this.loadedModelID;
    this.loadedModelID = null;

    // Resolve the lifecycle-loaded embeddings model id: cached id first,
    // then the lifecycle snapshot — mirroring Swift's currentModelID →
    // loadedModelSnapshot(category: .embedding) fallback.
    let modelID = cachedModelID ?? '';
    if (modelID.length === 0) {
      const snapshot = await currentModel(
        CurrentModelRequest.fromPartial({
          category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
        })
      );
      modelID = snapshot?.found ? snapshot.modelId : '';
    }
    if (modelID.length === 0) return;

    const result = await unloadModel(
      ModelUnloadRequest.fromPartial({
        modelId: modelID,
        category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      })
    );
    if (!result.success) {
      throw SDKException.processingFailed(
        result.errorMessage || 'Embeddings lifecycle unload failed'
      );
    }
  }

  private async ensureLoaded(modelID: string): Promise<void> {
    if (this.loadedModelID === modelID) {
      return;
    }

    // Mirrors Swift: a lifecycle-loaded match short-circuits the load.
    const snapshot = await currentModel(
      CurrentModelRequest.fromPartial({
        category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      })
    );
    if (snapshot?.found && snapshot.modelId === modelID) {
      this.loadedModelID = modelID;
      return;
    }

    const result = await loadModel(
      ModelLoadRequest.fromPartial({
        modelId: modelID,
        category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
        forceReload: true,
        validateAvailability: true,
      })
    );
    if (!result.success) {
      throw SDKException.of(
        ErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
        result.errorMessage || 'Embeddings lifecycle load failed',
        { category: ErrorCategory.ERROR_CATEGORY_INTERNAL }
      );
    }
    this.loadedModelID = modelID;
  }
}

/** Singleton capability instance attached to the `RunAnywhere` facade. */
export const embeddings = new EmbeddingsCapability();
