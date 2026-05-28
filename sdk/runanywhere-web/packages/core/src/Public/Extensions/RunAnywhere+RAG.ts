/**
 * RunAnywhere+RAG.ts
 *
 * Public RAG facade. Web views own browser file picking/reading; native or
 * registered providers own session, ingestion, retrieval, and generation via
 * generated proto request/result models.
 */

import { SDKErrorCode, SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { RAGProtoAdapter } from '../../Adapters/ModalityProtoAdapter';
import type {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  RAGResult,
  RAGSearchResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';
import { rAGConfigurationDefaults } from '@runanywhere/proto-ts/convenience/rag_convenience';

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
  readonly providerKind?: 'custom' | 'wasm-session';
  ragCreatePipeline(config: RAGConfiguration): Promise<void>;
  ragDestroyPipeline(): Promise<void>;
  ragIngest(text: string, metadataJson?: string): Promise<void>;
  ragAddDocumentsBatch?(documents: Array<{ text: string; metadataJson?: string }>): Promise<void>;
  ragQuery(question: string, options?: RAGQueryOverrides): Promise<RAGResult>;
  ragClearDocuments(): Promise<void>;
  ragGetDocumentCount(): Promise<number>;
  ragGetStatistics?(): Promise<RAGStatistics>;
  ragListDocuments?(): Promise<RAGDocumentSummary[]>;
  ragRemoveDocument?(id: string): Promise<void>;
  ragGetCapabilities?(): RAGProviderCapabilities;
}

export type RAGAvailabilitySource =
  | 'provider'
  | 'wasm-session'
  | 'wasm-exports'
  | 'unavailable';

export interface RAGAvailability {
  available: boolean;
  source: RAGAvailabilitySource;
  reason: string;
  missingExports: string[];
}

export interface RAGNativeProviderOptions {
  adapter?: RAGProtoAdapter;
  session?: number;
  config?: Partial<RAGConfiguration>;
}

let _provider: RAGProvider | null = null;

export function setRAGProvider(provider: RAGProvider | null): void {
  _provider = provider;
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
}

function activeProvider(): RAGProvider | null {
  return _provider;
}

export function getRAGAvailability(): RAGAvailability {
  if (_provider) {
    return {
      available: true,
      source: _provider.providerKind === 'wasm-session' ? 'wasm-session' : 'provider',
      reason: _provider.providerKind === 'wasm-session'
        ? 'Native RAG session provider registered.'
        : 'RAG provider registered.',
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
    validateNativeRAGConfiguration(config, 'RAG.createPipeline');
    if (this.session != null) {
      this.adapter.destroySession(this.session);
      this.session = null;
    }
    const session = this.adapter.createSession(config);
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
      this.adapter.destroySession(this.session);
      this.session = null;
    }
  }

  async ragIngest(text: string, metadataJson?: string): Promise<void> {
    const session = await this.ensureSession();
    const stats = this.adapter.ingest(session, makeRAGDocument(text, metadataJson));
    if (!stats) {
      throw SDKException.backendNotAvailable(
        'RAG.ingest',
        'Native RAG ingest returned no statistics.',
      );
    }
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
    if (!this.config.llmModelId.trim()) {
      return unavailableRAGResult(
        question,
        'Native Web RAG query requires RAGConfiguration.llmModelId. A session without an LLM model id can ingest but cannot generate answers.',
      );
    }
    const result = this.adapter.query(session, makeRAGQuery(question, this.config, options));
    return result ?? unavailableRAGResult(
      question,
      'Native RAG query returned no result.',
    );
  }

  async ragClearDocuments(): Promise<void> {
    const session = await this.ensureSession();
    const stats = this.adapter.clear(session);
    if (!stats) {
      throw SDKException.backendNotAvailable(
        'RAG.clearDocuments',
        'Native RAG clear returned no statistics.',
      );
    }
  }

  async ragGetDocumentCount(): Promise<number> {
    return (await this.statistics()).indexedDocuments;
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
    if (this.session == null) {
      if (this.config.persistIndex) {
        return unavailableRAGStatistics(NATIVE_RAG_PERSISTENCE_UNAVAILABLE);
      }
      return emptyRAGStatistics(this.config);
    }
    return this.adapter.statistics(this.session) ?? unavailableRAGStatistics(
      'Native RAG statistics returned no result.',
    );
  }
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
  if (config.persistIndex) {
    throw SDKException.backendNotAvailable(
      feature,
      NATIVE_RAG_PERSISTENCE_UNAVAILABLE,
    );
  }
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
  // Kotlin / Flutter / RN parity (embeddingDimension=384, topK=5,
  // similarityThreshold=0.7, chunkSize=512, chunkOverlap=64). Caller-supplied
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
  // Per rag.proto: `retrievalTopK = 0` and `similarityThreshold = 0` mean
  // "use the RAGConfiguration default" so falling back to 0 when neither the
  // per-query override nor the pipeline config supplies a value is the
  // correct way to defer to commons.
  return {
    question,
    systemPrompt: options.systemPrompt,
    maxTokens: options.maxTokens ?? 512,
    temperature: options.temperature ?? 0.4,
    topP: options.topP ?? 1,
    topK: options.topK ?? 0,
    retrievalTopK: options.retrievalTopK ?? config.topK ?? 0,
    similarityThreshold: options.similarityThreshold ?? config.similarityThreshold ?? 0,
    stream: options.stream ?? false,
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

function parseMetadata(metadataJson?: string): ParsedMetadata {
  const metadata = parseMetadataJson(metadataJson);
  const docId = metadata.docId ?? metadata.id ?? createId('rag-doc');
  const docName = metadata.docName ?? metadata.name ?? metadata.sourceDocument ?? metadata.sourceUri ?? 'Document';
  return {
    docId,
    docName,
    sourceUri: metadata.sourceUri,
    mediaType: metadata.mediaType,
    sizeBytes: Number(metadata.sizeBytes ?? 0),
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
    const parsed = JSON.parse(metadataJson) as Record<string, unknown>;
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

export function unavailableRAGStatistics(reason?: string): RAGStatistics {
  return {
    ...emptyRAGStatistics(createDefaultRAGConfiguration()),
    errorMessage: reason ?? getRAGAvailability().reason,
    errorCode: SDKErrorCode.BackendNotAvailable,
  };
}

export function unavailableRAGResult(question = '', reason?: string): RAGResult {
  return {
    answer: '',
    retrievedChunks: [],
    contextUsed: '',
    retrievalTimeMs: 0,
    generationTimeMs: 0,
    totalTimeMs: 0,
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    errorMessage: reason ?? getRAGAvailability().reason,
    errorCode: SDKErrorCode.BackendNotAvailable,
    requestId: createId(question ? 'rag-query-unavailable' : 'rag-unavailable'),
  };
}

function createId(prefix: string): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Math.random().toString(36).slice(2)}`;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export async function ragCreatePipeline(config: RAGConfiguration): Promise<void> {
  const provider = activeProvider();
  if (provider) {
    await provider.ragCreatePipeline(config);
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
  logger.info('RAG pipeline destroyed');
}

export async function ragIngest(text: string, metadataJson?: string): Promise<void> {
  await requireProvider('RAG.ingest').ragIngest(text, metadataJson);
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
): Promise<RAGResult> {
  const provider = activeProvider();
  if (!provider) return unavailableRAGResult(question);
  return provider.ragQuery(question, options);
}

export async function ragGetStatistics(): Promise<RAGStatistics> {
  const p = activeProvider();
  if (!p) return unavailableRAGStatistics();
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

/**
 * Public `RunAnywhere.rag.*` namespace. Members marked `@webOnly` are
 * Web-platform extensions that do not appear in the Swift source-of-truth
 * (`RunAnywhere+RAG.swift`). They live here until either the cross-SDK
 * spec adopts them (Kotlin / Flutter / RN / Swift) or the consumer surface
 * migrates to the Swift-aligned subset. See CLUSTER-44 / web-core-011.
 *
 * Swift-aligned surface (cross-SDK canonical):
 *   - `createPipeline`     ↔ `ragCreatePipeline`
 *   - `destroyPipeline`    ↔ `ragDestroyPipeline`
 *   - `ingest`             ↔ `ragIngest`
 *   - `addDocumentsBatch`  ↔ `ragAddDocumentsBatch`
 *   - `query`              ↔ `ragQuery`
 *   - `clearDocuments`     ↔ `ragClearDocuments`
 *   - `getDocumentCount`   ↔ `ragGetDocumentCount`
 *   - `getStatistics`      ↔ `ragGetStatistics`
 */
export const RAG = {
  /** @webOnly Provider wiring entry point. Backend packages call this during register(). */
  setProvider: setRAGProvider,
  /** @webOnly Construct a native (WASM-session-backed) RAG provider. */
  createNativeProvider: createRAGNativeProvider,
  /** @webOnly Install a pre-existing native RAG session handle as the active provider. */
  setSessionHandle: setRAGSessionHandle,
  /** @webOnly Inspect provider/availability without throwing. */
  availability: getRAGAvailability,
  /** @webOnly Convenience boolean for availability checks. */
  isAvailable: isRAGAvailable,
  /** @webOnly Inspect the active provider's declared capabilities (listing/removal/persistence). */
  capabilities: ragGetCapabilities,
  /** @webOnly Build a default `RAGConfiguration` with sensible field defaults. */
  defaultConfiguration: createDefaultRAGConfiguration,
  createPipeline: ragCreatePipeline,
  destroyPipeline: ragDestroyPipeline,
  /** @webOnly Idempotent "create-if-missing" bootstrap used by Web example apps. */
  ensureReady: ragEnsureReady,
  ingest: ragIngest,
  addDocumentsBatch: ragAddDocumentsBatch,
  query: ragQuery,
  clearDocuments: ragClearDocuments,
  getDocumentCount: ragGetDocumentCount,
  getStatistics: ragGetStatistics,
  /** @webOnly Document-level listing — pending the cross-SDK native list API. */
  listDocuments: ragListDocuments,
  /** @webOnly Document-level removal — pending the cross-SDK native remove API. */
  removeDocument: ragRemoveDocument,
};

export type { RAGSearchResult };
