/**
 * RunAnywhere+Embeddings.ts
 *
 * Public Embeddings facade — namespaced under `RunAnywhere.embeddings.*`
 * per the canonical cross-SDK spec. Mirrors Swift
 * `RunAnywhere+Embeddings.swift` (embed / embedBatch / unload / isLoaded /
 * currentModelID) so embedding generation is reachable from every SDK
 * against the same commons embedding lifecycle.
 *
 * Bridge shape: the RN native layer exposes the handle-based commons ABI
 * (`embeddingsCreateProto` / `embeddingsEmbedBatchProto` /
 * `embeddingsDestroyProto`); this facade owns the handle and the
 * currently-loaded model id so the public surface stays lifecycle-shaped
 * like Swift's.
 */
import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsOptions,
} from '@runanywhere/proto-ts/embeddings_options';
import {
  bytesToArrayBuffer,
  arrayBufferToBytes,
} from '../../../services/ProtoBytes';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { ensureServicesReadyOrIgnore } from '../../../Foundation/Initialization/ServicesReadyGuard';

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

  /** Unload the currently-loaded embeddings model. No-op if none. */
  async unload(): Promise<void> {
    if (this.handle === 0) {
      this.loadedModelID = null;
      return;
    }
    const native = ensureNative();
    const handle = this.handle;
    this.handle = 0;
    this.loadedModelID = null;
    await native.embeddingsDestroyProto(handle);
  }

  private async ensureLoaded(modelID: string): Promise<void> {
    if (this.handle !== 0 && this.loadedModelID === modelID) {
      return;
    }
    // Switching models: release the previous handle first.
    if (this.handle !== 0) {
      await this.unload();
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
