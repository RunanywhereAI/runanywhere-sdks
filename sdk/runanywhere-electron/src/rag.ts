// rag.ts — the public, ergonomic RAG surface. `RagSession` wraps the low-level
// proto-byte bridge (window.runanywhere.rag*) so callers work with plain objects:
// create a session over an embedding model (+ optional LLM), ingest documents,
// then ask grounded questions. Proto encode/decode lives in the preload bridge.

/** Configuration for a RAG session. Only `embeddingModelId` is required. */
export interface RagConfig {
  /** Registered/downloaded embedding model id (e.g. "minilm"). Required. */
  embeddingModelId: string;
  /** LLM id used to synthesize grounded answers. Omit for retrieval-only. */
  llmModelId?: string;
  /** Default number of chunks to retrieve per query. */
  topK?: number;
  /** Chunking: characters per chunk. */
  chunkSize?: number;
  /** Chunking: overlap (characters) between adjacent chunks. */
  chunkOverlap?: number;
  /** Cap on retrieved context tokens fed to the LLM. */
  maxContextTokens?: number;
  /** Minimum cosine similarity for a chunk to be retrieved (0–1). */
  similarityThreshold?: number;
  /** Prompt template override (uses "{context}" / "{question}" placeholders). */
  promptTemplate?: string;
  /** Persist the vector index to disk (default in-memory). */
  persistIndex?: boolean;
  /** On-disk index path when `persistIndex` is set. */
  indexPath?: string;
}

/** A document to ingest. `text` is chunked + embedded. */
export interface RagDoc {
  text: string;
  id?: string;
  metadata?: Record<string, string>;
  sourceUri?: string;
}

/** Per-query overrides. `question` is required. */
export interface RagQuery {
  question: string;
  systemPrompt?: string;
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  /** Retrieval count for this query (overrides the session default). */
  retrievalTopK?: number;
  similarityThreshold?: number;
}

/** A retrieved chunk used as grounding context. */
export interface RagChunk {
  chunkId: string;
  text: string;
  similarityScore: number;
  sourceDocument?: string;
}

/** The grounded answer plus its supporting chunks + timings. */
export interface RagResult {
  answer: string;
  retrievedChunks: RagChunk[];
  contextUsed: string;
  retrievalTimeMs: number;
  generationTimeMs: number;
  totalTimeMs: number;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  thinkingContent?: string;
  errorMessage?: string;
  errorCode: number;
}

/** Index statistics. */
export interface RagStats {
  indexedDocuments: number;
  indexedChunks: number;
  totalTokensIndexed: number;
  lastUpdatedMs: number;
  indexPath?: string;
}

/** The low-level bridge surface a RagSession drives (window.runanywhere). */
export interface RagBridge {
  ragCreateSession(config: RagConfig): Promise<number>;
  ragIngest(handle: number, doc: RagDoc): Promise<RagStats>;
  ragQuery(handle: number, query: RagQuery): Promise<RagResult>;
  ragStats(handle: number): Promise<RagStats>;
  ragClear(handle: number): Promise<RagStats>;
  ragDestroySession(handle: number): Promise<void>;
}

/**
 * A live RAG session. Create with {@link RagSession.create}, ingest documents,
 * query, then {@link close} to release the native session.
 */
export class RagSession {
  private closed = false;
  private constructor(private readonly bridge: RagBridge, readonly handle: number) {}

  /** Create a session over the given embedding model (+ optional LLM). */
  static async create(bridge: RagBridge, config: RagConfig): Promise<RagSession> {
    if (!config || !config.embeddingModelId) throw new Error('RagSession.create: embeddingModelId is required');
    const handle = await bridge.ragCreateSession(config);
    return new RagSession(bridge, handle);
  }

  /** Ingest one document (a string, or a {@link RagDoc}); returns index stats. */
  async ingest(doc: string | RagDoc): Promise<RagStats> {
    this.assertOpen();
    return this.bridge.ragIngest(this.handle, typeof doc === 'string' ? { text: doc } : doc);
  }

  /** Ingest several documents in order; returns the final index stats. */
  async ingestMany(docs: Array<string | RagDoc>): Promise<RagStats> {
    let stats: RagStats | undefined;
    for (const d of docs) stats = await this.ingest(d);
    return stats ?? this.stats();
  }

  /** Ask a grounded question (a string, or a {@link RagQuery}). */
  async query(query: string | RagQuery): Promise<RagResult> {
    this.assertOpen();
    return this.bridge.ragQuery(this.handle, typeof query === 'string' ? { question: query } : query);
  }

  /** Current index statistics. */
  async stats(): Promise<RagStats> {
    this.assertOpen();
    return this.bridge.ragStats(this.handle);
  }

  /** Drop all indexed documents (keeps the session). */
  async clear(): Promise<RagStats> {
    this.assertOpen();
    return this.bridge.ragClear(this.handle);
  }

  /** Destroy the native session. Idempotent. */
  async close(): Promise<void> {
    if (this.closed) return;
    this.closed = true;
    await this.bridge.ragDestroySession(this.handle);
  }

  private assertOpen(): void {
    if (this.closed) throw new Error('RagSession is closed');
  }
}
