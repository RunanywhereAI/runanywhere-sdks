// The embeddings namespace: embed text over the proto-byte backend. Auto-loads
// the embedding model named in options.model, mirroring Swift.
import { EmbeddingsRequest, EmbeddingsResult } from '@runanywhere/proto-ts/embeddings_options';

import type { RaBackend } from '../backend.js';
import type { Embedding } from '../types.js';
import type { ModelResolver } from './llm.js';

/** Per-request embedding controls. Mirrors Swift `EmbedOptions`. */
export interface EmbedOptions {
  /** Embedding model id to run; loaded (and downloaded) first if not resident. */
  model?: string;
  normalize?: boolean;
  pooling?: 'mean' | 'cls' | 'last';
}

export interface EmbeddingsNamespace {
  /** Embed a batch of texts; one vector per input, in order. */
  embed(texts: string[], options?: EmbedOptions): Promise<Embedding[]>;
}

export function createEmbeddingsNamespace(backend: RaBackend, resolve: ModelResolver): EmbeddingsNamespace {
  return {
    async embed(texts, options) {
      if (!texts.length) return [];
      if (options?.model) await resolve(options.model);
      const req = EmbeddingsRequest.fromPartial({
        texts,
        ...(options?.model ? { modelId: options.model } : {}),
      });
      const out = EmbeddingsResult.decode(await backend.embed(EmbeddingsRequest.encode(req).finish()));
      return out.vectors.map((v, i) => ({ index: v.inputIndex ?? i, vector: v.values }));
    },
  };
}
