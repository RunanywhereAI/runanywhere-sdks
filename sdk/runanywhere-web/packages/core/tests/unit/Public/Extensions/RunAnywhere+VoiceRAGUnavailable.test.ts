import { afterEach, describe, expect, it, vi } from 'vitest';
import { ProtoErrorCode, SDKException } from '../../../../src/Foundation/SDKException';
import {
  ModalityProtoAdapter,
  RAGProtoAdapter,
  type ModalityProtoModule,
} from '../../../../src/Adapters/ModalityProtoAdapter';
import { clearRunanywhereModule } from '../../../../src/runtime/EmscriptenModule';
import type { RAGQueryOptions } from '@runanywhere/proto-ts/rag';
import type { RAGResult } from '@runanywhere/proto-ts/rag_service';
import {
  RAG,
  createRAGNativeProvider,
  createDefaultRAGConfiguration,
  ragCreatePipeline,
  ragGetStatistics,
  ragQuery,
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

  it('rejects native Web RAG persistence until a browser storage-backed provider exists', async () => {
    ModalityProtoAdapter.registerModuleCapabilities(['rag'], fakeRAGModule());
    setRAGProvider(createRAGNativeProvider());

    await expect(ragCreatePipeline(createDefaultRAGConfiguration({
      embeddingModelPath: '/models/embed.onnx',
      llmModelPath: '/models/llm.gguf',
      persistIndex: true,
      indexPath: 'opfs://runanywhere/rag/docs',
    }))).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      proto: { nestedMessage: expect.stringContaining('browser storage-backed index adapter') },
    });

    expect(RAG.capabilities().persistent).toBe(false);
  });

  it('rejects persistent config at native Web RAG provider construction', () => {
    ModalityProtoAdapter.registerModuleCapabilities(['rag'], fakeRAGModule());

    expect(() => createRAGNativeProvider({
      config: {
        persistIndex: true,
        indexPath: 'opfs://runanywhere/rag/docs',
      },
    })).toThrow(SDKException);

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
      return emptyRAGResult(options.question);
    });
    setRAGProvider(createRAGNativeProvider({
      adapter,
      session: 7,
      config: {
        llmModelId: 'test-llm',
        similarityThreshold: 0.35,
      },
    }));

    await expect(ragQuery('What is indexed?', {
      similarityThreshold: 0,
      enableMultiQuery: true,
      multiQueryCount: 5,
      scopePrefix: 'chat/session-7/',
    })).resolves.toMatchObject({
      answer: 'no-op answer for: What is indexed?',
    });

    expect(query).toHaveBeenCalledOnce();
    expect(capturedQuery).toMatchObject({
      question: 'What is indexed?',
      similarityThreshold: 0,
      enableMultiQuery: true,
      multiQueryCount: 5,
      scopePrefix: 'chat/session-7/',
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
      async ragGetStatistics() {
        return {
          indexedDocuments: 1,
          indexedChunks: 4,
          totalTokensIndexed: 0,
          lastUpdatedMs: 0,
          indexPath: undefined,
          statsJson: undefined,
          vectorStoreSizeBytes: 0,
          isPersistent: false,
          lastQueryMs: 0,
          errorMessage: undefined,
          errorCode: 0,
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

function emptyRAGResult(question: string): RAGResult {
  return {
    answer: `no-op answer for: ${question}`,
    retrievedChunks: [],
    contextUsed: '',
    retrievalTimeMs: 0,
    generationTimeMs: 0,
    totalTimeMs: 0,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    errorMessage: undefined,
    errorCode: 0,
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
