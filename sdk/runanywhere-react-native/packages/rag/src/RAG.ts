/**
 * RAG.ts
 *
 * High-level TypeScript API for RunAnywhere RAG (Retrieval-Augmented Generation)
 */

import { getNitroModulesProxySync, initializeNitroModulesGlobally } from '@runanywhere/core';
import type { RunAnywhereRAG as IRunAnywhereRAG, RAGConfig, RAGQuery, RAGResult, RAGChunk, RAGStatistics } from './specs/RunAnywhereRAG.nitro';

/**
 * Get the cached NitroModules proxy (after global initialization).
 */
function getNitroModulesProxy(): any {
  return getNitroModulesProxySync();
}

export type {
  RAGConfig,
  RAGQuery,
  RAGResult,
  RAGChunk,
  RAGStatistics,
} from './specs/RunAnywhereRAG.nitro';

/**
 * Document to be added to the knowledge base
 */
export interface Document {
  /** Document text content */
  text: string;
  /** Optional metadata (will be serialized to JSON) */
  metadata?: Record<string, any>;
}

/**
 * High-level RAG class with convenience methods
 */
export class RAG {
  private _native: IRunAnywhereRAG;
  private _isInitialized: boolean = false;

  constructor() {
    console.log('[RAG] Constructor started');
    
    // Get the NitroModules proxy (should already be initialized by caller)
    console.log('[RAG] Getting NitroModules proxy...');
    const NitroProxy = getNitroModulesProxy();
    console.log('[RAG] NitroProxy result:', NitroProxy ? 'Available' : 'NULL');
    
    if (!NitroProxy) {
      const error = new Error(
        'NitroModules is not available. ' +
        'Make sure to call initializeNitroModulesGlobally() before creating RAG instance.\n' +
        'Example: await initializeNitroModulesGlobally(); then createRAG();'
      );
      console.error('[RAG] Error - NitroProxy not available:', error);
      throw error;
    }
    
    console.log('[RAG] NitroProxy available, checking for createHybridObject method...');
    console.log('[RAG] NitroProxy type:', typeof NitroProxy);
    console.log('[RAG] NitroProxy.createHybridObject:', typeof NitroProxy.createHybridObject);
    
    try {
      console.log('[RAG] Attempting to create hybrid object "RunAnywhereRAG"...');
      this._native = NitroProxy.createHybridObject('RunAnywhereRAG') as IRunAnywhereRAG;
      console.log('[RAG] Successfully created RunAnywhereRAG hybrid object:', this._native);
    } catch (err) {
      console.error('[RAG] Failed to create RunAnywhereRAG hybrid object:', err);
      console.error('[RAG] Error message:', err instanceof Error ? err.message : String(err));
      console.error('[RAG] Error stack:', err instanceof Error ? err.stack : 'No stack');
      throw new Error(
        'Failed to create RunAnywhereRAG hybrid object: ' + 
        (err instanceof Error ? err.message : String(err)) + 
        '. Make sure RAG native module is properly built: npm run nitrogen'
      );
    }
  }

  /**
   * Static method to ensure Nitro is initialized before creating RAG instances.
   * Call this once on app startup if needed.
   */
  static async ensureInitialized(): Promise<void> {
    await initializeNitroModulesGlobally();
  }

  /**
   * Initialize the RAG pipeline
   *
   * @param config Pipeline configuration
   */
  async initialize(config: RAGConfig): Promise<void> {
    if (this._isInitialized) {
      throw new Error('RAG pipeline already initialized. Call destroy() first.');
    }

    await this._native.createPipeline(config);
    this._isInitialized = true;
  }

  /**
   * Check if pipeline is initialized
   */
  get isInitialized(): boolean {
    return this._isInitialized;
  }

  /**
   * Add a single document to the knowledge base
   *
   * @param document Document with text and optional metadata
   */
  async addDocument(document: Document): Promise<void> {
    this.ensureInitialized();

    const metadataJson = document.metadata
      ? JSON.stringify(document.metadata)
      : undefined;

    await this._native.addDocument(document.text, metadataJson);
  }

  /**
   * Add multiple documents in batch
   *
   * @param documents Array of documents
   */
  async addDocuments(documents: Document[]): Promise<void> {
    this.ensureInitialized();

    const texts = documents.map((d) => d.text);
    const metadataArray = documents.map((d) =>
      d.metadata ? JSON.stringify(d.metadata) : '{}'
    );

    await this._native.addDocumentsBatch(texts, metadataArray);
  }

  /**
   * Query the RAG pipeline with a question
   *
   * @param question User question
   * @param options Optional query parameters
   * @returns RAG result with answer and sources
   */
  async query(
    question: string,
    options?: Partial<Omit<RAGQuery, 'question'>>
  ): Promise<RAGResult> {
    this.ensureInitialized();

    const query: RAGQuery = {
      question,
      ...options,
    };

    const result = await this._native.query(query);

    // Parse metadata JSON in chunks
    if (result.retrievedChunks) {
      for (const chunk of result.retrievedChunks) {
        if (chunk.metadataJson) {
          try {
            (chunk as any).metadata = JSON.parse(chunk.metadataJson);
          } catch (e) {
            // Keep as JSON string if parsing fails
          }
        }
      }
    }

    return result;
  }

  /**
   * Clear all documents from the knowledge base
   */
  async clearDocuments(): Promise<void> {
    this.ensureInitialized();
    await this._native.clearDocuments();
  }

  /**
   * Get the number of documents in the knowledge base
   */
  async getDocumentCount(): Promise<number> {
    this.ensureInitialized();
    return await this._native.getDocumentCount();
  }

  /**
   * Get RAG statistics
   */
  async getStatistics(): Promise<RAGStatistics> {
    this.ensureInitialized();
    return await this._native.getStatistics();
  }

  /**
   * Destroy the pipeline and free resources
   */
  async destroy(): Promise<void> {
    if (!this._isInitialized) {
      return;
    }

    await this._native.destroyPipeline();
    this._isInitialized = false;
  }

  private ensureInitialized(): void {
    if (!this._isInitialized) {
      throw new Error('RAG pipeline not initialized. Call initialize() first.');
    }
  }
}

/**
 * Create a new RAG instance
 */
export function createRAG(): RAG {
  console.log('[RAG] createRAG() called');
  try {
    const instance = new RAG();
    console.log('[RAG] createRAG() succeeded, returning instance');
    return instance;
  } catch (err) {
    console.error('[RAG] createRAG() failed:', err);
    throw err;
  }
}

/**
 * Default prompt template for RAG
 */
export const DEFAULT_PROMPT_TEMPLATE = `You are a helpful AI assistant. Answer the question based on the provided context.

Context:
{context}

Question: {query}

Answer:`;

/**
 * Helper to create RAG config with defaults
 */
export function createRAGConfig(
  embeddingModelPath: string,
  llmModelPath: string,
  overrides?: Partial<RAGConfig>
): RAGConfig {
  return {
    embeddingModelPath,
    llmModelPath,
    embeddingDimension: 384,
    topK: 3,
    similarityThreshold: 0.7,
    maxContextTokens: 2048,
    chunkSize: 512,
    chunkOverlap: 50,
    promptTemplate: DEFAULT_PROMPT_TEMPLATE,
    ...overrides,
  };
}
