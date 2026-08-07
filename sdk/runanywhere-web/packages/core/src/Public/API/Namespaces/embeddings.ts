/**
 * `RunAnywhere.embeddings` — text embeddings in input order.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { SDKException } from '../../../Foundation/SDKException.js';
import { Embeddings } from '../../Extensions/RunAnywhere+Embeddings.js';
import { WebModelLifecycle } from '../../Extensions/RunAnywhere+ModelLifecycle.js';
import type { EmbedOptions } from '../Options.js';
import type { Embedding } from '../Results.js';
import { toEmbeddings, toProtoEmbedOptions } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

function resolveModelId(options?: EmbedOptions): string {
  if (options?.model) return options.model;
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    includeModelMetadata: false,
  });
  if (current?.found && current.modelId) return current.modelId;
  throw SDKException.notInitialized(
    'No embedding model is loaded. Pass options.model or call RunAnywhere.models.load(id) first.',
  );
}

/** Text embeddings against the resident embedding model. */
export const embeddings = {
  /**
   * Embed a batch of texts, returning one vector per input in input order.
   *
   * @throws SDKException when no embedding model is available.
   *
   * @example
   * const [first] = await RunAnywhere.embeddings.embed(['on-device inference']);
   * console.log(first.vector.length);
   */
  async embed(texts: readonly string[], options?: EmbedOptions): Promise<Embedding[]> {
    if (texts.length === 0) return [];
    await ensureReady();
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING, options?.model);
    const modelId = resolveModelId(options);
    const result = await Embeddings.embedBatch(
      {
        texts: [...texts],
        options: toProtoEmbedOptions(options),
        requestId: '',
        modelId,
      },
      modelId,
    );
    return toEmbeddings(result);
  },
};
