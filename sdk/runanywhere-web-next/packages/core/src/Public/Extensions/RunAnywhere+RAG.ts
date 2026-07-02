import {
  type RAGConfiguration as ProtoRAGConfiguration,
  type RAGDocument as ProtoRAGDocument,
  type RAGQueryOptions as ProtoRAGQueryOptions,
  type RAGResult as ProtoRAGResult,
  type RAGStatistics as ProtoRAGStatistics,
} from '@runanywhere/proto-ts/rag';
import { DownloadAdapter } from '../../Adapters/DownloadAdapter';
import { runDownload } from '../../Adapters/DownloadRunner';
import { ModelRegistryAdapter } from '../../Adapters/ModelRegistryAdapter';
import { RAGProtoAdapter } from '../../Adapters/RAGProtoAdapter';
import { SDKException } from '../../Foundation/SDKException';
import { clientFor } from '../../runtime/HostRegistry';
import { RunAnywhereSDK } from '../RunAnywhere';

declare module '../RunAnywhere' {
  interface RunAnywhereSDK {
    ragCreateSession(config: ProtoRAGConfiguration): Promise<number | null>;
    ragDestroySession(session: number): Promise<void>;
    ragIngest(session: number, document: ProtoRAGDocument): Promise<ProtoRAGStatistics | null>;
    ragQuery(session: number, query: ProtoRAGQueryOptions): Promise<ProtoRAGResult | null>;
    ragClear(session: number): Promise<ProtoRAGStatistics | null>;
    ragStats(session: number): Promise<ProtoRAGStatistics | null>;
  }
}

function rag(): RAGProtoAdapter {
  const adapter = RAGProtoAdapter.tryDefault();
  if (!adapter) throw SDKException.backendNotAvailable('RAG');
  return adapter;
}

// The RAG pipeline (embedding + LLM) runs entirely in the RAG worker, so both
// referenced models must be resolvable there. A model downloaded through a
// different backend worker (e.g. an LLM in the llama.cpp worker) is registered
// in the RAG worker but has no local_path until it is hydrated there. Hydrate
// each referenced model on the RAG worker's own client so session creation can
// resolve them — mirrors how single-process SDKs already have every model in
// one registry.
async function hydrateOnRagWorker(modelId: string): Promise<void> {
  if (!modelId) return;
  const client = clientFor('rag');
  if (!client) return;
  const model = (await ModelRegistryAdapter.tryDefault()?.get(modelId)) ?? undefined;
  await runDownload(new DownloadAdapter(client), modelId, model);
}

RunAnywhereSDK.prototype.ragCreateSession = async function (this: RunAnywhereSDK, config) {
  this.ensureInitialized();
  await hydrateOnRagWorker(config.embeddingModelId);
  await hydrateOnRagWorker(config.llmModelId);
  return rag().createSession(config);
};

RunAnywhereSDK.prototype.ragDestroySession = function (this: RunAnywhereSDK, session) {
  return rag().destroySession(session);
};

RunAnywhereSDK.prototype.ragIngest = function (this: RunAnywhereSDK, session, document) {
  this.ensureInitialized();
  return rag().ingest(session, document);
};

RunAnywhereSDK.prototype.ragQuery = function (this: RunAnywhereSDK, session, query) {
  this.ensureInitialized();
  return rag().query(session, query);
};

RunAnywhereSDK.prototype.ragClear = function (this: RunAnywhereSDK, session) {
  return rag().clear(session);
};

RunAnywhereSDK.prototype.ragStats = function (this: RunAnywhereSDK, session) {
  return rag().statistics(session);
};
