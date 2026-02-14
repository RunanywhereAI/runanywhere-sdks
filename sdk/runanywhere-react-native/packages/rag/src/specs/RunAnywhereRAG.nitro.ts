/**
 * RunAnywhereRAG.nitro.ts
 *
 * Nitrogen spec for RunAnywhere RAG (Retrieval-Augmented Generation) backend.
 * This defines the TypeScript/C++ interface that Nitrogen will generate bindings for.
 *
 * RAG Pipeline:
 * 1. Add documents (chunked and embedded automatically)
 * 2. Query with natural language
 * 3. Retrieve relevant chunks
 * 4. Generate contextual answer
 */

import type { HybridObject } from 'react-native-nitro-modules';

/**
 * RAG Configuration
 */
export interface RAGConfig {
  /** Path to embedding model (ONNX) */
  embeddingModelPath: string;

  /** Path to LLM model (ONNX format, e.g., TinyLlama) */
  llmModelPath: string;

  /** Embedding dimension (default 384) */
  embeddingDimension?: number;

  /** Number of chunks to retrieve (default 3) */
  topK?: number;

  /** Minimum similarity threshold 0-1 (default 0.7) */
  similarityThreshold?: number;

  /** Max context tokens (default 2048) */
  maxContextTokens?: number;

  /** Tokens per chunk (default 512) */
  chunkSize?: number;

  /** Overlap between chunks (default 50) */
  chunkOverlap?: number;

  /** Prompt template with {context} and {query} */
  promptTemplate?: string;

  /** Optional embedding model config JSON */
  embeddingConfigJson?: string;

  /** Optional LLM model config JSON */
  llmConfigJson?: string;
}

/**
 * Query parameters
 */
export interface RAGQuery {
  /** User question */
  question: string;

  /** Optional system prompt override */
  systemPrompt?: string;

  /** Max tokens to generate (default 512) */
  maxTokens?: number;

  /** Temperature (default 0.7) */
  temperature?: number;

  /** Top-p sampling (default 0.9) */
  topP?: number;

  /** Top-k sampling (default 40) */
  topK?: number;
}

/**
 * Retrieved chunk
 */
export interface RAGChunk {
  /** Chunk ID */
  chunkId: string;

  /** Chunk text */
  text?: string;

  /** Similarity score 0-1 */
  similarityScore: number;

  /** Optional metadata JSON */
  metadataJson?: string;
}

/**
 * Query result
 */
export interface RAGResult {
  /** Generated answer */
  answer: string;

  /** Retrieved chunks */
  retrievedChunks: RAGChunk[];

  /** Context sent to LLM */
  contextUsed?: string;

  /** Retrieval time in ms */
  retrievalTimeMs: number;

  /** Generation time in ms */
  generationTimeMs: number;

  /** Total time in ms */
  totalTimeMs: number;
}

/**
 * Statistics
 */
export interface RAGStatistics {
  /** Total documents */
  documentCount: number;

  /** Total chunks */
  chunkCount: number;

  /** Vector store size */
  vectorStoreSize: number;

  /** Additional stats JSON */
  statsJson: string;
}

/**
 * RunAnywhereRAG - Native RAG Pipeline Interface
 *
 * Nitrogen HybridObject exposing RAG C API to JavaScript/TypeScript.
 */
export interface RunAnywhereRAG extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Create RAG pipeline
   *
   * @param config Pipeline configuration
   * @returns Promise resolving to success
   */
  createPipeline(config: RAGConfig): Promise<boolean>;

  /**
   * Add document to knowledge base
   *
   * @param documentText Document content
   * @param metadataJson Optional metadata as JSON string
   * @returns Promise resolving to success
   */
  addDocument(documentText: string, metadataJson?: string): Promise<boolean>;

  /**
   * Add multiple documents in batch
   *
   * @param documents Array of document texts
   * @param metadataArray Optional array of metadata JSON strings
   * @returns Promise resolving to success
   */
  addDocumentsBatch(documents: string[], metadataArray?: string[]): Promise<boolean>;

  /**
   * Query the RAG pipeline
   *
   * @param query Query parameters
   * @returns Promise resolving to RAG result
   */
  query(query: RAGQuery): Promise<RAGResult>;

  /**
   * Clear all documents
   *
   * @returns Promise resolving to success
   */
  clearDocuments(): Promise<boolean>;

  /**
   * Get document count
   *
   * @returns Promise resolving to document count
   */
  getDocumentCount(): Promise<number>;

  /**
   * Get statistics
   *
   * @returns Promise resolving to statistics
   */
  getStatistics(): Promise<RAGStatistics>;

  /**
   * Destroy pipeline and free resources
   *
   * @returns Promise resolving to success
   */
  destroyPipeline(): Promise<boolean>;
}
