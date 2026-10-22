import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { VectorStore } from '@runanywhere/proto-ts/rag';

const ragQuery = vi.fn();
const ragQueryStream = vi.fn();

vi.mock('../../../../../src/Public/API/Runtime/Prerequisites', () => ({
  ensureReady: vi.fn(async () => undefined),
}));
vi.mock('../../../../../src/Public/Extensions/RunAnywhere+RAG', () => ({
  ragClearDocuments: vi.fn(async () => undefined),
  ragCreatePipeline: vi.fn(async () => undefined),
  ragDestroyPipeline: vi.fn(async () => undefined),
  ragGetStatistics: vi.fn(async () => ({})),
  ragIngestDocument: vi.fn(async () => undefined),
  ragQuery: (...args: unknown[]) => ragQuery(...args),
  ragQueryStream: (...args: unknown[]) => ragQueryStream(...args),
  ragSearch: vi.fn(async () => []),
}));

import { rag, type RagSession } from '../../../../../src/Public/API/Namespaces/rag';

// Plain-JS callers are not held to the `'usearch'` literal type, so an unknown
// store must be rejected by name instead of being dropped before the provider's
// own guard can see it (#1094).
describe('rag session vectorStore validation', () => {
  let session: RagSession;

  beforeEach(async () => {
    ragQuery.mockReset();
    ragQueryStream.mockReset();
    ragQuery.mockResolvedValue({ answer: 'ok', retrievedChunks: [], contextUsed: '' });
    session = await rag.open({ id: 'all-minilm-l6-v2' } as never, { id: 'lfm2-350m' } as never);
  });

  afterEach(async () => {
    await session.close();
  });

  it('rejects an unknown vectorStore on query before anything is sent', async () => {
    await expect(
      session.query('q', { retrieval: { vectorStore: 'pgvector' as never } }),
    ).rejects.toThrow(/vectorStore.*pgvector/);
    expect(ragQuery).not.toHaveBeenCalled();
  });

  it('rejects an unknown vectorStore from the queryStream call itself', () => {
    expect(() => session.queryStream('q', { retrieval: { vectorStore: 'pgvector' as never } }))
      .toThrow(/vectorStore.*pgvector/);
    expect(ragQueryStream).not.toHaveBeenCalled();
  });

  it("forwards 'usearch' as VECTOR_STORE_USEARCH", async () => {
    await session.query('q', { retrieval: { vectorStore: 'usearch' } });
    expect(ragQuery.mock.calls[0]![1].retrieval.vectorStore).toBe(VectorStore.VECTOR_STORE_USEARCH);
  });
});
