// The rag namespace: retrieval-augmented generation. open() auto-loads the
// embedding model (and the LLM, if given) then returns a session with its own
// native handle (opaque string id), so several corpora can be open at once.
// Ingest/search/query/queryStream run in commons; the SDK only maps protos.
import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGSearchRequest,
  RAGSearchResponse,
  RAGSearchResult,
  RAGStatistics,
  RAGStreamEvent,
  RAGStreamEventKind,
} from '@runanywhere/proto-ts/rag';

import type { RaBackend } from '../backend.js';
import { toLlmGenerationOptions } from '../options.js';
import type { LlmOptions } from '../options.js';
import { bridgeStream } from '../stream.js';
import type { ModelRef } from '../types.js';
import type { ModelResolver } from './llm.js';

/** Retrieval and chunking controls for a RAG session. Mirrors Swift `RagConfig`. */
export interface RagConfig {
  retrievalTopK?: number;
  chunkSize?: number;
  chunkOverlap?: number;
  similarityThreshold?: number;
  /** Persist the index at this path; absent keeps it in memory. */
  persistPath?: string;
}

/** A document to ingest. */
export interface RagDoc {
  text: string;
  id?: string;
  metadata?: Record<string, string>;
  /** Source path/uri recorded with the document. */
  path?: string;
}

/** A retrieved chunk. Mirrors Swift `Match`. */
export interface Match {
  text: string;
  score: number;
  source: string;
  metadata: Record<string, string>;
}

/** A completed RAG answer. */
export interface RagResult {
  answer: string;
  sources: Match[];
  thinking: string;
  contextUsed: string;
  totalTimeMs: number;
}

/** Corpus statistics. */
export interface RagStats {
  documents: number;
  chunks: number;
  persistent: boolean;
}

/** Per-query controls. Mirrors Swift `RagQueryOptions`. */
export interface RagQueryOptions {
  retrievalTopK?: number;
  similarityThreshold?: number;
  generation?: LlmOptions;
}

/** A streamed RAG event. */
export type RagEvent =
  | { type: 'chunk'; match: Match }
  | { type: 'token'; token: string }
  | { type: 'completed'; result: RagResult }
  | { type: 'error'; message: string };

/** An open RAG session. Close it (or use `using`) to release the native handle. */
export interface RagSession {
  ingest(doc: RagDoc): Promise<RagStats>;
  ingestAll(docs: RagDoc[]): Promise<RagStats>;
  search(query: string, topK?: number): Promise<Match[]>;
  query(question: string, options?: RagQueryOptions): Promise<RagResult>;
  queryStream(question: string, options?: RagQueryOptions): AsyncIterableIterator<RagEvent>;
  stats(): Promise<RagStats>;
  clear(): Promise<RagStats>;
  close(): Promise<void>;
  [Symbol.asyncDispose](): Promise<void>;
}

export interface RagNamespace {
  /** Open a corpus. The embedding model is required; an LLM enables generation (query). */
  open(embeddingModel: ModelRef, llmModel?: ModelRef, config?: RagConfig): Promise<RagSession>;
}

function toStats(s: RAGStatistics): RagStats {
  return { documents: s.indexedDocuments, chunks: s.indexedChunks, persistent: s.isPersistent };
}

function toMatch(c: RAGSearchResult): Match {
  return {
    text: c.text,
    score: c.similarityScore,
    source: c.sourceDocument ?? '',
    metadata: c.metadata ?? {},
  };
}

function toResult(res: RAGResult): RagResult {
  return {
    answer: res.answer,
    sources: (res.retrievedChunks ?? []).map(toMatch),
    thinking: res.thinkingContent ?? '',
    contextUsed: res.contextUsed,
    totalTimeMs: res.totalTimeMs,
  };
}

function queryBytes(question: string, stream: boolean, options?: RagQueryOptions): Uint8Array {
  return RAGQueryOptions.encode(
    RAGQueryOptions.fromPartial({
      question,
      stream,
      ...(options?.retrievalTopK !== undefined ? { retrievalTopK: options.retrievalTopK } : {}),
      ...(options?.similarityThreshold !== undefined
        ? { similarityThreshold: options.similarityThreshold }
        : {}),
      ...(options?.generation ? { generation: toLlmGenerationOptions(options.generation) } : {}),
    })
  ).finish();
}

export function createRagNamespace(
  backend: RaBackend,
  resolveEmbedding: ModelResolver,
  resolveLlm: ModelResolver
): RagNamespace {
  return {
    async open(embeddingModel, llmModel, config) {
      await resolveEmbedding(embeddingModel.id);
      if (llmModel) await resolveLlm(llmModel.id);
      const cfg = RAGConfiguration.fromPartial({
        embeddingModelId: embeddingModel.id,
        llmModelId: llmModel?.id ?? '',
        persistIndex: config?.persistPath !== undefined,
        rerankResults: false,
        ...(config?.retrievalTopK !== undefined ? { topK: config.retrievalTopK } : {}),
        ...(config?.chunkSize !== undefined ? { chunkSize: config.chunkSize } : {}),
        ...(config?.chunkOverlap !== undefined ? { chunkOverlap: config.chunkOverlap } : {}),
        ...(config?.similarityThreshold !== undefined
          ? { similarityThreshold: config.similarityThreshold }
          : {}),
        ...(config?.persistPath !== undefined ? { indexPath: config.persistPath } : {}),
      });
      const id = await backend.ragOpen(RAGConfiguration.encode(cfg).finish());

      async function ingestOne(doc: RagDoc): Promise<RAGStatistics> {
        const bytes = RAGDocument.encode(
          RAGDocument.fromPartial({
            id: doc.id ?? '',
            text: doc.text,
            metadata: doc.metadata ?? {},
            ...(doc.path !== undefined ? { sourceUri: doc.path } : {}),
          })
        ).finish();
        return RAGStatistics.decode(await backend.ragIngest(id, bytes));
      }

      const session: RagSession = {
        async ingest(doc) {
          return toStats(await ingestOne(doc));
        },
        async ingestAll(docs) {
          let last: RAGStatistics | null = null;
          for (const doc of docs) last = await ingestOne(doc);
          return last ? toStats(last) : { documents: 0, chunks: 0, persistent: false };
        },
        async search(query, topK) {
          const bytes = RAGSearchRequest.encode(
            RAGSearchRequest.fromPartial({
              question: query,
              ...(topK !== undefined ? { retrievalTopK: topK } : {}),
            })
          ).finish();
          const res = RAGSearchResponse.decode(await backend.ragSearch(id, bytes));
          return res.chunks.map(toMatch);
        },
        async query(question, options) {
          const res = RAGResult.decode(await backend.ragQuery(id, queryBytes(question, false, options)));
          return toResult(res);
        },
        queryStream(question, options) {
          return bridgeStream<RagEvent>((sink) =>
            backend.ragQueryStream(id, queryBytes(question, true, options), (bytes) => {
              const ev = RAGStreamEvent.decode(bytes);
              switch (ev.kind) {
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED:
                  if (ev.chunk) sink.push({ type: 'chunk', match: toMatch(ev.chunk) });
                  break;
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_TOKEN:
                  sink.push({ type: 'token', token: ev.token });
                  break;
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED:
                  if (ev.result) sink.push({ type: 'completed', result: toResult(ev.result) });
                  break;
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR:
                  sink.push({ type: 'error', message: ev.error?.message ?? 'rag stream error' });
                  break;
                default:
                  break;
              }
            })
          );
        },
        async stats() {
          return toStats(RAGStatistics.decode(await backend.ragStats(id)));
        },
        async clear() {
          return toStats(RAGStatistics.decode(await backend.ragClear(id)));
        },
        async close() {
          await backend.ragClose(id);
        },
        async [Symbol.asyncDispose]() {
          await backend.ragClose(id);
        },
      };
      return session;
    },
  };
}
