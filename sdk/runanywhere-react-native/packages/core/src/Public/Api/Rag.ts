/**
 * `RunAnywhere.rag` — retrieval sessions with optional grounded generation.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGStreamEvent,
  RAGStreamEventKind,
} from '@runanywhere/proto-ts/rag';

import { SDKException } from '../../Foundation/Errors/SDKException';
import {
  ragClearDocuments,
  ragCreatePipeline,
  ragDestroyPipeline,
  ragGetStatistics,
  ragIngest,
  ragQuery,
} from '../Extensions/RAG/RunAnywhere+RAG';
import { decodeEvent, encode, preflight } from './Bridge';
import { ensureModelLoaded } from './Models';
import { toLlmOptions, toRagConfiguration } from './Options';
import { toMatch, toRagResult, toRagStats } from './Results';
import { pushStream } from './Stream';
import type {
  LlmOptions,
  Match,
  ModelRef,
  RagConfig,
  RagDocument,
  RagEvent,
  RagResult,
  RagSession,
  RagStats,
} from './Types';

/** Arguments for {@link rag.open}. */
export interface RagOpenOptions {
  embeddingModel: ModelRef;
  /** Omit for a retrieval-only session. */
  llmModel?: ModelRef;
  config?: RagConfig;
}

let activeSession: RagSession | null = null;

/**
 * Read a document file into text.
 *
 * @throws SDKException when `react-native-fs` is not installed, since the SDK
 * core has no filesystem of its own.
 */
async function readDocumentFile(path: string): Promise<string> {
  let fs: { readFile(path: string, encoding: string): Promise<string> };
  try {
    fs = require('react-native-fs');
  } catch {
    throw SDKException.notImplemented(
      'RagDocument.filePath needs the optional react-native-fs dependency; pass document text instead'
    );
  }
  return fs.readFile(path, 'utf8');
}

async function toRagDocument(document: RagDocument): Promise<RAGDocument> {
  const text =
    document.text ??
    (document.filePath ? await readDocumentFile(document.filePath) : '');
  if (text.length === 0) {
    throw SDKException.invalidInput('RagDocument carries no text');
  }
  return RAGDocument.fromPartial({
    text,
    ...(document.id ? { id: document.id } : {}),
    ...(document.metadata ? { metadata: document.metadata } : {}),
    ...(document.filePath ? { sourceUri: document.filePath } : {}),
  });
}

function buildQueryOptions(
  question: string,
  options: LlmOptions | undefined,
  topK?: number
): RAGQueryOptions {
  return RAGQueryOptions.fromPartial({
    question,
    generation: toLlmOptions(options),
    ...(topK !== undefined ? { retrievalTopK: topK } : {}),
  });
}

function createSession(config: RagConfig | undefined): RagSession {
  let closed = false;

  const requireOpen = (): void => {
    if (closed) {
      throw SDKException.invalidState('This RAG session is closed');
    }
  };

  const session: RagSession = {
    async ingest(document: RagDocument | RagDocument[]): Promise<void> {
      requireOpen();
      const batch = Array.isArray(document) ? document : [document];
      for (const item of batch) {
        await ragIngest(await toRagDocument(item));
      }
    },

    async ingestAll(documents: RagDocument[]): Promise<void> {
      return session.ingest(documents);
    },

    async search(query: string, topK?: number): Promise<Match[]> {
      requireOpen();
      // commons exposes no retrieval-only proto verb, so retrieval rides the
      // query path with generation clamped to a single token.
      const result = await ragQuery(
        buildQueryOptions(query, { maxOutputTokens: 1 }, topK ?? config?.topK)
      );
      return result.retrievedChunks.map(toMatch);
    },

    async query(question: string, options?: LlmOptions): Promise<RagResult> {
      requireOpen();
      return toRagResult(await ragQuery(buildQueryOptions(question, options)));
    },

    queryStream(question: string, options?: LlmOptions): AsyncIterable<RagEvent> {
      requireOpen();
      const retrieved: Match[] = [];
      let cancel: (() => Promise<void>) | null = null;

      return pushStream<RagEvent>(
        async (controller) => {
          const native = await preflight();
          cancel = async () => {
            await native.ragCancelProto().catch(() => undefined);
          };
          const requestBytes = encode(
            buildQueryOptions(question, options),
            RAGQueryOptions
          );
          void native
            .ragQueryStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
              const event = decodeEvent(eventBytes, RAGStreamEvent);
              switch (event.kind) {
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED:
                  if (event.chunk) retrieved.push(toMatch(event.chunk));
                  break;
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CONTEXT_READY:
                  controller.push({ type: 'retrieved', matches: [...retrieved] });
                  break;
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_TOKEN:
                  if (event.token.length > 0) {
                    controller.push({
                      type: 'token',
                      text: event.token,
                      kind: 'text',
                    });
                  }
                  break;
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED:
                  controller.push({
                    type: 'completed',
                    result: toRagResult(event.result ?? RAGResult.fromPartial({})),
                  });
                  controller.finish();
                  break;
                case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR:
                  controller.fail(
                    event.error
                      ? new SDKException(event.error)
                      : SDKException.generationFailedWith('RAG query failed')
                  );
                  break;
                default:
                  break;
              }
            })
            .then(() => controller.finish())
            .catch((error: Error) => controller.fail(error));
        },
        async () => {
          await cancel?.();
        }
      );
    },

    async stats(): Promise<RagStats> {
      requireOpen();
      return toRagStats(await ragGetStatistics());
    },

    async clear(): Promise<void> {
      requireOpen();
      await ragClearDocuments();
    },

    async close(): Promise<void> {
      if (closed) return;
      closed = true;
      if (activeSession === session) activeSession = null;
      await ragDestroyPipeline();
    },
  };

  return session;
}

/** Retrieval-augmented generation sessions. */
export const rag = {
  /**
   * Open a session over an embedding model, optionally with an answer model.
   *
   * commons keeps one RAG pipeline per process today, so a second concurrent
   * session is rejected instead of silently replacing the first.
   *
   * @example
   * const session = await RunAnywhere.rag.open({ embeddingModel: { id: 'all-minilm' } });
   * await session.ingest({ text: 'RunAnywhere runs models on device.' });
   *
   * @throws SDKException when a session is already open or the models fail to load.
   */
  async open(options: RagOpenOptions): Promise<RagSession> {
    if (activeSession) {
      throw SDKException.invalidState(
        'A RAG session is already open; close it before opening another'
      );
    }
    await ensureModelLoaded(
      options.embeddingModel.id,
      ModelCategory.MODEL_CATEGORY_EMBEDDING
    );
    if (options.llmModel) {
      await ensureModelLoaded(
        options.llmModel.id,
        ModelCategory.MODEL_CATEGORY_LANGUAGE
      );
    }
    await ragCreatePipeline(
      toRagConfiguration(
        options.embeddingModel.id,
        options.llmModel?.id ?? '',
        options.config
      )
    );
    const session = createSession(options.config);
    activeSession = session;
    return session;
  },
};
