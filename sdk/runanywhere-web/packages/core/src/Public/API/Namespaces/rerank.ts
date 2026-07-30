/**
 * `RunAnywhere.rerank` — cross-encoder reranking of candidate documents.
 */

import { rerankOptionsDefaults } from '@runanywhere/proto-ts/convenience/rerank_convenience';
import { rerank as rerankImpl } from '../../Extensions/RunAnywhere+Rerank.js';
import type { RankedResult } from '../Results.js';
import { toRankedResults } from '../Mapping.js';
import { ensureReady } from '../Runtime/Prerequisites.js';

/** Cross-encoder reranking against the resident rerank model. */
export const rerank = {
  /**
   * Score documents against a query, best first.
   *
   * @returns Index pointers into `documents` with their relevance scores.
   * @throws SDKException when no rerank model is loaded through `models.load`.
   *
   * @example
   * const ranked = await RunAnywhere.rerank.rerank('best local LLM', docs, 3);
   * console.log(docs[ranked[0].index]);
   */
  async rerank(
    query: string,
    documents: readonly string[],
    topN?: number,
  ): Promise<RankedResult[]> {
    if (documents.length === 0) return [];
    await ensureReady();
    const result = await rerankImpl({
      query,
      candidates: documents.map((text, index) => ({ id: String(index), text })),
      options: { ...rerankOptionsDefaults(), topN: topN ?? rerankOptionsDefaults().topN },
    });
    return toRankedResults(result);
  },
};
