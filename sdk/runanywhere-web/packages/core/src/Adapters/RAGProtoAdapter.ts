import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
  type RAGConfiguration as ProtoRAGConfiguration,
  type RAGDocument as ProtoRAGDocument,
  type RAGQueryOptions as ProtoRAGQueryOptions,
  type RAGResult as ProtoRAGResult,
  type RAGStatistics as ProtoRAGStatistics,
} from '@runanywhere/proto-ts/rag';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

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

  createSession(config: ProtoRAGConfiguration): number | null {
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

  destroySession(session: number): void {
    if (!this.module._rac_rag_session_destroy_proto) {
      logger.warning('rag.destroySession: module missing _rac_rag_session_destroy_proto');
      return;
    }
    this.module._rac_rag_session_destroy_proto(session);
  }

  ingest(session: number, document: ProtoRAGDocument): ProtoRAGStatistics | null {
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

  query(session: number, query: ProtoRAGQueryOptions): ProtoRAGResult | null {
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

  clear(session: number): ProtoRAGStatistics | null {
    if (!ensureExports(this.module, 'rag.clear', ['_rac_rag_clear_proto'])) return null;
    return this.bridge().callResultProto(
      RAGStatistics,
      (outStats) => this.module._rac_rag_clear_proto!(session, outStats),
      'rac_rag_clear_proto',
    );
  }

  statistics(session: number): ProtoRAGStatistics | null {
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
}
