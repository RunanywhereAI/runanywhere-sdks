/**
 * RunAnywhere+Embeddings.ts
 *
 * Embeddings extension backed by the commons proto-byte ABI.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import {
  EmbeddingsNormalizeMode,
  EmbeddingsPoolingStrategy,
  type EmbeddingsOptions,
  EmbeddingsRequest,
  type EmbeddingsResult,
  EmbeddingsResult as EmbeddingsResultMessage,
} from '@runanywhere/proto-ts/embeddings_options';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const embeddingsHandles = new Map<string, number>();

function defaultEmbeddingsOptions(options?: EmbeddingsOptions): EmbeddingsOptions {
  return {
    normalize: options?.normalize ?? true,
    truncate: options?.truncate,
    batchSize: options?.batchSize,
    normalizeMode:
      options?.normalizeMode ?? EmbeddingsNormalizeMode.EMBEDDINGS_NORMALIZE_MODE_L2,
    pooling:
      options?.pooling ?? EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_MEAN,
    nThreads: options?.nThreads ?? 0,
  };
}

async function getEmbeddingsHandle(modelId: string): Promise<number> {
  const existing = embeddingsHandles.get(modelId);
  if (existing && existing !== 0) return existing;

  const native = requireNativeModule();
  const handle = await native.embeddingsCreateProto(modelId, undefined);
  if (!handle || handle === 0) {
    throw new Error(`Failed to create embeddings service for model: ${modelId}`);
  }
  embeddingsHandles.set(modelId, handle);
  return handle;
}

/**
 * Generate an embedding vector for a single text.
 *
 * Matches Swift: `RunAnywhere.embed(text:modelId:options:)`.
 */
export async function embed(
  text: string,
  modelId: string,
  options?: EmbeddingsOptions
): Promise<EmbeddingsResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  const handle = await getEmbeddingsHandle(modelId);
  const request = EmbeddingsRequest.create({
    texts: [text],
    options: defaultEmbeddingsOptions(options),
  });
  const resultBytes = await native.embeddingsEmbedBatchProto(
    handle,
    bytesToArrayBuffer(EmbeddingsRequest.encode(request).finish())
  );
  const bytes = arrayBufferToBytes(resultBytes);
  if (bytes.byteLength === 0) {
    throw new Error('Embeddings proto request returned an empty result');
  }
  return EmbeddingsResultMessage.decode(bytes);
}

/** Destroy a cached embeddings service handle. */
export async function unloadEmbeddingsModel(modelId: string): Promise<void> {
  const handle = embeddingsHandles.get(modelId);
  if (!handle || !isNativeModuleAvailable()) return;
  embeddingsHandles.delete(modelId);
  await requireNativeModule().embeddingsDestroyProto(handle);
}
