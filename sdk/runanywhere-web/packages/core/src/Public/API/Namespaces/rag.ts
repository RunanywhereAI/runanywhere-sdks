/**
 * `RunAnywhere.rag` — retrieval-augmented sessions over an ingested corpus.
 */

import { RAGStreamEventKind } from '@runanywhere/proto-ts/rag';
import { SDKException } from '../../../Foundation/SDKException.js';
import {
  ragClearDocuments,
  ragCreatePipeline,
  ragDestroyPipeline,
  ragGetStatistics,
  ragIngestDocument,
  ragQuery,
  ragQueryStream,
  ragSearch,
} from '../../Extensions/RunAnywhere+RAG.js';
import type { ModelRef, RagDocument } from '../Inputs.js';
import type { LlmOptions, RagConfig } from '../Options.js';
import type { RagEvent } from '../Events.js';
import type { Match, RagResult, RagStats } from '../Results.js';
import { optionDefaults } from '../Options.js';
import { toMatch, toProtoLlmOptions, toRagResult, toRagStats } from '../Mapping.js';
import { ensureReady } from '../Runtime/Prerequisites.js';

/** A live corpus with its own retrieval index and optional answer model. */
export interface RagSession {
  /** Index one document or a batch of documents. */
  ingest(document: RagDocument): Promise<void>;
  ingest(documents: readonly RagDocument[]): Promise<void>;
  /** Retrieve matching chunks without generating an answer. */
  search(query: string, topK?: number): Promise<Match[]>;
  /** Answer a question grounded in the corpus. */
  query(question: string, options?: LlmOptions): Promise<RagResult>;
  /** Answer a question, emitting `retrieved`, `token`, and `completed`. */
  queryStream(question: string, options?: LlmOptions): AsyncIterable<RagEvent>;
  /** Document, chunk, and index-size counters. */
  stats(): Promise<RagStats>;
  /** Drop every indexed document, keeping the session open. */
  clear(): Promise<void>;
  /** Tear the session down and release its index. */
  close(): Promise<void>;
}

// The Web RAG pipeline is a process-wide singleton in commons and in the
// TypeScript vector index, so only one session can be open at a time.
let openSession: RagSession | null = null;

function requireOpen(session: RagSession, verb: string): void {
  if (openSession !== session) {
    throw SDKException.invalidState(`This RAG session is closed; ${verb} is unavailable.`);
  }
}

function toProtoConfig(
  embeddingModel: ModelRef,
  llmModel: ModelRef | undefined,
  config: RagConfig | undefined,
) {
  const defaults = optionDefaults.rag();
  return {
    embeddingModelId: embeddingModel.id,
    llmModelId: llmModel?.id ?? '',
    topK: config?.topK ?? defaults.topK,
    chunkSize: config?.chunkSize ?? defaults.chunkSize,
    chunkOverlap: config?.chunkOverlap ?? defaults.chunkOverlap,
    similarityThreshold: config?.similarityThreshold ?? defaults.similarityThreshold,
    persistIndex: config?.persistPath !== undefined,
    indexPath: config?.persistPath,
    rerankResults: defaults.rerankResults,
  };
}

function createSession(): RagSession {
  const session: RagSession = {
    async ingest(input: RagDocument | readonly RagDocument[]): Promise<void> {
      requireOpen(session, 'ingest');
      const documents = Array.isArray(input) ? input : [input as RagDocument];
      for (const document of documents) {
        await ragIngestDocument({
          id: document.name ?? '',
          text: document.text,
          metadata: document.metadata ?? {},
          sizeBytes: document.text.length,
        });
      }
    },

    async search(query: string, topK?: number): Promise<Match[]> {
      requireOpen(session, 'search');
      return (await ragSearch(query, topK)).map(toMatch);
    },

    async query(question: string, options?: LlmOptions): Promise<RagResult> {
      requireOpen(session, 'query');
      const result = await ragQuery(question, { generation: toProtoLlmOptions(options) });
      if (result.error) throw new SDKException(result.error);
      return toRagResult(result);
    },

    queryStream(question: string, options?: LlmOptions): AsyncIterable<RagEvent> {
      requireOpen(session, 'queryStream');
      return (async function* answer(): AsyncGenerator<RagEvent> {
        const events = ragQueryStream(question, { generation: toProtoLlmOptions(options) });
        let announcedSources = false;
        for await (const event of events) {
          if (event.error) throw new SDKException(event.error);
          if (!announcedSources && event.result?.retrievedChunks.length) {
            announcedSources = true;
            yield { type: 'retrieved', matches: event.result.retrievedChunks.map(toMatch) };
          }
          if (event.token) yield { type: 'token', text: event.token, kind: 'text' };
          if (event.kind === RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED && event.result) {
            if (!announcedSources) {
              yield { type: 'retrieved', matches: event.result.retrievedChunks.map(toMatch) };
            }
            yield { type: 'completed', result: toRagResult(event.result) };
          }
        }
      })();
    },

    async stats(): Promise<RagStats> {
      requireOpen(session, 'stats');
      return toRagStats(await ragGetStatistics());
    },

    async clear(): Promise<void> {
      requireOpen(session, 'clear');
      await ragClearDocuments();
    },

    async close(): Promise<void> {
      if (openSession !== session) return;
      openSession = null;
      await ragDestroyPipeline();
    },
  };
  return session;
}

/** Retrieval-augmented generation over a corpus you ingest. */
export const rag = {
  /**
   * Open a session, loading the embedding model and, when given, the answer model.
   *
   * The Web RAG index is process-wide, so a second session cannot be opened
   * until the first one is closed.
   *
   * @param llmModel Omit for retrieval-only sessions.
   * @throws SDKException when a session is already open or the models cannot be loaded.
   *
   * @example
   * const session = await RunAnywhere.rag.open({ id: 'all-minilm-l6' }, { id: 'qwen3-0.6b' });
   * await session.ingest({ text: 'RunAnywhere runs models on device.' });
   */
  async open(
    embeddingModel: ModelRef,
    llmModel?: ModelRef,
    config?: RagConfig,
  ): Promise<RagSession> {
    if (openSession) {
      throw SDKException.invalidState(
        'A RAG session is already open. Close it before opening another; the Web index is process-wide.',
      );
    }
    await ensureReady();
    await ragCreatePipeline(toProtoConfig(embeddingModel, llmModel, config));
    const session = createSession();
    openSession = session;
    return session;
  },
};
