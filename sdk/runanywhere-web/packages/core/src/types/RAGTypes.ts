/**
 * RAGTypes.ts
 *
 * Type definitions for RAG (Retrieval-Augmented Generation) pipelines.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RAGTypes.swift
 */

export interface RAGConfiguration {
  /** Path to the embedding model (ONNX) */
  embeddingModelPath: string;
  /** Path to the LLM model (GGUF) */
  llmModelPath: string;
  /** Embedding vector dimension (default: 384) */
  embeddingDimension?: number;
  /** Number of top chunks to retrieve per query (default: 3) */
  topK?: number;
  /** Minimum cosine similarity threshold 0.0-1.0 (default: 0.12) */
  similarityThreshold?: number;
  /** Maximum tokens of context for the LLM (default: 2048) */
  maxContextTokens?: number;
  /** Tokens per chunk (default: 180) */
  chunkSize?: number;
  /** Overlap tokens between consecutive chunks (default: 30) */
  chunkOverlap?: number;
  /** Prompt template with `{context}` and `{query}` placeholders */
  promptTemplate?: string;
  /** Optional configuration JSON for the embedding model */
  embeddingConfigJSON?: string;
  /** Optional configuration JSON for the LLM model */
  llmConfigJSON?: string;
}

export interface RAGQueryOptions {
  question: string;
  systemPrompt?: string;
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
}

export interface RAGSearchResult {
  chunkId: string;
  text: string;
  similarityScore: number;
  metadataJson?: string;
}

export interface RAGResult {
  answer: string;
  retrievedChunks: RAGSearchResult[];
  contextUsed?: string;
  retrievalTimeMs: number;
  generationTimeMs: number;
  totalTimeMs: number;
}

export interface RAGStatistics {
  documentCount: number;
  chunkCount: number;
  vectorStoreSize: number;
  statsJson: string;
}
