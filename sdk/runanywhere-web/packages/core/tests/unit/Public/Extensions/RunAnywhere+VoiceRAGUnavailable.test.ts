import { afterEach, describe, expect, it, vi } from 'vitest';
import { ProtoErrorCode, SDKException } from '../../../../src/Foundation/SDKException';
import {
  ModalityProtoAdapter,
  RAGProtoAdapter,
  type ModalityProtoModule,
} from '../../../../src/Adapters/ModalityProtoAdapter';
import { clearRunanywhereModule } from '../../../../src/runtime/EmscriptenModule';
// `rag_service` was absorbed into `rag.ts` -- `RAGResult` lives there now
// alongside `RAGQueryOptions`/`RAGSearchRequest`.
import type { RAGQueryOptions, RAGResult, RAGSearchRequest } from '@runanywhere/proto-ts/rag';
import {
  RAG,
  createRAGNativeProvider,
  createDefaultRAGConfiguration,
  ragGetStatistics,
  ragQuery,
  ragSearch,
  setRAGProvider,
  setRAGSessionHandle,
} from '../../../../src/Public/Extensions/RunAnywhere+RAG';
import {
  VoiceAgent,
  processVoiceTurn,
  setVoiceAgentHandle,
  setVoiceAgentProvider,
  streamVoiceAgent,
} from '../../../../src/Public/Extensions/RunAnywhere+VoiceAgent';

describe('VoiceAgent and RAG provider-required facades', () => {
  afterEach(() => {
    setVoiceAgentProvider(null);
    setRAGProvider(null);
    clearRunanywhereModule();
    vi.restoreAllMocks();
  });

  it('throws notInitialized from processVoiceTurn when no provider is registered (Swift parity)', async () => {
    expect(VoiceAgent.availability().available).toBe(false);

    await expect(processVoiceTurn(new Float32Array([0, 0, 0, 0]))).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      message: expect.stringContaining('Voice agent not ready'),
    });
  });

  it('finishes the voice-agent stream empty when no stream provider is registered (Swift parity)', async () => {
    const iterator = streamVoiceAgent()[Symbol.asyncIterator]();
    const first = await iterator.next();

    expect(first.done).toBe(true);
  });

  it('throws from RAG query/statistics when no provider is registered (Swift parity)', async () => {
    expect(RAG.availability().available).toBe(false);

    await expect(ragQuery('What is indexed?')).rejects.toBeInstanceOf(SDKException);
    await expect(ragGetStatistics()).rejects.toBeInstanceOf(SDKException);
  });

  it('keeps RAG unavailable when native exports exist but no provider/session is registered', async () => {
    ModalityProtoAdapter.registerModuleCapabilities(['rag'], fakeRAGModule());

    const availability = RAG.availability();

    expect(availability.available).toBe(false);
    expect(availability.source).toBe('wasm-exports');
    expect(availability.reason).toContain('no RAG provider or session handle');
    await expect(ragQuery('What is indexed?')).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
    });
  });

  it('rejects missing native RAG and voice-agent handles instead of marking them available', () => {
    expect(() => setRAGSessionHandle(0)).toThrow(SDKException);
    expect(() => setVoiceAgentHandle(0, {} as never)).toThrow(SDKException);

    expect(RAG.availability().available).toBe(false);
    expect(VoiceAgent.availability().available).toBe(false);
  });

  // `RAGConfiguration.persistIndex`/`.indexPath` were deleted outright
  // (idl/rag.proto): the RAG index is in-memory only now, so
  // NativeRAGSessionProvider has nothing left to reject at construction or
  // pipeline-create time -- it unconditionally reports `persistent: false`
  // instead of gating on a persistence request. These two tests used to
  // pin the (now structurally gone) persistence-rejection error path; they
  // now pin the unconditional non-persistent reality instead.
  it('creates a native Web RAG session with the config, and always reports non-persistent capabilities', async () => {
    ModalityProtoAdapter.registerModuleCapabilities(['rag'], fakeRAGModule());
    const provider = createRAGNativeProvider();
    setRAGProvider(provider);

    // Exercise the native provider directly — public ragCreatePipeline may
    // swap to composed CrossWasm when artifacts are not co-located.
    await expect(provider.ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelId: 'all-minilm-l6-v2',
      llmModelId: 'lfm2-350m-q4_k_m',
    }))).resolves.toBeUndefined();

    expect(RAG.capabilities().persistent).toBe(false);
  });

  it('accepts a plain (non-persistent) config at native Web RAG provider construction', () => {
    ModalityProtoAdapter.registerModuleCapabilities(['rag'], fakeRAGModule());

    expect(() => createRAGNativeProvider({
      config: {
        embeddingModelId: 'all-minilm-l6-v2',
      },
    })).not.toThrow();

    // Construction alone does not register the provider as active -- Swift
    // parity requires an explicit setRAGProvider()/setRAGSessionHandle()
    // call, same as the "keeps RAG unavailable" case above.
    expect(RAG.availability().available).toBe(false);
  });

  it('keeps native RAG document listing and removal unavailable without native APIs', async () => {
    ModalityProtoAdapter.registerModuleCapabilities(['rag'], fakeRAGModule());
    setRAGSessionHandle(7);

    expect(RAG.availability()).toMatchObject({
      available: true,
      source: 'wasm-session',
    });
    expect(RAG.capabilities()).toEqual({
      native: true,
      persistent: false,
      documentListing: false,
      documentRemoval: false,
    });

    await expect(RAG.listDocuments()).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      proto: { nestedMessage: expect.stringContaining('does not expose document listing') },
    });
    await expect(RAG.removeDocument('doc-1')).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      proto: { nestedMessage: expect.stringContaining('does not expose document-level removal') },
    });
  });

  it('preserves typed query overrides when dispatching through the native provider', async () => {
    const adapter = new RAGProtoAdapter(fakeRAGModule());
    let capturedQuery: RAGQueryOptions | undefined;
    const query = vi.spyOn(adapter, 'query').mockImplementation((session, options) => {
      expect(session).toBe(7);
      capturedQuery = options;
      return Promise.resolve(emptyRAGResult(options.query));
    });
    // `RAGConfiguration.similarityThreshold` was renamed `.scoreThreshold`.
    setRAGProvider(createRAGNativeProvider({
      adapter,
      session: 7,
      config: {
        llmModelId: 'test-llm',
        scoreThreshold: 0.35,
      },
    }));

    // `RAGQueryOverrides`'s flat `similarityThreshold`/`enableMultiQuery`/
    // `multiQueryCount`/`scopePrefix` knobs moved onto the nested
    // `retrieval: RAGRetrievalOptions`; `similarityThreshold` was itself
    // renamed `scoreThreshold` (idl/rag.proto).
    await expect(ragQuery('What is indexed?', {
      retrieval: {
        scoreThreshold: 0,
        enableMultiQuery: true,
        multiQueryCount: 5,
        scopePrefix: 'chat/session-7/',
      },
    })).resolves.toMatchObject({
      answer: 'no-op answer for: What is indexed?',
    });

    expect(query).toHaveBeenCalledOnce();
    expect(capturedQuery).toMatchObject({
      query: 'What is indexed?',
      retrieval: {
        scoreThreshold: 0,
        enableMultiQuery: true,
        multiQueryCount: 5,
        scopePrefix: 'chat/session-7/',
      },
    });
  });

  it('routes ragSearch through rac_rag_search_proto without generation', async () => {
    const adapter = new RAGProtoAdapter(fakeRAGModule());
    let captured: RAGSearchRequest | undefined;
    vi.spyOn(adapter, 'search').mockImplementation(async (session, request) => {
      expect(session).toBe(7);
      captured = request;
      return {
        chunks: [{
          chunkId: 'c1',
          text: 'indexed fact',
          // `RAGSearchResult.similarityScore`→`.score`; `.rank` was deleted
          // outright (reconstruct from array index instead).
          score: 0.88,
          metadata: {},
          startOffset: 0,
          endOffset: 12,
          tokenCount: 2,
        }],
        retrievalTimeMs: 3,
        requestId: 'search-1',
      };
    });
    // `RAGConfiguration.similarityThreshold` was renamed `.scoreThreshold`.
    setRAGProvider(createRAGNativeProvider({
      adapter,
      session: 7,
      config: { topK: 4, scoreThreshold: 0.2 },
    }));

    await expect(ragSearch('What is indexed?', 2)).resolves.toEqual([
      expect.objectContaining({ text: 'indexed fact', score: 0.88 }),
    ]);
    // `RAGSearchRequest` is `{ query, retrieval? }` now; `question` renamed
    // `query` and `retrievalTopK`/`similarityThreshold` moved onto the
    // nested `retrieval: RAGRetrievalOptions`.
    expect(captured).toMatchObject({
      query: 'What is indexed?',
      retrieval: {
        topK: 2,
        scoreThreshold: 0.2,
      },
    });
  });

  it('surfaces a clear error when rac_rag_search_proto is missing', async () => {
    const adapter = new RAGProtoAdapter(fakeRAGModule());
    vi.spyOn(adapter, 'search').mockResolvedValue(null);
    setRAGProvider(createRAGNativeProvider({
      adapter,
      session: 7,
      config: { topK: 3 },
    }));

    await expect(ragSearch('What is indexed?')).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      proto: { nestedMessage: expect.stringContaining('rac_rag_search_proto') },
    });
  });

  it('does not fabricate RAG document listings when the provider only exposes statistics', async () => {
    setRAGProvider({
      async ragCreatePipeline() {},
      async ragDestroyPipeline() {},
      async ragIngest() {},
      async ragQuery(question) {
        return emptyRAGResult(question);
      },
      async ragClearDocuments() {},
      async ragGetDocumentCount() {
        return 1;
      },
      // `RAGStatistics` was trimmed to 5 real fields + optional `error` --
      // `indexPath`/`statsJson`/`isPersistent`/`lastQueryMs`/`errorMessage`/
      // `errorCode` were all deleted outright (idl/rag.proto).
      async ragGetStatistics() {
        return {
          indexedDocuments: 1,
          indexedChunks: 4,
          totalTokensIndexed: 0,
          lastUpdatedMs: 0,
          vectorStoreSizeBytes: 0,
        };
      },
    });

    await expect(RAG.listDocuments()).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      proto: { nestedMessage: expect.stringContaining('does not expose document listing') },
    });
  });

  it('does not advertise provider document capabilities without matching methods', async () => {
    setRAGProvider({
      async ragCreatePipeline() {},
      async ragDestroyPipeline() {},
      async ragIngest() {},
      async ragQuery(question) {
        return emptyRAGResult(question);
      },
      async ragClearDocuments() {},
      async ragGetDocumentCount() {
        return 1;
      },
      ragGetCapabilities() {
        return {
          native: false,
          persistent: true,
          documentListing: true,
          documentRemoval: true,
        };
      },
    });

    expect(RAG.capabilities()).toEqual({
      native: false,
      persistent: true,
      documentListing: false,
      documentRemoval: false,
    });

    await expect(RAG.listDocuments()).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
    });
  });
});

// `RAGResult.totalTimeMs`/`.promptTokens`/`.completionTokens`/`.totalTokens`/
// `.errorMessage`/`.errorCode` were all deleted outright (idl/rag.proto):
// `retrievalTimeMs + generationTimeMs` is the closest surviving equivalent
// for total time, and `.usage: TokenUsage` replaced the flat token counts.
function emptyRAGResult(query: string): RAGResult {
  return {
    answer: `no-op answer for: ${query}`,
    retrievedChunks: [],
    contextUsed: '',
    retrievalTimeMs: 0,
    generationTimeMs: 0,
    requestId: 'test-rag-query',
  };
}

function fakeRAGModule(): ModalityProtoModule {
  const heap = new Uint8Array(4096);
  return {
    HEAPU8: heap,
    HEAPU32: new Uint32Array(heap.buffer),
    HEAP32: new Int32Array(heap.buffer),
    _malloc: () => 64,
    _free: () => {},
    _rac_proto_buffer_init: () => {},
    _rac_proto_buffer_free: () => {},
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_rag_session_create_proto: () => 0,
    _rac_rag_session_destroy_proto: () => {},
    _rac_rag_ingest_proto: () => 0,
    _rac_rag_query_proto: () => 0,
    _rac_rag_clear_proto: () => 0,
    _rac_rag_stats_proto: () => 0,
  };
}
