/**
 * RunAnywhere+Embeddings.ts
 *
 * Public Embeddings facade — namespaced under `RunAnywhere.embeddings.*`
 * per the canonical cross-SDK spec. Mirrors Swift
 * `RunAnywhere+Embeddings.swift` (embed / embedBatch / unload / isLoaded /
 * currentModelID) so embedding generation is reachable from every SDK
 * against the same commons embedding lifecycle.
 *
 * Bridge shape: the RN native layer exposes only the handle-based commons
 * ABI (`embeddingsCreateProto` / `embeddingsEmbedBatchProto` /
 * `embeddingsDestroyProto`) — the lifecycle-aware
 * `rac_embeddings_embed_batch_lifecycle_proto` symbol Swift dispatches
 * through (CppBridge.EmbeddingsProto.embedBatchLifecycle) is not plumbed
 * through Nitro yet. TODO(layer-down): expose the lifecycle embed ABI on
 * the Nitro bridge and migrate `embedBatch` off the per-facade handle so
 * RN matches Swift's handle-less lifecycle path exactly.
 *
 * Until then this facade owns the embed handle, but `unload()` mirrors
 * Swift by ALSO unloading the lifecycle-loaded embeddings model through
 * the shared model-lifecycle unload (`RunAnywhere.unloadModel`).
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
  ModelUnloadRequest,
} from '@runanywhere/proto-ts/model_types';
import {
  bytesToArrayBuffer,
  arrayBufferToBytes,
} from '../../../services/ProtoBytes';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { ensureServicesReadyOrIgnore } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';
import { currentModel, unloadModel } from '../Models/RunAnywhere+ModelLifecycle';

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
  private handle = 0;
  private loadedModelID: string | null = null;

  /** True when an embeddings model is loaded and ready. */
  get isLoaded(): boolean {
    return this.handle !== 0 && this.loadedModelID !== null;
  }

  /** Currently-loaded embeddings model id, or null. */
  get currentModelID(): string | null {
    return this.isLoaded ? this.loadedModelID : null;
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

    if (request.modelId && request.modelId !== modelID) {
      throw SDKException.invalidInput(
        'EmbeddingsRequest.model_id does not match requested modelID'
      );
    }

    await this.ensureLoaded(modelID);

    const lifecycleRequest = EmbeddingsRequest.fromPartial({
      ...request,
      modelId: modelID,
    });
    const requestBytes = bytesToArrayBuffer(
      EmbeddingsRequest.encode(lifecycleRequest).finish()
    );
    const resultBuffer = await native.embeddingsEmbedBatchProto(
      this.handle,
      requestBytes
    );
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
   * when the lifecycle reports failure. Additionally releases the RN-local
   * embed handle (bridge-shape difference — see module header).
   */
  async unload(): Promise<void> {
    // Swift parity: guard isInitialized (RunAnywhere+Embeddings.swift:102-108).
    requireInitialized();

    // Release the RN-local embed handle first so a failed lifecycle unload
    // never leaves a dangling native handle behind.
    const cachedModelID = this.loadedModelID;
    if (this.handle !== 0) {
      const native = ensureNative();
      const handle = this.handle;
      this.handle = 0;
      this.loadedModelID = null;
      await native.embeddingsDestroyProto(handle);
    } else {
      this.loadedModelID = null;
    }

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
    if (this.handle !== 0 && this.loadedModelID === modelID) {
      return;
    }
    // Switching models: release the previous handle first (handle only —
    // the new model is about to take the lifecycle slot anyway).
    if (this.handle !== 0) {
      const native = ensureNative();
      const handle = this.handle;
      this.handle = 0;
      this.loadedModelID = null;
      await native.embeddingsDestroyProto(handle);
    }
    const native = ensureNative();
    const handle = await native.embeddingsCreateProto(modelID, undefined);
    if (!handle) {
      throw SDKException.modelLoadFailed(modelID);
    }
    this.handle = handle;
    this.loadedModelID = modelID;
  }
}

/** Singleton capability instance attached to the `RunAnywhere` facade. */
export const embeddings = new EmbeddingsCapability();
