// The rerank namespace, wired over rac_rerank_component_rerank_proto. A rerank
// model must be resident (rerank has no ModelCategory, so it does not auto-load).
import { RerankRequest, RerankResult as ProtoRerankResult } from '@runanywhere/proto-ts/rerank';

import type { RaBackend } from '../backend.js';
import type { RankedResult } from '../types.js';

export interface RerankNamespace {
  /** Score `documents` against `query`, best-first. A rerank model must be resident. */
  rerank(query: string, documents: string[], topN?: number): Promise<RankedResult[]>;
}

export function createRerankNamespace(backend: RaBackend): RerankNamespace {
  return {
    async rerank(query, documents, topN) {
      if (!documents.length) return [];
      const req = RerankRequest.fromPartial({
        query,
        candidates: documents.map((text, i) => ({ id: String(i), text })),
        ...(topN !== undefined ? { options: { topN } } : {}),
      });
      const out = ProtoRerankResult.decode(await backend.rerank(RerankRequest.encode(req).finish()));
      return out.items.map((it) => ({ index: it.index, relevanceScore: it.relevanceScore }));
    },
  };
}
