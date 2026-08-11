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
} from '@runanywhere/proto-ts/rag';
import type { RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import { DataAbi, toEmbeddingsRequest, toRerankRequest } from './data-abi';
import { RAC_CATEGORY, RAC_FRAMEWORK } from './native-backend';
import { RAG_DEFAULTS, toNativeEmbedOptions } from './options';
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

/** Sync commons vector math exported by runanywhere_native.node (data_bridge.cpp). */
interface EmbeddingsMathNative {
  embeddingsNorm(vector: Float32Array): number;
  embeddingsSimilarity(lhs: Float32Array, rhs: Float32Array): number;
}

let embeddingsMathInjected: EmbeddingsMathNative | null = null;

/** Test hook — unit tests inject a fake so they do not need the .node. */
export function setEmbeddingsMathNativeForTests(native: EmbeddingsMathNative | null): void {
  embeddingsMathInjected = native;
}

function embeddingsMathNative(): EmbeddingsMathNative {
  if (embeddingsMathInjected) return embeddingsMathInjected;
  // Lazy require: bridge.ts throws at import when the .node is missing.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { addon } = require('../bridge') as { addon: EmbeddingsMathNative };
  return addon;
}

function asFloat32Vector(input: Embedding | Float32Array, fieldPath: string): Float32Array {
  if (input instanceof Float32Array) return input;
  if (input?.vector instanceof Float32Array) return input.vector;
  throw SDKException.validationFailed({
    fieldPath,
    message: 'expected Embedding or Float32Array',
  });
}

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
  /**
   * Cosine similarity via commons (`rac_embeddings_similarity`). Returns 0 for
   * mismatched lengths, empty vectors, or zero norms.
   */
  cosineSimilarity(a: Embedding | Float32Array, b: Embedding | Float32Array): number;
  /** L2 norm via commons (`rac_embeddings_norm`). */
  computeNorm(vector: Embedding | Float32Array): number;
}

/** Build the `embeddings` namespace over a backend. */
export function createEmbeddingsNamespace(deps: DataDeps): EmbeddingsNamespace {
  const data = new DataAbi(deps.backend);
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
      // Commons resolves the resident embeddings model itself; a missing one
      // comes back as a typed error from the call rather than a slot lookup.
      const result = await data.embed(toEmbeddingsRequest(texts, options));
      // `input_index` is set on every entry including zero, so the batch order
      // is commons' rather than something reconstructed from array position.
      return result.vectors.map((v) => ({
        index: v.inputIndex,
        vector: Float32Array.from(v.values),
      }));
    },
    cosineSimilarity(a, b) {
      const lhs = asFloat32Vector(a, 'a');
      const rhs = asFloat32Vector(b, 'b');
      return embeddingsMathNative().embeddingsSimilarity(lhs, rhs);
    },
    computeNorm(vector) {
      const values = asFloat32Vector(vector, 'vector');
      if (!values.length) return 0;
      return embeddingsMathNative().embeddingsNorm(values);
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
  const data = new DataAbi(deps.backend);
  return {
    async rerank(query, documents, topN) {
      deps.requireReady();
      if (!documents?.length) return [];
      const loaded = await deps.backend.loaded('rerank');
      if (!loaded) {
        throw SDKException.invalidState('no rerank model is loaded — call models.load() first');
      }
      // RerankResult.items is already sorted best-first and truncated to
      // top_n, so the SDK-side re-sort by rank is gone.
      const result = await data.rerank(toRerankRequest(query, documents, topN));
      return result.items.map((i) => ({
        index: i.index,
        relevanceScore: i.relevanceScore,
      }));
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
  return {
    answer: raw.answer,
    sources: raw.retrievedChunks.map(toMatch),
    thinkingText: raw.thinkingContent || undefined,
    inputTokens: raw.usage?.inputTokens ?? 0,
    outputTokens: raw.usage?.outputTokens ?? 0,
    // TokenUsage from the LLM leg of the RAG pipeline — never retrieve-time or
    // a local outputTokens/generationMs rate.
    timeToFirstTokenMs: raw.usage?.ttftMs ?? 0,
    tokensPerSecond: raw.usage?.decodeTokensPerSecond ?? 0,
    requestId: raw.requestId || requestId,
    model,
  };
}

// Only the sampling knobs commons' RAG pipeline reads; tools and structured output
// are not part of a grounded-answer request. An unset knob stays absent so
// commons applies its own `rac_default`, the same contract the LLM path uses.
function toRagGeneration(options: LlmOptions = {}): {
  maxOutputTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  systemPrompt?: string;
} {
  const out: {
    maxOutputTokens?: number;
    temperature?: number;
    topP?: number;
    topK?: number;
    systemPrompt?: string;
  } = {};
  if (options.maxOutputTokens !== undefined) out.maxOutputTokens = options.maxOutputTokens;
  if (options.temperature !== undefined) out.temperature = options.temperature;
  if (options.topP !== undefined) out.topP = options.topP;
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
          scoreThreshold: config.similarityThreshold,
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
            retrieval: { topK, scoreThreshold: config.similarityThreshold },
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
                retrieval: { topK: topK ?? defaultTopK, scoreThreshold: config.similarityThreshold },
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
