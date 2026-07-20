/**
 * RunAnywhere+RAG.ts
 *
 * Public RAG facade. Browser I/O (file picking, IndexedDB/OPFS persistence)
 * stays in Web adapters; chunking/retrieval/prompt assembly belong in the
 * commons native RAG session when exports are present. CrossWasm IndexedDB
 * orchestration is a fallback only when the native session ABI is missing.
 */

import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import {
  EmbeddingsProtoAdapter,
  RAGProtoAdapter,
} from '../../Adapters/ModalityProtoAdapter.js';
import type {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGSearchResult,
  RAGStatistics,
  RAGStreamEvent,
} from '@runanywhere/proto-ts/rag';
import type { EmbeddingVector } from '@runanywhere/proto-ts/embeddings_options';
import {
  rAGConfigurationDefaults,
  rAGQueryOptionsDefaults,
} from '@runanywhere/proto-ts/convenience/rag_convenience';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { getBackendWorkerOwner } from '../../runtime/BackendWorkerModelOwnership.js';
import {
  getModuleForModel,
  getWasmModuleRecord,
  getWasmModuleRecordForCapability,
} from '../../runtime/EmscriptenModule.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';
import { ModelRegistry } from './RunAnywhere+ModelRegistry.js';
import {
  Embeddings,
  embeddingCosineSimilarity,
} from './RunAnywhere+Embeddings.js';
import { TextGeneration } from './RunAnywhere+TextGeneration.js';

const logger = new SDKLogger('RAG');
const NATIVE_RAG_PERSISTENCE_UNAVAILABLE =
  'Persistent Web RAG indexes require a provider with a browser storage-backed index adapter. The current native Web RAG session ABI is in-memory only.';

export interface RAGDocumentSummary {
  id: string;
  name: string;
  chunkCount: number;
}

export type RAGQueryOverrides = Partial<Omit<RAGQueryOptions, 'question'>>;

export interface RAGProviderCapabilities {
  native: boolean;
  persistent: boolean;
  documentListing: boolean;
  documentRemoval: boolean;
}

export interface RAGProvider {
  readonly providerKind?: 'custom' | 'cross-wasm' | 'wasm-session';
  ragCreatePipeline(config: RAGConfiguration): Promise<void>;
  ragDestroyPipeline(): Promise<void>;
  ragIngest(text: string, metadataJson?: string): Promise<void>;
  /** Ingest a generated-proto document. Optional — providers without
   * document-level ingest fall back to `ragIngest(text, metadataJson)`.
   * Mirrors Swift `ragIngest(_ document:)` (RunAnywhere+RAG.swift:92). */
  ragIngestDocument?(document: RAGDocument): Promise<RAGStatistics>;
  ragAddDocumentsBatch?(documents: Array<{ text: string; metadataJson?: string }>): Promise<void>;
  ragQuery(question: string, options?: RAGQueryOverrides): Promise<RAGResult>;
  /** Streaming query — emits a RAGStreamEvent per token, then COMPLETED/ERROR.
   * Optional so providers without a streaming path stay compatible. */
  ragQueryStream?(question: string, options?: RAGQueryOverrides): AsyncIterable<RAGStreamEvent>;
  ragClearDocuments(): Promise<void>;
  ragGetDocumentCount(): Promise<number>;
  ragGetStatistics?(): Promise<RAGStatistics>;
  ragListDocuments?(): Promise<RAGDocumentSummary[]>;
  ragRemoveDocument?(id: string): Promise<void>;
  ragGetCapabilities?(): RAGProviderCapabilities;
}

export type RAGAvailabilitySource =
  | 'provider'
  | 'cross-wasm'
  | 'wasm-session'
  | 'wasm-exports'
  | 'unavailable';

export interface RAGAvailability {
  available: boolean;
  source: RAGAvailabilitySource;
  reason: string;
  missingExports: string[];
}

/**
 * Identity of the facade-owned active RAG pipeline. The generation changes on
 * every successful create, destroy, or provider replacement—even when the
 * model ids are unchanged—so mounted Web views can detect global provider
 * replacement without inspecting backend-private state.
 */
export interface RAGPipelineState {
  generation: number;
  configuration: RAGConfiguration | null;
}

export interface RAGNativeProviderOptions {
  adapter?: RAGProtoAdapter;
  session?: number;
  config?: Partial<RAGConfiguration>;
}

let _provider: RAGProvider | null = null;
let _pipelineGeneration = 0;
let _pipelineConfiguration: RAGConfiguration | null = null;

function advancePipelineState(configuration: RAGConfiguration | null): void {
  _pipelineGeneration += 1;
  _pipelineConfiguration = configuration ? { ...configuration } : null;
}

export function getRAGPipelineState(): RAGPipelineState {
  return {
    generation: _pipelineGeneration,
    configuration: _pipelineConfiguration ? { ..._pipelineConfiguration } : null,
  };
}

export function setRAGProvider(provider: RAGProvider | null): void {
  _provider = provider;
  advancePipelineState(null);
}

/**
 * Explicit backend-registration hook for Web RAG providers. Split WASM
 * backends call this after claiming their capabilities; it never runs as an
 * implicit side effect of a RAG API call.
 */
export function registerRAGProvider(provider?: RAGProvider): boolean {
  // Prefer the commons native RAG session when exports are present (Swift /
  // Kotlin parity). Fall back to the IndexedDB-backed CrossWasm provider only
  // when the native session ABI is unavailable in this WASM build.
  let resolved = provider ?? null;
  const nativeAvailable = RAGProtoAdapter.tryDefault()?.supportsProtoRAG() ?? false;
  if (!resolved) {
    const nativeAdapter = RAGProtoAdapter.tryDefault();
    if (nativeAdapter?.supportsProtoRAG()) {
      try {
        resolved = createRAGNativeProvider({ adapter: nativeAdapter });
      } catch {
        resolved = null;
      }
    }
  }
  // A build with the native session ABI must not silently replace commons
  // retrieval with the browser-only CrossWasm composition. Apps that need it
  // can explicitly call registerPersistentRAGProvider() as a degraded path.
  if (!resolved && !nativeAvailable && supportsCrossWasmRAG()) {
    logger.warning('Native RAG ABI is unavailable; using degraded CrossWasm RAG provider.');
    resolved = createPersistentRAGProvider();
  }
  if (!resolved) return false;
  setRAGProvider(resolved);
  return true;
}

/** Install a browser-storage-backed cross-WASM RAG provider. */
export function registerPersistentRAGProvider(): boolean {
  if (_provider || !supportsCrossWasmRAG()) return false;
  setRAGProvider(createPersistentRAGProvider());
  return true;
}

/** Core-lifecycle cleanup for shutdown paths where a provider destroy fails. */
export function resetRAGFacadeState(): void {
  const hadState = _provider !== null || _pipelineConfiguration !== null;
  _provider = null;
  if (hadState) advancePipelineState(null);
}

export function createRAGNativeProvider(
  options: RAGNativeProviderOptions = {},
): RAGProvider {
  if (options.session != null) assertNativeHandle(options.session, 'RAG.nativeProvider');
  const adapter = options.adapter ?? RAGProtoAdapter.tryDefault();
  if (!adapter) {
    throw SDKException.backendNotAvailable(
      'RAG.nativeProvider',
      'No backend is registered for the RAG capability. Call LlamaCPP.register() (or another RAG-providing backend) before creating a native RAG provider.',
    );
  }
  if (!adapter.supportsProtoRAG()) {
    throw SDKException.backendNotAvailable(
      'RAG.nativeProvider',
      `Native RAG exports are missing: ${adapter.missingRAGExports().join(', ')}.`,
    );
  }
  return new NativeRAGSessionProvider(adapter, options);
}

export function setRAGSessionHandle(
  session: number,
  adapter?: RAGProtoAdapter,
): void {
  assertNativeHandle(session, 'RAG.setSessionHandle');
  _provider = createRAGNativeProvider({ adapter, session });
  advancePipelineState(null);
}

function evictUnavailableCrossWasmProvider(): void {
  const provider = _provider;
  if (provider?.providerKind !== 'cross-wasm' || supportsCrossWasmRAG()) return;

  _provider = null;
  advancePipelineState(null);
  void provider.ragDestroyPipeline().catch((error: unknown) => {
    logger.warning(
      `Stale cross-WASM RAG cleanup failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  });
}

function activeProvider(): RAGProvider | null {
  evictUnavailableCrossWasmProvider();
  return _provider;
}

export function getRAGAvailability(): RAGAvailability {
  const provider = activeProvider();
  if (provider) {
    const source = provider.providerKind === 'wasm-session'
      ? 'wasm-session'
      : provider.providerKind === 'cross-wasm'
        ? 'cross-wasm'
        : 'provider';
    return {
      available: true,
      source,
      reason: source === 'wasm-session'
        ? 'Native RAG session provider registered.'
        : source === 'cross-wasm'
          ? 'Web cross-WASM embeddings, retrieval, and LLM provider registered.'
        : 'RAG provider registered.',
      missingExports: [],
    };
  }

  if (supportsCrossWasmRAG()) {
    return {
      available: false,
      source: 'wasm-exports',
      reason: 'Web cross-WASM embeddings and LLM backends are registered, but no RAG pipeline has been created.',
      missingExports: [],
    };
  }

  const adapter = RAGProtoAdapter.tryDefault();
  if (!adapter) {
    return {
      available: false,
      source: 'unavailable',
      reason: 'No RAG provider or native RAG session handle is registered, and no Web WASM module is active.',
      missingExports: [],
    };
  }

  const missingExports = adapter.missingRAGExports();
  if (missingExports.length > 0) {
    return {
      available: false,
      source: 'unavailable',
      reason: 'RAG is unavailable in this Web WASM build. Native RAG exports are missing, likely because RAC_BACKEND_RAG=OFF.',
      missingExports,
    };
  }

  return {
    available: false,
    source: 'wasm-exports',
    reason: 'Native RAG proto exports are present, but no RAG provider or session handle is registered.',
    missingExports: [],
  };
}

export function isRAGAvailable(): boolean {
  return getRAGAvailability().available;
}

function requireProvider(feature = 'RAG'): RAGProvider {
  const provider = activeProvider();
  if (provider) return provider;
  const availability = getRAGAvailability();
  throw SDKException.backendNotAvailable(
    feature,
    `${availability.reason}${availability.missingExports.length > 0
      ? ` Missing exports: ${availability.missingExports.join(', ')}.`
      : ''}`,
  );
}

class NativeRAGSessionProvider implements RAGProvider {
  readonly providerKind = 'wasm-session' as const;
  private session: number | null = null;
  private config: RAGConfiguration;

  constructor(
    private readonly adapter: RAGProtoAdapter,
    options: RAGNativeProviderOptions = {},
  ) {
    this.session = options.session != null
      ? assertNativeHandle(options.session, 'RAG.nativeProvider')
      : null;
    if (options.config?.persistIndex) {
      throw SDKException.backendNotAvailable(
        'RAG.nativeProvider',
        NATIVE_RAG_PERSISTENCE_UNAVAILABLE,
      );
    }
    this.config = createDefaultRAGConfiguration(options.config);
  }

  async ragCreatePipeline(config: RAGConfiguration): Promise<void> {
    if (config.persistIndex) {
      throw SDKException.backendNotAvailable(
        'RAG.createPipeline',
        NATIVE_RAG_PERSISTENCE_UNAVAILABLE,
      );
    }
    validateNativeRAGConfiguration(config, 'RAG.createPipeline');
    if (this.session != null) {
      await this.adapter.destroySession(this.session);
      this.session = null;
    }
    const session = await this.adapter.createSession(config);
    if (session == null) {
      throw SDKException.backendNotAvailable(
        'RAG.createPipeline',
        'Native RAG session creation returned no handle.',
      );
    }
    this.session = session;
    this.config = { ...config };
  }

  async ragDestroyPipeline(): Promise<void> {
    if (this.session != null) {
      await this.adapter.destroySession(this.session);
      this.session = null;
    }
  }

  async ragIngest(text: string, metadataJson?: string): Promise<void> {
    // Mirrors Swift's text overload delegating to the document overload
    // (RunAnywhere+RAG.swift:86-88).
    await this.ragIngestDocument(makeRAGDocument(text, metadataJson));
  }

  async ragIngestDocument(document: RAGDocument): Promise<RAGStatistics> {
    const session = await this.ensureSession();
    const stats = await this.adapter.ingest(session, document);
    if (!stats) {
      throw SDKException.backendNotAvailable(
        'RAG.ingest',
        'Native RAG ingest returned no statistics.',
      );
    }
    return stats;
  }

  async ragAddDocumentsBatch(documents: Array<{ text: string; metadataJson?: string }>): Promise<void> {
    for (const document of documents) {
      await this.ragIngest(document.text, document.metadataJson);
    }
  }

  async ragQuery(
    question: string,
    options: RAGQueryOverrides = {},
  ): Promise<RAGResult> {
    const session = await this.ensureSession();
    // Swift parity: RAG verbs throw on misconfiguration/failure — no
    // synthetic error-shaped results.
    if (!this.config.llmModelId.trim()) {
      throw SDKException.fromCode(
        -ProtoErrorCode.ERROR_CODE_INVALID_INPUT,
        'Native Web RAG query requires RAGConfiguration.llmModelId',
        'A session without an LLM model id can ingest but cannot generate answers.',
      );
    }
    const result = await this.adapter.query(session, makeRAGQuery(question, this.config, options));
    if (!result) {
      throw SDKException.backendNotAvailable(
        'RAG.query',
        'Native RAG query returned no result.',
      );
    }
    return result;
  }

  async *ragQueryStream(
    question: string,
    options: RAGQueryOverrides = {},
  ): AsyncIterable<RAGStreamEvent> {
    const session = await this.ensureSession();
    if (!this.config.llmModelId.trim()) {
      throw SDKException.fromCode(
        -ProtoErrorCode.ERROR_CODE_INVALID_INPUT,
        'Native Web RAG query requires RAGConfiguration.llmModelId',
        'A session without an LLM model id can ingest but cannot generate answers.',
      );
    }
    yield* this.adapter.queryStream(session, makeRAGQuery(question, this.config, options));
  }

  async ragClearDocuments(): Promise<void> {
    const session = await this.ensureSession();
    const stats = await this.adapter.clear(session);
    if (!stats) {
      throw SDKException.backendNotAvailable(
        'RAG.clearDocuments',
        'Native RAG clear returned no statistics.',
      );
    }
  }

  async ragGetDocumentCount(): Promise<number> {
    // Swift parity: RunAnywhere+RAG.swift reports indexedChunks.
    return (await this.statistics()).indexedChunks;
  }

  async ragGetStatistics(): Promise<RAGStatistics> {
    return this.statistics();
  }

  ragGetCapabilities(): RAGProviderCapabilities {
    return {
      native: true,
      persistent: false,
      documentListing: false,
      documentRemoval: false,
    };
  }

  private async ensureSession(): Promise<number> {
    if (this.session != null) return this.session;
    validateNativeRAGConfiguration(this.config, 'RAG.session');
    await this.ragCreatePipeline(this.config);
    return this.session!;
  }

  private async statistics(): Promise<RAGStatistics> {
    // Swift parity: failures throw — no synthetic error-shaped statistics.
    if (this.session == null) {
      if (this.config.persistIndex) {
        throw SDKException.backendNotAvailable(
          'RAG.statistics',
          NATIVE_RAG_PERSISTENCE_UNAVAILABLE,
        );
      }
      return emptyRAGStatistics(this.config);
    }
    const stats = await this.adapter.statistics(this.session);
    if (!stats) {
      throw SDKException.backendNotAvailable(
        'RAG.statistics',
        'Native RAG statistics returned no result.',
      );
    }
    return stats;
  }
}

interface CrossWasmRAGChunk {
  id: string;
  documentId: string;
  documentName: string;
  text: string;
  metadata: Record<string, string>;
  vector: EmbeddingVector;
  startOffset: number;
  endOffset: number;
  tokenCount: number;
}

interface CrossWasmRAGDocument {
  id: string;
  name: string;
  chunkCount: number;
}

interface PersistentRAGSnapshot {
  config: RAGConfiguration;
  chunks: CrossWasmRAGChunk[];
  documents: Array<[string, CrossWasmRAGDocument]>;
  lastUpdatedMs: number;
  lastQueryMs: number;
}

const memoryPersistentRAGStore = new Map<string, PersistentRAGSnapshot>();

async function readPersistentRAGSnapshot(key: string): Promise<PersistentRAGSnapshot | null> {
  if (typeof indexedDB === 'undefined') return memoryPersistentRAGStore.get(key) ?? null;
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('runanywhere-rag', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('indexes');
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const transaction = request.result.transaction('indexes', 'readonly');
      const get = transaction.objectStore('indexes').get(key);
      get.onsuccess = () => resolve((get.result as PersistentRAGSnapshot | undefined) ?? null);
      get.onerror = () => reject(get.error);
    };
  });
}

async function writePersistentRAGSnapshot(key: string, snapshot: PersistentRAGSnapshot): Promise<void> {
  if (typeof indexedDB === 'undefined') {
    memoryPersistentRAGStore.set(key, snapshot);
    return;
  }
  await new Promise<void>((resolve, reject) => {
    const request = indexedDB.open('runanywhere-rag', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('indexes');
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const transaction = request.result.transaction('indexes', 'readwrite');
      transaction.objectStore('indexes').put(snapshot, key);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    };
  });
}

async function deletePersistentRAGSnapshot(key: string): Promise<void> {
  if (typeof indexedDB === 'undefined') {
    memoryPersistentRAGStore.delete(key);
    return;
  }
  await new Promise<void>((resolve, reject) => {
    const request = indexedDB.open('runanywhere-rag', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('indexes');
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const transaction = request.result.transaction('indexes', 'readwrite');
      transaction.objectStore('indexes').delete(key);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    };
  });
}

/**
 * Browser provider for the split-WASM release architecture.
 *
 * The ONNX module owns MiniLM embeddings while the llama.cpp module owns text
 * generation. A C++ RAG session is private to one Emscripten heap and cannot
 * resolve service handles registered in its sibling module. Keep the public
 * RAG contract intact by owning the in-memory vector index here and routing
 * each primitive to its canonical backend facade.
 */
class CrossWasmRAGProvider implements RAGProvider {
  readonly providerKind = 'cross-wasm' as const;

  protected config: RAGConfiguration = createDefaultRAGConfiguration();
  protected initialized = false;
  protected chunks: CrossWasmRAGChunk[] = [];
  protected documents = new Map<string, CrossWasmRAGDocument>();
  protected lastUpdatedMs = 0;
  protected lastQueryMs = 0;
  protected lifecycleVersion = 0;

  async ragCreatePipeline(config: RAGConfiguration): Promise<void> {
    validateNativeRAGConfiguration(config, 'RAG.createPipeline');
    if (!config.llmModelId.trim()) {
      throw SDKException.backendNotAvailable(
        'RAG.createPipeline',
        'The cross-WASM Web RAG provider requires RAGConfiguration.llmModelId.',
      );
    }
    if (!supportsCrossWasmRAG()) {
      throw SDKException.backendNotAvailable(
        'RAG.createPipeline',
        'The cross-WASM Web RAG provider requires registered ONNX embeddings and llama.cpp text generation backends.',
      );
    }

    // Direct configuration callers (including rag.ensureReady) receive the
    // same lifecycle guarantees as the two-model-id convenience overload.
    await loadRagArtifactModel(
      config.embeddingModelId,
      ModelCategory.MODEL_CATEGORY_EMBEDDING,
      'Embedding',
    );
    await loadRagArtifactModel(
      config.llmModelId,
      ModelCategory.MODEL_CATEGORY_LANGUAGE,
      'LLM',
    );

    this.lifecycleVersion += 1;
    this.config = { ...createDefaultRAGConfiguration(), ...config };
    this.chunks = [];
    this.documents.clear();
    this.lastUpdatedMs = Date.now();
    this.lastQueryMs = 0;
    this.initialized = true;
  }

  async ragDestroyPipeline(): Promise<void> {
    this.lifecycleVersion += 1;
    this.initialized = false;
    this.chunks = [];
    this.documents.clear();
    this.lastUpdatedMs = Date.now();
    this.lastQueryMs = 0;
  }

  async ragIngest(text: string, metadataJson?: string): Promise<void> {
    await this.ragIngestDocument(makeRAGDocument(text, metadataJson));
  }

  async ragIngestDocument(document: RAGDocument): Promise<RAGStatistics> {
    this.requireInitialized('RAG.ingest');
    const version = this.lifecycleVersion;
    const normalized = normalizeCrossWasmDocument(document);
    const textChunks = splitRAGText(
      normalized.text,
      this.config.chunkSize ?? 512,
      this.config.chunkOverlap ?? 64,
    );
    if (textChunks.length === 0) {
      throw SDKException.fromCode(
        -ProtoErrorCode.ERROR_CODE_INVALID_INPUT,
        'RAG document text is empty.',
        'RAG.ingest',
      );
    }

    const result = await Embeddings.embedBatch({
      texts: textChunks.map((chunk) => chunk.text),
      requestId: '',
      modelId: this.config.embeddingModelId,
      metadata: {},
    }, this.config.embeddingModelId);
    this.assertCurrent(version, 'RAG.ingest');
    if (result.vectors.length !== textChunks.length) {
      throw SDKException.backendNotAvailable(
        'RAG.ingest',
        `Embedding backend returned ${result.vectors.length} vectors for ${textChunks.length} chunks.`,
      );
    }

    this.removeDocumentInternal(normalized.id);
    const nextChunks = textChunks.map((chunk, index): CrossWasmRAGChunk => ({
      id: `${normalized.id}:chunk-${index}`,
      documentId: normalized.id,
      documentName: normalized.name,
      text: chunk.text,
      metadata: {
        ...normalized.metadata,
        docId: normalized.id,
        docName: normalized.name,
      },
      vector: result.vectors[index]!,
      startOffset: chunk.startOffset,
      endOffset: chunk.endOffset,
      tokenCount: chunk.tokenCount,
    }));
    this.chunks.push(...nextChunks);
    this.documents.set(normalized.id, {
      id: normalized.id,
      name: normalized.name,
      chunkCount: nextChunks.length,
    });
    this.lastUpdatedMs = Date.now();
    return this.statistics();
  }

  async ragAddDocumentsBatch(
    documents: Array<{ text: string; metadataJson?: string }>,
  ): Promise<void> {
    for (const document of documents) {
      await this.ragIngest(document.text, document.metadataJson);
    }
  }

  async ragQuery(
    question: string,
    options: RAGQueryOverrides = {},
  ): Promise<RAGResult> {
    this.requireInitialized('RAG.query');
    const version = this.lifecycleVersion;
    const query = question.trim();
    if (!query) {
      throw SDKException.fromCode(
        -ProtoErrorCode.ERROR_CODE_INVALID_INPUT,
        'RAG query question is empty.',
        'RAG.query',
      );
    }

    const totalStarted = nowMs();
    const retrievalStarted = nowMs();
    const queryEmbedding = await Embeddings.embed(
      query,
      this.config.embeddingModelId,
    );
    this.assertCurrent(version, 'RAG.query');
    const queryVector = queryEmbedding.vectors[0];
    if (!queryVector) {
      throw SDKException.backendNotAvailable(
        'RAG.query',
        'Embedding backend returned no query vector.',
      );
    }

    const queryOptions = makeRAGQuery(query, this.config, options);
    const minimumSimilarity = queryOptions.similarityThreshold ?? 0;
    const requestedTopK = queryOptions.retrievalTopK || this.config.topK || 5;
    const ranked = this.chunks
      .map((chunk) => ({
        chunk,
        score: embeddingCosineSimilarity(queryVector, chunk.vector),
      }))
      .filter(({ score }) => score >= minimumSimilarity)
      .sort((a, b) => b.score - a.score)
      .slice(0, Math.max(1, requestedTopK));
    const retrievalTimeMs = nowMs() - retrievalStarted;

    const retrievedChunks: RAGSearchResult[] = ranked.map(({ chunk, score }, index) => ({
      chunkId: chunk.id,
      text: chunk.text,
      similarityScore: score,
      sourceDocument: chunk.documentName,
      metadata: { ...chunk.metadata },
      rank: index + 1,
      startOffset: chunk.startOffset,
      endOffset: chunk.endOffset,
      tokenCount: chunk.tokenCount,
    }));
    if (retrievedChunks.length === 0) {
      const totalTimeMs = nowMs() - totalStarted;
      this.lastQueryMs = Date.now();
      return {
        answer: '',
        retrievedChunks: [],
        contextUsed: '',
        retrievalTimeMs,
        generationTimeMs: 0,
        totalTimeMs,
        promptTokens: 0,
        completionTokens: 0,
        totalTokens: 0,
        errorCode: 0,
        requestId: createId('rag-query'),
      };
    }

    const context = boundedRAGContext(
      retrievedChunks,
      this.config.maxContextTokens ?? 4096,
    );
    const prompt = renderRAGPrompt(
      this.config.promptTemplate,
      context,
      query,
    );

    // Acceleration changes replace the entire llama.cpp Emscripten module.
    // The TypeScript-owned vector index remains valid, but its configured LLM
    // no longer exists in the new module's lifecycle heap. Re-establish that
    // dependency immediately before generation without recreating (and
    // clearing) the RAG pipeline.
    const currentLlm = WebModelLifecycle.currentModel({
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      includeModelMetadata: false,
    });
    if (!currentLlm?.found || currentLlm.modelId !== this.config.llmModelId) {
      await loadRagArtifactModel(
        this.config.llmModelId,
        ModelCategory.MODEL_CATEGORY_LANGUAGE,
        'LLM',
      );
      this.assertCurrent(version, 'RAG.query');
    }

    const generationStarted = nowMs();
    const generated = await TextGeneration.generate({
      prompt,
      systemPrompt: queryOptions.systemPrompt
        ?? 'Answer the question using only the supplied context. If the context does not contain the answer, say so.',
      maxTokens: queryOptions.maxTokens,
      temperature: queryOptions.temperature,
      topP: queryOptions.topP,
      topK: queryOptions.topK,
      disableThinking: queryOptions.disableThinking,
      conversationId: 'web-cross-wasm-rag',
    });
    this.assertCurrent(version, 'RAG.query');
    const generationTimeMs = nowMs() - generationStarted;
    const totalTimeMs = nowMs() - totalStarted;
    this.lastQueryMs = Date.now();
    return {
      answer: generated.text,
      retrievedChunks,
      contextUsed: context,
      retrievalTimeMs,
      generationTimeMs,
      totalTimeMs,
      promptTokens: generated.inputTokens,
      completionTokens: generated.tokensGenerated,
      totalTokens: generated.inputTokens + generated.tokensGenerated,
      errorCode: 0,
      requestId: createId('rag-query'),
      thinkingContent: generated.thinkingContent,
    };
  }

  async ragClearDocuments(): Promise<void> {
    this.requireInitialized('RAG.clearDocuments');
    this.chunks = [];
    this.documents.clear();
    this.lastUpdatedMs = Date.now();
  }

  async ragGetDocumentCount(): Promise<number> {
    return this.documents.size;
  }

  async ragGetStatistics(): Promise<RAGStatistics> {
    return this.statistics();
  }

  async ragListDocuments(): Promise<RAGDocumentSummary[]> {
    return [...this.documents.values()].map((document) => ({ ...document }));
  }

  async ragRemoveDocument(id: string): Promise<void> {
    this.requireInitialized('RAG.removeDocument');
    this.removeDocumentInternal(id);
    this.lastUpdatedMs = Date.now();
  }

  ragGetCapabilities(): RAGProviderCapabilities {
    return {
      native: false,
      persistent: false,
      documentListing: true,
      documentRemoval: true,
    };
  }

  protected statistics(): RAGStatistics {
    const totalTokensIndexed = this.chunks.reduce(
      (sum, chunk) => sum + chunk.tokenCount,
      0,
    );
    const vectorStoreSizeBytes = this.chunks.reduce(
      (sum, chunk) => sum + chunk.vector.values.length * Float32Array.BYTES_PER_ELEMENT,
      0,
    );
    return {
      indexedDocuments: this.documents.size,
      indexedChunks: this.chunks.length,
      totalTokensIndexed,
      lastUpdatedMs: this.lastUpdatedMs,
      indexPath: undefined,
      statsJson: JSON.stringify({ provider: 'cross-wasm', dimension: this.chunks[0]?.vector.dimension ?? 0 }),
      vectorStoreSizeBytes,
      isPersistent: false,
      lastQueryMs: this.lastQueryMs,
      errorMessage: undefined,
      errorCode: 0,
    };
  }

  protected removeDocumentInternal(id: string): void {
    this.documents.delete(id);
    this.chunks = this.chunks.filter((chunk) => chunk.documentId !== id);
  }

  protected requireInitialized(feature: string): void {
    if (!this.initialized) {
      throw SDKException.notInitialized(`${feature}: RAG pipeline is not ready`);
    }
  }

  protected assertCurrent(version: number, feature: string): void {
    if (!this.initialized || version !== this.lifecycleVersion) {
      throw SDKException.notInitialized(`${feature}: RAG pipeline stopped or restarted`);
    }
  }
}

/**
 * Cross-WASM RAG with a durable browser index. It persists chunks and embedding
 * vectors in IndexedDB (with a same-interface memory fallback for non-browser
 * test environments), while embeddings and generation remain backend-owned.
 */
class PersistentRAGProvider extends CrossWasmRAGProvider {
  private storageKey = '';

  async ragCreatePipeline(config: RAGConfiguration): Promise<void> {
    await super.ragCreatePipeline({ ...config, persistIndex: true });
    this.storageKey = config.indexPath || `default:${config.embeddingModelId}:${config.llmModelId}`;
    const snapshot = await readPersistentRAGSnapshot(this.storageKey);
    if (snapshot) {
      this.chunks = snapshot.chunks;
      this.documents = new Map(snapshot.documents);
      this.lastUpdatedMs = snapshot.lastUpdatedMs;
      this.lastQueryMs = snapshot.lastQueryMs;
      logger.info(`Restored persistent RAG index '${this.storageKey}'`);
    }
  }

  async ragIngestDocument(document: RAGDocument): Promise<RAGStatistics> {
    const result = await super.ragIngestDocument(document);
    await this.persist();
    return result;
  }

  async ragClearDocuments(): Promise<void> {
    await super.ragClearDocuments();
    await deletePersistentRAGSnapshot(this.storageKey);
  }

  async ragRemoveDocument(id: string): Promise<void> {
    await super.ragRemoveDocument(id);
    await this.persist();
  }

  ragGetCapabilities(): RAGProviderCapabilities {
    return {
      native: false,
      persistent: true,
      documentListing: true,
      documentRemoval: true,
    };
  }

  protected statistics(): RAGStatistics {
    return {
      ...super.statistics(),
      indexPath: this.storageKey || this.config.indexPath,
      isPersistent: true,
      statsJson: JSON.stringify({
        provider: 'persistent-cross-wasm',
        persistent: true,
        dimension: this.chunks[0]?.vector.dimension ?? 0,
      }),
    };
  }

  private async persist(): Promise<void> {
    if (!this.storageKey) return;
    await writePersistentRAGSnapshot(this.storageKey, {
      config: { ...this.config, persistIndex: true },
      chunks: this.chunks,
      documents: [...this.documents.entries()],
      lastUpdatedMs: this.lastUpdatedMs,
      lastQueryMs: this.lastQueryMs,
    });
  }
}

/** Create a provider whose ingested index survives a browser reload. */
export function createPersistentRAGProvider(): RAGProvider {
  return new PersistentRAGProvider();
}

function supportsCrossWasmRAG(): boolean {
  const embeddings = EmbeddingsProtoAdapter.tryDefault();
  return Boolean(embeddings?.supportsLifecycleProtoEmbeddings())
    && TextGeneration.supportsProtoLLM();
}

/**
 * Stable execution-site key for a loaded model. Native RAG can only resolve
 * artifacts that live on the same site as the RAG ABI host (one Emscripten
 * heap / BackendWorker). Keys are ownership-derived — never framework enums.
 */
function executionSiteForModel(modelId: string): string {
  const workerOwner = getBackendWorkerOwner(modelId);
  if (workerOwner) return `worker:${workerOwner}`;
  const module = getModuleForModel(modelId);
  if (module) {
    const record = getWasmModuleRecord(module);
    return `main:${record?.backend ?? 'unknown'}`;
  }
  return `unloaded:${modelId}`;
}

/**
 * Where `rac_rag_session_create_proto` will run for this embedding model.
 * Must stay aligned with `RAGProtoAdapter` worker routing.
 */
function executionSiteForNativeRagHost(embeddingModelId: string): string | null {
  if (getBackendWorkerOwner(embeddingModelId) === 'onnx') {
    return 'worker:onnx';
  }
  const ragRecord = getWasmModuleRecordForCapability('rag');
  if (!ragRecord) return null;
  return `main:${ragRecord.backend}`;
}

/**
 * Native session iff every artifact the session will load is co-located with
 * the RAG ABI host. Otherwise compose via public Embeddings + TextGeneration
 * facades (still worker-backed; no framework hardcoding).
 */
function resolveRagExecutionPlan(config: RAGConfiguration): {
  mode: 'native' | 'composed';
  reason: string;
} {
  const embId = config.embeddingModelId?.trim() ?? '';
  const llmId = config.llmModelId?.trim() ?? '';
  if (!embId) {
    return {
      mode: 'composed',
      reason: 'RAGConfiguration.embeddingModelId is required',
    };
  }

  const ragHost = executionSiteForNativeRagHost(embId);
  const embSite = executionSiteForModel(embId);
  const llmSite = llmId ? executionSiteForModel(llmId) : embSite;

  if (
    ragHost
    && embSite === ragHost
    && llmSite === ragHost
  ) {
    return {
      mode: 'native',
      reason: `all RAG artifacts co-located with RAG ABI host (${ragHost})`,
    };
  }

  return {
    mode: 'composed',
    reason: ragHost
      ? `RAG ABI host is ${ragHost}, but artifacts are at emb=${embSite}`
        + (llmId ? ` llm=${llmSite}` : '')
        + '; native session is single-heap'
      : 'No RAG ABI host is registered; composing via modality facades',
  };
}

/**
 * Install the provider that matches the ownership plan. Replaces a mismatched
 * wasm-session provider when the pipeline spans heaps.
 */
async function ensureProviderForExecutionPlan(
  config: RAGConfiguration,
): Promise<void> {
  const plan = resolveRagExecutionPlan(config);
  if (plan.mode === 'native') return;

  if (!supportsCrossWasmRAG()) {
    throw SDKException.backendNotAvailable(
      'RAG.createPipeline',
      `${plan.reason}. Composed RAG also unavailable (embeddings + LLM facades `
        + 'are not both registered).',
    );
  }

  const current = _provider;
  if (current?.providerKind === 'cross-wasm') return;
  if (current) {
    try {
      await current.ragDestroyPipeline();
    } catch {
      /* ignore teardown races while swapping providers */
    }
  }
  logger.info(`Using composed RAG provider — ${plan.reason}`);
  setRAGProvider(createPersistentRAGProvider());
}

interface NormalizedCrossWasmDocument {
  id: string;
  name: string;
  text: string;
  metadata: Record<string, string>;
}

function normalizeCrossWasmDocument(document: RAGDocument): NormalizedCrossWasmDocument {
  const id = document.id.trim() || createId('rag-doc');
  const name = document.metadata.docName
    || document.metadata.name
    || document.metadata.sourceDocument
    || document.sourceUri
    || 'Document';
  return {
    id,
    name,
    text: document.text.trim(),
    metadata: { ...document.metadata },
  };
}

interface SplitRAGChunk {
  text: string;
  startOffset: number;
  endOffset: number;
  tokenCount: number;
}

function splitRAGText(text: string, requestedSize: number, requestedOverlap: number): SplitRAGChunk[] {
  const matches = [...text.matchAll(/\S+/g)];
  if (matches.length === 0) return [];
  const size = Math.max(1, Math.floor(requestedSize));
  const overlap = Math.min(Math.max(0, Math.floor(requestedOverlap)), size - 1);
  const stride = Math.max(1, size - overlap);
  const chunks: SplitRAGChunk[] = [];
  for (let start = 0; start < matches.length; start += stride) {
    const end = Math.min(matches.length, start + size);
    const startOffset = matches[start]!.index ?? 0;
    const last = matches[end - 1]!;
    const endOffset = (last.index ?? 0) + last[0].length;
    chunks.push({
      text: text.slice(startOffset, endOffset),
      startOffset,
      endOffset,
      tokenCount: end - start,
    });
    if (end === matches.length) break;
  }
  return chunks;
}

function boundedRAGContext(chunks: RAGSearchResult[], requestedMaxTokens: number): string {
  const maxTokens = Math.max(1, Math.floor(requestedMaxTokens));
  const parts: string[] = [];
  let used = 0;
  for (const chunk of chunks) {
    const available = maxTokens - used;
    if (available <= 0) break;
    const words = chunk.text.split(/\s+/).filter(Boolean);
    const text = words.slice(0, available).join(' ');
    if (!text) continue;
    parts.push(`[Source ${chunk.rank}: ${chunk.sourceDocument ?? 'Document'}]\n${text}`);
    used += Math.min(words.length, available);
  }
  return parts.join('\n\n');
}

function renderRAGPrompt(template: string | undefined, context: string, query: string): string {
  const fallback = 'Use the context below to answer.\n\nContext:\n{context}\n\nQuestion: {query}';
  return (template?.trim() || fallback)
    .replaceAll('{{context}}', context)
    .replaceAll('{{query}}', query)
    .replaceAll('{context}', context)
    .replaceAll('{query}', query);
}

function nowMs(): number {
  return globalThis.performance?.now?.() ?? Date.now();
}

function assertNativeHandle(handle: number, feature: string): number {
  if (!Number.isFinite(handle) || handle <= 0) {
    throw SDKException.backendNotAvailable(
      feature,
      'A non-zero native RAG session handle is required.',
    );
  }
  return handle;
}

function validateNativeRAGConfiguration(config: RAGConfiguration, feature: string): void {
  if (!config.embeddingModelId.trim()) {
    throw SDKException.backendNotAvailable(
      feature,
      'Native Web RAG session creation requires RAGConfiguration.embeddingModelId or an explicit RAG.setSessionHandle(...).',
    );
  }
}

export function createDefaultRAGConfiguration(
  overrides: Partial<RAGConfiguration> = {},
): RAGConfiguration {
  // Seed with the proto-generated canonical defaults so Web matches Swift /
  // Kotlin / Flutter / RN parity (topK / similarityThreshold / chunkSize /
  // chunkOverlap from idl/rag.proto rac_default; embeddingDimension is left
  // unset so commons derives it from the loaded embedding model). Caller-supplied
  // overrides (including explicit 0 for chunkOverlap / similarityThreshold)
  // are honored end-to-end because RAGConfiguration numeric fields are proto3
  // `optional` — commons distinguishes "unset" from "explicit zero" via
  // `has_*()` in `build_backend_config` (rac_rag_proto_abi.cpp).
  return {
    ...rAGConfigurationDefaults(),
    ...overrides,
  };
}

function makeRAGQuery(
  question: string,
  config: RAGConfiguration,
  options: RAGQueryOverrides,
): RAGQueryOptions {
  // Seed with the proto-generated canonical defaults (maxTokens 512 /
  // temperature 0.7 / topP 1.0 from idl/rag.proto rac_default) so Web matches
  // Swift's `RARAGQueryOptions.defaults(question:)` (RAGProto+Helpers.swift:72).
  //
  // Per rag.proto: `retrievalTopK = 0` and `similarityThreshold = 0` mean
  // "use the RAGConfiguration default" so falling back to 0 when neither the
  // per-query override nor the pipeline config supplies a value is the
  // correct way to defer to commons.
  const defaults = rAGQueryOptionsDefaults();
  return {
    ...defaults,
    question,
    systemPrompt: options.systemPrompt,
    maxTokens: options.maxTokens ?? defaults.maxTokens,
    temperature: options.temperature ?? defaults.temperature,
    topP: options.topP ?? defaults.topP,
    topK: options.topK ?? defaults.topK,
    retrievalTopK: options.retrievalTopK ?? config.topK ?? 0,
    similarityThreshold: options.similarityThreshold ?? config.similarityThreshold ?? 0,
    stream: options.stream ?? false,
    // Structured flag — commons prepends the model's no-think directive.
    disableThinking: options.disableThinking ?? false,
    enableMultiQuery: options.enableMultiQuery ?? defaults.enableMultiQuery,
    multiQueryCount: options.multiQueryCount ?? defaults.multiQueryCount,
    scopePrefix: options.scopePrefix ?? defaults.scopePrefix,
  };
}

function makeRAGDocument(text: string, metadataJson?: string): RAGDocument {
  const parsed = parseMetadata(metadataJson);
  return {
    id: parsed.docId,
    text,
    metadata: parsed.metadata,
    sourceUri: parsed.sourceUri,
    adapterHandle: undefined,
    mediaType: parsed.mediaType,
    sizeBytes: parsed.sizeBytes,
  };
}

interface ParsedMetadata {
  docId: string;
  docName: string;
  sourceUri?: string;
  mediaType?: string;
  sizeBytes: number;
  metadata: Record<string, string>;
}

function createId(prefix: string): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Math.random().toString(36).slice(2)}`;
}

function parseMetadata(metadataJson?: string): ParsedMetadata {
  const metadata = parseMetadataJson(metadataJson);
  const docId = metadata.docId ?? metadata.id ?? createId('rag-doc');
  const docName = metadata.docName ?? metadata.name ?? metadata.sourceDocument ?? metadata.sourceUri ?? 'Document';
  const parsedSizeBytes = Number(metadata.sizeBytes ?? 0);
  return {
    docId,
    docName,
    sourceUri: metadata.sourceUri,
    mediaType: metadata.mediaType,
    sizeBytes: Number.isFinite(parsedSizeBytes) && parsedSizeBytes >= 0
      ? parsedSizeBytes
      : 0,
    metadata: {
      ...metadata,
      docId,
      docName,
    },
  };
}

function parseMetadataJson(metadataJson?: string): Record<string, string> {
  if (!metadataJson) return {};
  try {
    const parsed: unknown = JSON.parse(metadataJson);
    if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
      return { metadataJson };
    }
    const metadata: Record<string, string> = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (value != null) metadata[key] = String(value);
    }
    return metadata;
  } catch {
    return { metadataJson };
  }
}

function emptyRAGStatistics(config: RAGConfiguration): RAGStatistics {
  return {
    indexedDocuments: 0,
    indexedChunks: 0,
    totalTokensIndexed: 0,
    lastUpdatedMs: 0,
    indexPath: config.indexPath,
    statsJson: undefined,
    vectorStoreSizeBytes: 0,
    isPersistent: config.persistIndex,
    lastQueryMs: 0,
    errorMessage: undefined,
    errorCode: 0,
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Load one RAG artifact model through the commons lifecycle and surface a
 * Swift-shaped failure. Mirrors the private `loadRAGArtifactModel`
 * (RunAnywhere+RAG.swift:202-224): category falls back when the registry
 * entry leaves it unspecified, and failures throw
 * `"{label} model '{id}': {message}"` with MODEL_LOAD_FAILED.
 */
async function loadRagArtifactModel(
  modelId: string,
  fallbackCategory: ModelCategory,
  errorLabel: string,
): Promise<string> {
  const model = ModelRegistry.getModel(modelId);
  const category =
    model && model.category !== ModelCategory.MODEL_CATEGORY_UNSPECIFIED
      ? model.category
      : fallbackCategory;
  const result = await WebModelLifecycle.loadModelAsync({
    modelId,
    category,
    ...(model?.framework !== undefined ? { framework: model.framework } : {}),
    forceReload: false,
    validateAvailability: false,
  });
  if (!result?.success) {
    const message = result?.errorMessage
      || `${errorLabel} model lifecycle artifact resolution failed`;
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_MODEL_LOAD_FAILED,
      `${errorLabel} model '${modelId}': ${message}`,
    );
  }
  return result.modelId || modelId;
}

/**
 * Build a generated RAG configuration from registry models by using commons
 * lifecycle resolution for the embedding and LLM artifacts, then stamping the
 * lifecycle-resolved model ids onto the base configuration. Mirrors Swift
 * `ragResolvedConfiguration(embeddingModel:llmModel:baseConfiguration:)`
 * (RunAnywhere+RAG.swift:19-35 + RAGProto+Helpers.swift
 * `resolvingLifecycleArtifacts`).
 */
export async function ragResolvedConfiguration(
  embeddingModelId: string,
  llmModelId: string,
  baseConfiguration?: Partial<RAGConfiguration>,
): Promise<RAGConfiguration> {
  const embedding = await loadRagArtifactModel(
    embeddingModelId,
    ModelCategory.MODEL_CATEGORY_EMBEDDING,
    'Embedding',
  );
  const llm = await loadRagArtifactModel(
    llmModelId,
    ModelCategory.MODEL_CATEGORY_LANGUAGE,
    'LLM',
  );
  return createDefaultRAGConfiguration({
    ...baseConfiguration,
    embeddingModelId: embedding,
    llmModelId: llm,
  });
}

export async function ragCreatePipeline(config: RAGConfiguration): Promise<void>;
/**
 * Bootstrap overload: create the RAG pipeline from two registry model ids.
 * Mirrors Swift `ragCreatePipeline(embeddingModel:llmModel:baseConfiguration:)`
 * (RunAnywhere+RAG.swift:39-50): the configuration comes from
 * [ragResolvedConfiguration], so both artifacts are loaded through the
 * commons lifecycle (with lifecycle-resolved model ids) before the native
 * session create runs.
 */
export async function ragCreatePipeline(
  embeddingModelId: string,
  llmModelId: string,
  baseConfiguration?: Partial<RAGConfiguration>,
): Promise<void>;
export async function ragCreatePipeline(
  configOrEmbeddingModelId: RAGConfiguration | string,
  llmModelId?: string,
  baseConfiguration?: Partial<RAGConfiguration>,
): Promise<void> {
  const config = typeof configOrEmbeddingModelId === 'string'
    ? await ragResolvedConfiguration(
      configOrEmbeddingModelId,
      llmModelId ?? '',
      baseConfiguration,
    )
    : configOrEmbeddingModelId;
  await ensureProviderForExecutionPlan(config);
  const provider = activeProvider();
  if (provider) {
    await provider.ragCreatePipeline(config);
    advancePipelineState(config);
    logger.info('RAG pipeline created');
    return;
  }

  const adapter = RAGProtoAdapter.tryDefault();
  if (!adapter || !adapter.supportsProtoRAG()) {
    requireProvider('RAG.createPipeline');
    return;
  }

  const nativeProvider = new NativeRAGSessionProvider(adapter, { config });
  await nativeProvider.ragCreatePipeline(config);
  _provider = nativeProvider;
  advancePipelineState(config);
  logger.info('RAG pipeline created');
}

export async function ragDestroyPipeline(): Promise<void> {
  // Swift parity: `ragDestroyPipeline` is idempotent. When no provider has
  // been installed there is nothing to tear down, so resolve quietly rather
  // than throwing `backendNotAvailable`.
  const provider = activeProvider();
  if (!provider) return;
  await provider.ragDestroyPipeline();
  _provider = null;
  advancePipelineState(null);
  logger.info('RAG pipeline destroyed');
}

export async function ragIngest(text: string, metadataJson?: string): Promise<void>;
/**
 * Ingest a generated-proto document. Mirrors Swift's discardable-result
 * document overload (RunAnywhere+RAG.swift:91-100).
 */
export async function ragIngest(document: RAGDocument): Promise<RAGStatistics>;
export async function ragIngest(
  textOrDocument: string | RAGDocument,
  metadataJson?: string,
): Promise<void | RAGStatistics> {
  if (typeof textOrDocument === 'string') {
    await requireProvider('RAG.ingest').ragIngest(textOrDocument, metadataJson);
    return;
  }
  return ragIngestDocument(textOrDocument);
}

export async function ragIngestDocument(document: RAGDocument): Promise<RAGStatistics> {
  const p = requireProvider('RAG.ingest');
  if (p.ragIngestDocument) return p.ragIngestDocument(document);
  // Provider without document-level ingest: fall back to the text path and
  // report the post-ingest statistics snapshot.
  const metadataJson = document.metadata && Object.keys(document.metadata).length > 0
    ? JSON.stringify(document.metadata)
    : undefined;
  await p.ragIngest(document.text, metadataJson);
  return ragGetStatistics();
}

export async function ragAddDocumentsBatch(
  documents: Array<{ text: string; metadataJson?: string }>,
): Promise<void> {
  const p = requireProvider('RAG.addDocumentsBatch');
  if (p.ragAddDocumentsBatch) return p.ragAddDocumentsBatch(documents);
  for (const d of documents) await p.ragIngest(d.text, d.metadataJson);
}

export async function ragClearDocuments(): Promise<void> {
  await requireProvider('RAG.clearDocuments').ragClearDocuments();
}

export async function ragGetDocumentCount(): Promise<number> {
  return requireProvider('RAG.getDocumentCount').ragGetDocumentCount();
}

export async function ragQuery(
  question: string,
  options?: RAGQueryOverrides,
): Promise<RAGResult>;
/**
 * Full-options overload: query with a complete generated `RAGQueryOptions`
 * (question rides inside the options). Mirrors Swift
 * `ragQuery(_ options:)` (RunAnywhere+RAG.swift:190); the
 * question+optional-options variant (RunAnywhere+RAG.swift:181) maps onto
 * the `(question, overrides)` overload above.
 */
export async function ragQuery(options: RAGQueryOptions): Promise<RAGResult>;
export async function ragQuery(
  questionOrOptions: string | RAGQueryOptions,
  options?: RAGQueryOverrides,
): Promise<RAGResult> {
  // Swift parity (RunAnywhere+RAG.swift:190-196): throws `.notInitialized`
  // instead of returning a synthetic error-shaped result.
  if (typeof questionOrOptions === 'string') {
    return requireProvider('RAG.query').ragQuery(questionOrOptions, options);
  }
  const { question, ...overrides } = questionOrOptions;
  return requireProvider('RAG.query').ragQuery(question, overrides);
}

/**
 * Streaming RAG query. Emits a `RAGStreamEvent` per generated token
 * (kind = TOKEN) as the answer is produced, then a terminal COMPLETED event
 * carrying the full `RAGResult`, or an ERROR event. Mirrors Swift
 * `ragQueryStream` and the Kotlin `ragQueryStream` Flow.
 */
export function ragQueryStream(
  question: string,
  options?: RAGQueryOverrides,
): AsyncIterable<RAGStreamEvent>;
export function ragQueryStream(options: RAGQueryOptions): AsyncIterable<RAGStreamEvent>;
export function ragQueryStream(
  questionOrOptions: string | RAGQueryOptions,
  options?: RAGQueryOverrides,
): AsyncIterable<RAGStreamEvent> {
  const provider = requireProvider('RAG.queryStream');
  if (!provider.ragQueryStream) {
    throw SDKException.backendNotAvailable(
      'RAG.queryStream',
      'Streaming RAG is not available on this provider.',
    );
  }
  if (typeof questionOrOptions === 'string') {
    return provider.ragQueryStream(questionOrOptions, options);
  }
  const { question, ...overrides } = questionOrOptions;
  return provider.ragQueryStream(question, overrides);
}

// ---------------------------------------------------------------------------
// RAG proto helpers — Swift parity: RAGProto+Helpers.swift
// ---------------------------------------------------------------------------

/**
 * Generated defaults with a required question string. Question is excluded
 * from the proto annotation because it has no semantic default
 * (caller-supplied). Swift parity: `RARAGQueryOptions.defaults(question:)`
 * (RAGProto+Helpers.swift:72).
 */
export function ragQueryOptionsWithQuestion(question: string): RAGQueryOptions {
  return { ...rAGQueryOptionsDefaults(), question };
}

/**
 * Total end-to-end query time in seconds (from `totalTimeMs`).
 * Swift parity: `RARAGResult.totalTime` (RAGProto+Helpers.swift:82).
 */
export function ragResultTotalTime(result: RAGResult): number {
  return result.totalTimeMs / 1000;
}

/**
 * Last index update as a `Date`, or null when the index has never been
 * updated. Swift parity: `RARAGStatistics.lastUpdated` (RAGProto+Helpers.swift:88).
 */
export function ragStatisticsLastUpdated(statistics: RAGStatistics): Date | null {
  if (statistics.lastUpdatedMs <= 0) return null;
  return new Date(statistics.lastUpdatedMs);
}

export async function ragGetStatistics(): Promise<RAGStatistics> {
  // Swift parity (RunAnywhere+RAG.swift:142-150): throws `.notInitialized`
  // instead of returning a synthetic error-shaped result.
  const p = requireProvider('RAG.getStatistics');
  if (p.ragGetStatistics) return p.ragGetStatistics();
  const indexedDocuments = await p.ragGetDocumentCount();
  return {
    indexedDocuments,
    indexedChunks: indexedDocuments,
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
}

export async function ragListDocuments(): Promise<RAGDocumentSummary[]> {
  const p = requireProvider('RAG.listDocuments');
  if (providerCapabilities(p).documentListing && p.ragListDocuments) {
    return p.ragListDocuments();
  }
  throw SDKException.backendNotAvailable(
    'RAG.listDocuments',
    'The active RAG provider does not expose document listing. Use RAG.getStatistics() for aggregate counts until the native document-list API is available.',
  );
}

export async function ragRemoveDocument(id: string): Promise<void> {
  const p = requireProvider('RAG.removeDocument');
  if (providerCapabilities(p).documentRemoval && p.ragRemoveDocument) {
    await p.ragRemoveDocument(id);
    return;
  }
  throw SDKException.backendNotAvailable(
    'RAG.removeDocument',
    `The active RAG provider does not expose document-level removal for '${id}'.`,
  );
}

export function ragGetCapabilities(): RAGProviderCapabilities {
  return providerCapabilities(activeProvider());
}

function providerCapabilities(provider: RAGProvider | null): RAGProviderCapabilities {
  if (!provider) {
    return unavailableCapabilities();
  }

  const reported = provider.ragGetCapabilities?.();
  const hasDocumentListing = typeof provider.ragListDocuments === 'function';
  const hasDocumentRemoval = typeof provider.ragRemoveDocument === 'function';

  return {
    native: reported?.native ?? provider.providerKind === 'wasm-session',
    persistent: reported?.persistent ?? false,
    documentListing: (reported?.documentListing ?? hasDocumentListing) && hasDocumentListing,
    documentRemoval: (reported?.documentRemoval ?? hasDocumentRemoval) && hasDocumentRemoval,
  };
}

function unavailableCapabilities(): RAGProviderCapabilities {
  return {
    native: false,
    persistent: false,
    documentListing: false,
    documentRemoval: false,
  };
}

/**
 * Bootstrap options for `RunAnywhere.rag.ensureReady(...)`. When the RAG
 * proto exports are present but no session is registered yet (the
 * `wasm-exports` availability source), the SDK creates the native
 * session for the caller using the supplied embedding/LLM model ids
 * plus any other defaults.
 */
export interface RAGEnsureReadyOptions {
  embeddingModelId: string;
  llmModelId: string;
  config?: Partial<RAGConfiguration>;
}

/**
 * Ensure a RAG pipeline is live; idempotent. Absorbs the
 * `availability() + createPipeline(defaultConfiguration({...}))`
 * bootstrap step that example apps used to inline. Returns the final
 * availability snapshot so callers can decide whether to surface a
 * "RAG unavailable" placeholder (`source === 'unavailable'`) without
 * re-querying the availability oracle separately.
 *
 * Mirrors the lifecycle ownership pattern used by Swift's RAG facade —
 * app code never reaches into `defaultConfiguration` itself.
 */
export async function ragEnsureReady(
  options: RAGEnsureReadyOptions,
): Promise<RAGAvailability> {
  let availability = getRAGAvailability();
  if (availability.available) {
    return availability;
  }
  if (availability.source !== 'wasm-exports') {
    return availability;
  }
  try {
    await ragCreatePipeline(createDefaultRAGConfiguration({
      ...options.config,
      embeddingModelId: options.embeddingModelId,
      llmModelId: options.llmModelId,
    }));
  } catch (err) {
    logger.warning(
      `RAG.ensureReady() bootstrap failed: ${err instanceof Error ? err.message : String(err)}`,
    );
    throw err;
  }
  availability = getRAGAvailability();
  return availability;
}

/** Internal constructor used by focused split-WASM provider contract tests. */
export const __testing__ = {
  createCrossWasmRAGProvider: (): RAGProvider => new CrossWasmRAGProvider(),
  createPersistentRAGProvider: (): RAGProvider => new PersistentRAGProvider(),
  clearPersistentRAGStore: (): void => memoryPersistentRAGStore.clear(),
  resetFacadeState: resetRAGFacadeState,
  resolveRagExecutionPlan,
};

/**
 * Public `RunAnywhere.rag.*` namespace — Web-only extensions ONLY.
 *
 * The Swift source of truth (`RunAnywhere+RAG.swift`) has no `rag` namespace;
 * its flat verbs (`ragCreatePipeline`, `ragDestroyPipeline`, `ragIngest`,
 * `ragAddDocumentsBatch`, `ragQuery`, `ragClearDocuments`,
 * `ragGetDocumentCount`, `ragGetStatistics`) live directly on the
 * `RunAnywhere` facade (see RunAnywhere+FlatFacade.ts) and are the canonical
 * cross-SDK surface. Every member below is a Web-platform extension that does
 * not appear in Swift — provider registration is the Web plugin pattern
 * (backend packages install providers at register() time, where Swift links
 * CppBridge statically), and availability probing exists because Web WASM
 * backends register asynchronously after `initialize()`.
 */
export const RAG = {
  /** @webOnly Provider wiring entry point. Backend packages call this during register(). */
  setProvider: setRAGProvider,
  /** @webOnly Construct a native (WASM-session-backed) RAG provider. */
  createNativeProvider: createRAGNativeProvider,
  /** @webOnly Construct an IndexedDB-backed cross-WASM provider. */
  createPersistentProvider: createPersistentRAGProvider,
  /** @webOnly Install the default IndexedDB-backed cross-WASM provider. */
  registerPersistentProvider: registerPersistentRAGProvider,
  /** @webOnly Install a pre-existing native RAG session handle as the active provider. */
  setSessionHandle: setRAGSessionHandle,
  /** @webOnly Inspect provider/availability without throwing. */
  availability: getRAGAvailability,
  /** @webOnly Identify the exact active pipeline across global provider replacement. */
  pipelineState: getRAGPipelineState,
  /** @webOnly Convenience boolean for availability checks. */
  isAvailable: isRAGAvailable,
  /** @webOnly Inspect the active provider's declared capabilities (listing/removal/persistence). */
  capabilities: ragGetCapabilities,
  /** @webOnly Build a default `RAGConfiguration` with sensible field defaults. */
  defaultConfiguration: createDefaultRAGConfiguration,
  /** @webOnly Idempotent "create-if-missing" bootstrap used by Web example apps. */
  ensureReady: ragEnsureReady,
  /** @webOnly Document-level listing — pending the cross-SDK native list API. */
  listDocuments: ragListDocuments,
  /** @webOnly Document-level removal — pending the cross-SDK native remove API. */
  removeDocument: ragRemoveDocument,
};

export type { RAGSearchResult };
