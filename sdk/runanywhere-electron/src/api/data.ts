// data.ts — the `embeddings`, `rerank`, and `rag` namespaces.
//
// RAG crosses the C ABI as serialized runanywhere.v1 protos, so this file owns the
// encode/decode and hands plain objects to callers.

import * as fs from 'fs';

import { SDKException } from '../errors';
import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGSearchRequest,
  RAGSearchResponse,
  RAGStatistics,
  RAGStreamEvent,
  RAGStreamEventKind,
} from '../proto/rag';
import type { RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import { RAC_CATEGORY, RAC_FRAMEWORK } from './native-backend';
import { LLM_DEFAULTS, RAG_DEFAULTS, toNativeEmbedOptions } from './options';
import type { EmbedOptions, LlmOptions, RagConfig } from './options';
import { ModelCategory, TokenKind, newRequestId } from './types';
import type {
  Embedding,
  Match,
  ModelRef,
  RagDocument as PublicRagDocument,
  RagEvent,
  RagResult as PublicRagResult,
  RagStats,
  RankedResult,
} from './types';

/** What the data namespaces need from the facade. */
export interface DataDeps {
  backend: RaBackend;
  hub: SdkEventHub;
  requireReady(): void;
}

// ---------------------------------------------------------------------------
// embeddings
// ---------------------------------------------------------------------------

/** Text embeddings. */
export interface EmbeddingsNamespace {
  /**
   * Embed every text, returning vectors in input order.
   *
   * @throws SDKException when no embedding model is loaded.
   * @example
   * const [a, b] = await RunAnywhere.embeddings.embed(['cat', 'kitten']);
   * console.log(a.vector.length);
   */
  embed(texts: string[], options?: EmbedOptions): Promise<Embedding[]>;
}

/** Build the `embeddings` namespace over a backend. */
export function createEmbeddingsNamespace(deps: DataDeps): EmbeddingsNamespace {
  return {
    async embed(texts, options = {}) {
      deps.requireReady();
      if (!Array.isArray(texts)) {
        throw SDKException.validationFailed({
          fieldPath: 'texts',
          message: 'embed takes an array of strings',
        });
      }
      if (!texts.length) return [];
      const loaded = await deps.backend.loaded('embedder');
      if (!loaded) {
        throw SDKException.invalidState(
          'no embedding model is loaded — call models.load() first'
        );
      }
      const vectors = await deps.backend.embed(texts, toNativeEmbedOptions(options));
      return vectors.map((vector, index) => ({ index, vector }));
    },
  };
}

// ---------------------------------------------------------------------------
// rerank
// ---------------------------------------------------------------------------

/** Cross-encoder reranking. */
export interface RerankNamespace {
  /**
   * Score `documents` against `query`, best first.
   *
   * @throws SDKException when no reranker is loaded.
   * @example
   * const ranked = await RunAnywhere.rerank.rerank('best cat food', docs, 3);
   * console.log(ranked[0].index, ranked[0].relevanceScore);
   */
  rerank(query: string, documents: string[], topN?: number): Promise<RankedResult[]>;
}

/** Build the `rerank` namespace over a backend. */
export function createRerankNamespace(deps: DataDeps): RerankNamespace {
  return {
    async rerank(query, documents, topN) {
      deps.requireReady();
      if (!documents?.length) return [];
      const loaded = await deps.backend.loaded('rerank');
      if (!loaded) {
        throw SDKException.invalidState('no rerank model is loaded — call models.load() first');
      }
      const scored = await deps.backend.rerank(query, documents, topN);
      return scored
        .slice()
        .sort((a, b) => a.rank - b.rank)
        .map((s) => ({ index: s.index, relevanceScore: s.score }));
    },
  };
}

// ---------------------------------------------------------------------------
// rag
// ---------------------------------------------------------------------------

/** A live retrieval-augmented generation corpus. */
export interface RagSession {
  /** Chunk, embed, and index one document or several. */
  ingest(document: PublicRagDocument | PublicRagDocument[]): Promise<void>;
  /** Retrieve the closest chunks without generating an answer. */
  search(query: string, topK?: number): Promise<Match[]>;
  /** Answer `question` grounded in the corpus. */
  query(question: string, options?: LlmOptions): Promise<PublicRagResult>;
  /** Stream the grounded answer as retrieved / token / completed events. */
  queryStream(question: string, options?: LlmOptions): AsyncIterableIterator<RagEvent>;
  /** Size of the index. */
  stats(): Promise<RagStats>;
  /** Drop every indexed document, keeping the session. */
  clear(): Promise<void>;
  /** Release the native session. Idempotent. */
  close(): Promise<void>;
}

/** Retrieval-augmented generation. */
export interface RagNamespace {
  /**
   * Open a corpus over an embedding model, optionally with an LLM for answers.
   *
   * @throws SDKException when a model cannot be downloaded, registered, or loaded.
   * @example
   * const s = await RunAnywhere.rag.open({ id: 'minilm' }, { id: 'qwen2.5-0.5b' });
   * await s.ingest(ragDocument.text('RunAnywhere runs models on-device.'));
   */
  open(
    embeddingModel: ModelRef,
    llmModel?: ModelRef,
    config?: RagConfig
  ): Promise<RagSession>;
}

function toMatch(chunk: {
  text: string;
  score: number;
  metadata: { [key: string]: string };
  sourceDocument?: string;
}): Match {
  const metadata = { ...chunk.metadata };
  if (chunk.sourceDocument) metadata.sourceDocument = chunk.sourceDocument;
  return { text: chunk.text, score: chunk.score, metadata };
}

function toRagResult(raw: RAGResult, requestId: string, model: string): PublicRagResult {
  const generationMs = raw.generationTimeMs || 0;
  return {
    answer: raw.answer,
    sources: raw.retrievedChunks.map(toMatch),
    thinkingText: raw.thinkingContent || undefined,
    inputTokens: raw.usage?.inputTokens ?? 0,
    outputTokens: raw.usage?.outputTokens ?? 0,
    // Commons reports retrieval and generation time but not time-to-first-token for
    // a non-streamed query, so retrieval time is the closest honest stand-in.
    timeToFirstTokenMs: raw.retrievalTimeMs,
    tokensPerSecond: generationMs > 0 ? (raw.usage?.outputTokens ?? 0) / (generationMs / 1000) : 0,
    requestId: raw.requestId || requestId,
    model,
  };
}

// Only the sampling knobs commons' RAG pipeline reads; tools and structured output
// are not part of a grounded-answer request.
function toRagGeneration(options: LlmOptions = {}): {
  maxOutputTokens: number;
  temperature: number;
  topP: number;
  topK?: number;
  systemPrompt?: string;
} {
  const out = {
    maxOutputTokens: options.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
    temperature: options.temperature ?? LLM_DEFAULTS.temperature,
    topP: options.topP ?? LLM_DEFAULTS.topP,
  } as {
    maxOutputTokens: number;
    temperature: number;
    topP: number;
    topK?: number;
    systemPrompt?: string;
  };
  if (options.topK !== undefined) out.topK = options.topK;
  if (options.systemPrompt !== undefined) out.systemPrompt = options.systemPrompt;
  return out;
}

function documentBytes(doc: PublicRagDocument): Uint8Array {
  let text = doc.text;
  if (text == null && doc.path) text = fs.readFileSync(doc.path, 'utf8');
  if (!text) {
    throw SDKException.validationFailed({
      fieldPath: 'document.text',
      message: 'a RAG document needs text or a readable path',
    });
  }
  return RAGDocument.encode(
    RAGDocument.fromPartial({
      id: doc.id ?? '',
      text,
      metadata: doc.metadata ?? {},
      sourceUri: doc.path,
    })
  ).finish();
}

/** Build the `rag` namespace over a backend. */
export function createRagNamespace(deps: DataDeps): RagNamespace {
  // A session's models must be in commons' global registry so session-create can
  // resolve their ids to on-disk paths; the Electron SDK otherwise loads by path.
  const registerFor = async (
    ref: ModelRef,
    category: number,
    framework: number
  ): Promise<string> => {
    const resolved = await deps.backend.resolveModel(ref.id);
    await deps.backend.registerModel(resolved.id, resolved.primary, category, framework);
    return resolved.id;
  };

  return {
    async open(embeddingModel, llmModel, config = {}) {
      deps.requireReady();
      if (!embeddingModel?.id) {
        throw SDKException.validationFailed({
          fieldPath: 'embeddingModel.id',
          message: 'rag.open needs an embedding model id',
        });
      }
      const embeddingId = await registerFor(
        embeddingModel,
        RAC_CATEGORY.EMBEDDING,
        RAC_FRAMEWORK.ONNX
      );
      deps.hub.emit({ type: 'modelLoaded', id: embeddingId, category: ModelCategory.EMBEDDING });
      let llmId = '';
      if (llmModel?.id) {
        const resolved = await deps.backend.resolveModel(llmModel.id);
        const framework = /\.(onnx|ort)$/i.test(resolved.primary)
          ? RAC_FRAMEWORK.ONNX
          : RAC_FRAMEWORK.LLAMACPP;
        await deps.backend.registerModel(
          resolved.id,
          resolved.primary,
          RAC_CATEGORY.LANGUAGE,
          framework
        );
        llmId = resolved.id;
        deps.hub.emit({ type: 'modelLoaded', id: llmId, category: ModelCategory.LANGUAGE });
      }

      const configBytes = RAGConfiguration.encode(
        RAGConfiguration.fromPartial({
          embeddingModelId: embeddingId,
          llmModelId: llmId,
          topK: config.topK ?? RAG_DEFAULTS.topK,
          chunkSize: config.chunkSize ?? RAG_DEFAULTS.chunkSize,
          chunkOverlap: config.chunkOverlap ?? RAG_DEFAULTS.chunkOverlap,
          scoreThreshold: config.scoreThreshold,
        })
      ).finish();

      const handle = await deps.backend.ragOpen(configBytes);
      const defaultTopK = config.topK ?? RAG_DEFAULTS.topK;
      let closed = false;

      const assertOpen = (): void => {
        if (closed) throw SDKException.invalidState('RagSession is closed');
      };

      const queryBytes = (question: string, options: LlmOptions, topK: number) =>
        RAGQueryOptions.encode(
          RAGQueryOptions.fromPartial({
            query: question,
            generation: toRagGeneration(options),
            retrieval: { topK, scoreThreshold: config.scoreThreshold },
          })
        ).finish();

      const session: RagSession = {
        async ingest(document) {
          assertOpen();
          const docs = Array.isArray(document) ? document : [document];
          for (const doc of docs) {
            await deps.backend.ragIngest(handle, documentBytes(doc));
          }
        },
        async search(query, topK) {
          assertOpen();
          const bytes = await deps.backend.ragSearch(
            handle,
            RAGSearchRequest.encode(
              RAGSearchRequest.fromPartial({
                query,
                retrieval: { topK: topK ?? defaultTopK, scoreThreshold: config.scoreThreshold },
              })
            ).finish()
          );
          const response = RAGSearchResponse.decode(bytes);
          if (response.error) {
            throw SDKException.fromProto(response.error);
          }
          return response.chunks.map(toMatch);
        },
        async query(question, options = {}) {
          assertOpen();
          const bytes = await deps.backend.ragQuery(
            handle,
            // Retrieval depth is a session-config knob; LlmOptions.topK is the
            // sampling top-k and must not be mistaken for it.
            queryBytes(question, options, defaultTopK)
          );
          const raw = RAGResult.decode(bytes);
          if (raw.error) {
            throw SDKException.fromProto(raw.error);
          }
          return toRagResult(raw, newRequestId('rag'), llmId || embeddingId);
        },
        queryStream(question, options = {}) {
          assertOpen();
          const requestId = newRequestId('rag');
          return bridgeStream<RagEvent>(
            async (sink) => {
              await deps.backend.ragQueryStream(
                handle,
                queryBytes(question, options, defaultTopK),
                (eventBytes) => {
                  const event = RAGStreamEvent.decode(eventBytes);
                  switch (event.kind) {
                    case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_TOKEN:
                      sink.push({ type: 'token', text: event.token, kind: TokenKind.TEXT });
                      break;
                    case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED:
                      // Commons no longer emits a separate mid-stream retrieval-progress
                      // signal (CHUNK_RETRIEVED/CONTEXT_READY were collapsed away) — the
                      // terminal COMPLETED event carries the full result, including
                      // retrievedChunks, in one shot. Derive 'retrieved' from it so
                      // existing consumers still see a sources-before-answer event.
                      if (event.result) {
                        sink.push({
                          type: 'retrieved',
                          matches: event.result.retrievedChunks.map(toMatch),
                        });
                        sink.push({
                          type: 'completed',
                          result: toRagResult(event.result, requestId, llmId || embeddingId),
                        });
                      }
                      break;
                    case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR:
                      sink.fail(
                        event.error
                          ? SDKException.fromProto(event.error)
                          : SDKException.generationFailed('rag stream failed')
                      );
                      break;
                    default:
                      break;
                  }
                }
              );
            },
            () => deps.backend.ragCancel(handle)
          );
        },
        async stats() {
          assertOpen();
          const raw = RAGStatistics.decode(await deps.backend.ragStats(handle));
          return {
            documentCount: raw.indexedDocuments,
            chunkCount: raw.indexedChunks,
            indexSizeBytes: raw.vectorStoreSizeBytes,
          };
        },
        async clear() {
          assertOpen();
          await deps.backend.ragClear(handle);
        },
        async close() {
          if (closed) return;
          closed = true;
          await deps.backend.ragClose(handle);
        },
      };
      return session;
    },
  };
}
