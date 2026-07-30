/**
 * `RunAnywhere.embeddings` — vectors for a batch of texts.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  EmbeddingsRequest,
  EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';

import { decode, encode, nextRequestId, preflight } from './Bridge';
import { requireLoadedModelId } from './Models';
import { toEmbedOptions } from './Options';
import { toEmbeddings } from './Results';
import type { EmbedOptions, Embedding } from './Types';

/** Text embeddings from the loaded embedding model. */
export const embeddings = {
  /**
   * Embed `texts`, returning one vector per input in input order.
   *
   * @example
   * const [first] = await RunAnywhere.embeddings.embed(['on-device AI']);
   * console.log(first.vector.length);
   *
   * @throws SDKException when no embedding model is loaded or embedding fails.
   */
  async embed(texts: string[], options?: EmbedOptions): Promise<Embedding[]> {
    const native = await preflight();
    const modelId = await requireLoadedModelId(
      ModelCategory.MODEL_CATEGORY_EMBEDDING,
      'embeddings.embed'
    );
    const request = EmbeddingsRequest.fromPartial({
      requestId: nextRequestId('embed'),
      texts,
      modelId,
      options: toEmbedOptions(options),
    });
    const resultBytes = await native.embeddingsEmbedBatchLifecycleProto(
      encode(request, EmbeddingsRequest)
    );
    return toEmbeddings(
      decode(resultBytes, EmbeddingsResult, 'embeddingsEmbedBatch')
    );
  },
};
