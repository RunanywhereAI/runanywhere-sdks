import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
  RAGStreamEvent,
  RAGStreamEventKind,
  type RAGConfiguration as ProtoRAGConfiguration,
  type RAGDocument as ProtoRAGDocument,
  type RAGQueryOptions as ProtoRAGQueryOptions,
  type RAGResult as ProtoRAGResult,
  type RAGStatistics as ProtoRAGStatistics,
  type RAGStreamEvent as ProtoRAGStreamEvent,
} from '@runanywhere/proto-ts/rag';
import { SDKException } from '../Foundation/SDKException.js';
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import { getBackendWorkerOwner } from '../runtime/BackendWorkerModelOwnership.js';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

/** Sessions created on the ONNX BackendWorker — follow-up RPCs must hit the same heap. */
const workerOwnedSessions = new Set<number>();

export class RAGProtoAdapter {
  static tryDefault(): RAGProtoAdapter | null {
    const mod = adapterState.modalitySlots.rag;
    return mod ? new RAGProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  missingRAGExports(): string[] {
    return missingExports(this.module, [
      '_rac_rag_session_create_proto',
      '_rac_rag_session_destroy_proto',
      '_rac_rag_ingest_proto',
      '_rac_rag_query_proto',
      '_rac_rag_clear_proto',
      '_rac_rag_stats_proto',
    ]);
  }

  supportsProtoRAG(): boolean {
    return this.missingRAGExports().length === 0;
  }

  async createSession(config: ProtoRAGConfiguration): Promise<number | null> {
    const host = this.workerHostForEmbedding(config.embeddingModelId);
    if (host) {
      const response = await host.infer('rag.sessionCreate', {
        requestBytes: RAGConfiguration.encode(config).finish(),
      }) as { session?: number };
      const session = response?.session || null;
      if (session) workerOwnedSessions.add(session);
      return session;
    }
    if (!ensureExports(this.module, 'rag.createSession', ['_rac_rag_session_create_proto'])) {
      return null;
    }
    const bridge = this.bridge();
    const outSession = bridge.allocOutPtr();
    if (!outSession) return null;
    try {
      const bytes = RAGConfiguration.encode(config).finish();
      const rc = bridge.withHeapBytes(bytes, (configPtr, configSize) => (
        this.module._rac_rag_session_create_proto!(configPtr, configSize, outSession)
      ));
      if (rc !== 0) {
        logger.warning(`rac_rag_session_create_proto returned ${formatRacResult(rc)}`);
        return null;
      }
      return bridge.readU32(outSession) || null;
    } finally {
      bridge.free(outSession);
    }
  }

  async destroySession(session: number): Promise<void> {
    const host = this.workerHostForSession(session);
    if (host) {
      try {
        await host.infer('rag.sessionDestroy', { session });
      } finally {
        workerOwnedSessions.delete(session);
      }
      return;
    }
    if (!this.module._rac_rag_session_destroy_proto) {
      logger.warning('rag.destroySession: module missing _rac_rag_session_destroy_proto');
      return;
    }
    this.module._rac_rag_session_destroy_proto(session);
  }

  async ingest(session: number, document: ProtoRAGDocument): Promise<ProtoRAGStatistics | null> {
    const host = this.workerHostForSession(session);
    if (host) {
      const response = await host.infer('rag.ingest', {
        session,
        requestBytes: RAGDocument.encode(document).finish(),
      }) as { resultBytes?: Uint8Array };
      return response?.resultBytes ? RAGStatistics.decode(response.resultBytes) : null;
    }
    if (!ensureExports(this.module, 'rag.ingest', ['_rac_rag_ingest_proto'])) return null;
    return this.bridge().withEncodedRequest(
      document,
      RAGDocument,
      RAGStatistics,
      (documentPtr, documentSize, outStats) => (
        this.module._rac_rag_ingest_proto!(session, documentPtr, documentSize, outStats)
      ),
      'rac_rag_ingest_proto',
    );
  }

  async query(session: number, query: ProtoRAGQueryOptions): Promise<ProtoRAGResult | null> {
    const host = this.workerHostForSession(session);
    if (host) {
      const response = await host.infer('rag.query', {
        session,
        requestBytes: RAGQueryOptions.encode(query).finish(),
      }) as { resultBytes?: Uint8Array };
      return response?.resultBytes ? RAGResult.decode(response.resultBytes) : null;
    }
    if (!ensureExports(this.module, 'rag.query', ['_rac_rag_query_proto'])) return null;
    return this.bridge().withEncodedRequest(
      query,
      RAGQueryOptions,
      RAGResult,
      (queryPtr, querySize, outResult) => (
        this.module._rac_rag_query_proto!(session, queryPtr, querySize, outResult)
      ),
      'rac_rag_query_proto',
    );
  }

  /**
   * Streaming query: emits a RAGStreamEvent per generated token (kind = TOKEN),
   * then a terminal COMPLETED carrying the full RAGResult, or an ERROR event.
   * The native callback returns a bool — returning false stops generation early
   * (backpressure), which is how iterator cancellation propagates.
   */
  queryStream(session: number, query: ProtoRAGQueryOptions): AsyncIterable<ProtoRAGStreamEvent> {
    if (workerOwnedSessions.has(session)) {
      throw SDKException.backendNotAvailable(
        'rag.queryStream',
        'Native RAG streaming is not yet available through the ONNX BackendWorker.',
      );
    }
    this.requireStreamExports();
    const encoded = RAGQueryOptions.encode(query).finish();
    return streamCallback(
      this.module,
      RAGStreamEvent,
      'rac_rag_query_stream_proto',
      (callbackPtr) => this.bridge().withHeapBytes(encoded, (queryPtr, querySize) => (
        this.module._rac_rag_query_stream_proto!(session, queryPtr, querySize, callbackPtr, 0)
      )),
      (event) => (
        event.kind === RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED
        || event.kind === RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR
      ),
      undefined,
      // Non-success rc synthesizes a terminal ERROR event instead of rejecting
      // the iterator (parity with the LLM stream adapter).
      (rc) => RAGStreamEvent.fromPartial({
        kind: RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR,
        errorCode: rc,
        errorMessage: `RAG stream failed: ${formatRacResult(rc)}`,
      }),
      /* callbackReturnsBool */ true,
    );
  }

  private requireStreamExports(): void {
    if (!ensureExports(this.module, 'rag.queryStream', ['_rac_rag_query_stream_proto'])) {
      throw new Error('rac_rag_query_stream_proto is unavailable');
    }
  }

  async clear(session: number): Promise<ProtoRAGStatistics | null> {
    const host = this.workerHostForSession(session);
    if (host) {
      const response = await host.infer('rag.clear', { session }) as { resultBytes?: Uint8Array };
      return response?.resultBytes ? RAGStatistics.decode(response.resultBytes) : null;
    }
    if (!ensureExports(this.module, 'rag.clear', ['_rac_rag_clear_proto'])) return null;
    return this.bridge().callResultProto(
      RAGStatistics,
      (outStats) => this.module._rac_rag_clear_proto!(session, outStats),
      'rac_rag_clear_proto',
    );
  }

  async statistics(session: number): Promise<ProtoRAGStatistics | null> {
    const host = this.workerHostForSession(session);
    if (host) {
      const response = await host.infer('rag.stats', { session }) as { resultBytes?: Uint8Array };
      return response?.resultBytes ? RAGStatistics.decode(response.resultBytes) : null;
    }
    if (!ensureExports(this.module, 'rag.statistics', ['_rac_rag_stats_proto'])) return null;
    return this.bridge().callResultProto(
      RAGStatistics,
      (outStats) => this.module._rac_rag_stats_proto!(session, outStats),
      'rac_rag_stats_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  /**
   * Route native session create to the BackendWorker that owns the embedding
   * model — not "any ONNX model is loaded". Matches ownership-based RAG planning.
   */
  private workerHostForEmbedding(embeddingModelId: string) {
    if (getBackendWorkerOwner(embeddingModelId) !== 'onnx') return null;
    return this.requireOnnxWorkerHost('rag.sessionCreate');
  }

  private workerHostForSession(session: number) {
    if (!workerOwnedSessions.has(session)) return null;
    return this.requireOnnxWorkerHost('rag');
  }

  private requireOnnxWorkerHost(operation: string) {
    const host = getActiveBackendWorkerHost('onnx');
    if (!host || host.diagnostics.executionContext !== 'worker') {
      throw SDKException.backendNotAvailable(
        operation,
        'ONNX BackendWorker is required for this native RAG session; '
          + 'main-thread fallback is disabled for worker-owned sessions.',
      );
    }
    return host;
  }
}
