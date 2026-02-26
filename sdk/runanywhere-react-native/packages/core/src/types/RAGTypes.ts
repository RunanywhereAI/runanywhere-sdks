/**
 * RAG (Retrieval-Augmented Generation) types.
 * Mirrors Swift RAGTypes.swift and Kotlin RAGTypes.kt.
 */

export interface RAGConfiguration {
  embeddingModelPath: string;
  llmModelPath: string;
  embeddingDimension?: number;
  topK?: number;
  similarityThreshold?: number;
  maxContextTokens?: number;
  chunkSize?: number;
  chunkOverlap?: number;
  promptTemplate?: string;
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
