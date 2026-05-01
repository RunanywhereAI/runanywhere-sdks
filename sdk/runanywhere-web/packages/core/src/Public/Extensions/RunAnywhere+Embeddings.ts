/**
 * RunAnywhere+Embeddings.ts
 *
 * Embeddings namespace — mirrors Swift's `RunAnywhere+Embeddings.swift`.
 * Exposes the §10 canonical flat `embed(...)` verb on `RunAnywhere.*` by
 * delegating to the backend-supplied embeddings service registered under
 * `ServiceKey.Embeddings` (e.g. by @runanywhere/web-llamacpp).
 */

import type {
  EmbeddingsOptions,
  EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
export type { EmbeddingsOptions, EmbeddingsResult };

import { ExtensionPoint, ServiceKey } from '../../Infrastructure/ExtensionPoint';
import { SDKException } from '../../Foundation/SDKException';

/** Backend-supplied embeddings provider interface. */
export interface EmbeddingsProvider {
  embed(text: string, options?: Partial<EmbeddingsOptions>): Promise<EmbeddingsResult>;
}

function getEmbeddingsProvider(): EmbeddingsProvider | null {
  const svc = ExtensionPoint.getService<EmbeddingsProvider>(ServiceKey.Embeddings);
  return svc ?? null;
}

/**
 * Generate an embedding vector for a single text (§10 `embed`).
 *
 * Delegates to the embeddings provider registered by a backend package.
 * Install and register `@runanywhere/web-llamacpp` (which also owns a
 * first-class `Embeddings` service with richer lifecycle methods) before
 * calling this.
 */
export async function embed(
  text: string,
  options?: Partial<EmbeddingsOptions>,
): Promise<EmbeddingsResult> {
  const provider = getEmbeddingsProvider();
  if (provider != null && typeof provider.embed === 'function') {
    return provider.embed(text, options);
  }
  throw SDKException.backendNotAvailable(
    'embed',
    'No embeddings backend registered. Install @runanywhere/web-llamacpp and call LlamaCPP.register().',
  );
}

/** Embeddings namespace object — mirrors `Diffusion` / `RAG`. */
export const Embeddings = {
  embed,
};
