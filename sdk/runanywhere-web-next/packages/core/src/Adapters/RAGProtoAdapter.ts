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
import { clientFor } from '../runtime/HostRegistry';
import { Arg, type WorkerProtoClient } from '../runtime/WorkerProtoClient';

export class RAGProtoAdapter {
  static tryDefault(): RAGProtoAdapter | null {
    const client = clientFor('rag');
    return client ? new RAGProtoAdapter(client) : null;
  }

  constructor(private readonly client: WorkerProtoClient) {}

  async createSession(config: ProtoRAGConfiguration): Promise<number | null> {
    const bytes = RAGConfiguration.encode(config).finish();
    const { rc, outValues } = await this.client.call(
      'rac_rag_session_create_proto',
      [Arg.bytes(bytes), Arg.outU32()],
    );
    if (rc !== 0) throw new Error(`rac_rag_session_create_proto failed (rc=${rc})`);
    return outValues?.[0] || null;
  }

  async destroySession(session: number): Promise<void> {
    await this.client.callRc('rac_rag_session_destroy_proto', [Arg.num(session)]);
  }

  ingest(session: number, document: ProtoRAGDocument): Promise<ProtoRAGStatistics | null> {
    const bytes = RAGDocument.encode(document).finish();
    return this.client.callProto(
      'rac_rag_ingest_proto',
      [Arg.num(session), Arg.bytes(bytes), Arg.outProto()],
      RAGStatistics,
    );
  }

  query(session: number, query: ProtoRAGQueryOptions): Promise<ProtoRAGResult | null> {
    const bytes = RAGQueryOptions.encode(query).finish();
    return this.client.callProto(
      'rac_rag_query_proto',
      [Arg.num(session), Arg.bytes(bytes), Arg.outProto()],
      RAGResult,
    );
  }

  clear(session: number): Promise<ProtoRAGStatistics | null> {
    return this.client.callProto(
      'rac_rag_clear_proto',
      [Arg.num(session), Arg.outProto()],
      RAGStatistics,
    );
  }

  statistics(session: number): Promise<ProtoRAGStatistics | null> {
    return this.client.callProto(
      'rac_rag_stats_proto',
      [Arg.num(session), Arg.outProto()],
      RAGStatistics,
    );
  }
}
