/**
 * RunAnywhere+RAG.ts
 *
 * RAG (Retrieval-Augmented Generation) pipeline extension. Wave 2:
 * aligned to proto-canonical RAG shapes (`@runanywhere/proto-ts/rag`).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RunAnywhere+RAG.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  RAGConfiguration,
  RAGQueryOptions,
  RAGResult,
  RAGSearchResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';

const logger = new SDKLogger('RunAnywhere.RAG');

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  return requireNativeModule();
}

/**
 * Create a RAG pipeline with the given configuration.
 *
 * Matches Swift: `RunAnywhere.ragCreatePipeline(_:)`.
 */
export async function ragCreatePipeline(
  config: RAGConfiguration
): Promise<void> {
  const native = ensureNative();
  const configWithDefaults = {
    embeddingModelPath: config.embeddingModelPath,
    llmModelPath: config.llmModelPath,
    embeddingDimension: config.embeddingDimension ?? 384,
    topK: config.topK ?? 3,
    similarityThreshold: config.similarityThreshold ?? 0.12,
    chunkSize: config.chunkSize ?? 180,
    chunkOverlap: config.chunkOverlap ?? 30,
  };
  const success = await native.ragCreatePipeline(
    JSON.stringify(configWithDefaults)
  );
  if (!success) {
    throw new Error('Failed to create RAG pipeline');
  }
  logger.info('RAG pipeline created');
}

/** Destroy the RAG pipeline and release resources. */
export async function ragDestroyPipeline(): Promise<void> {
  const native = ensureNative();
  await native.ragDestroyPipeline();
  logger.info('RAG pipeline destroyed');
}

/** Ingest a document into the RAG pipeline. */
export async function ragIngest(
  text: string,
  metadataJson?: string
): Promise<void> {
  const native = ensureNative();
  const success = await native.ragAddDocument(text, metadataJson ?? '');
  if (!success) {
    throw new Error('Failed to add document');
  }
}

/** Add multiple documents in batch. */
export async function ragAddDocumentsBatch(
  documents: Array<{ text: string; metadataJson?: string }>
): Promise<void> {
  const native = ensureNative();
  const success = await native.ragAddDocumentsBatch(JSON.stringify(documents));
  if (!success) {
    throw new Error('Failed to add documents batch');
  }
}

/**
 * Query the RAG pipeline with a question.
 *
 * Matches Swift: `RunAnywhere.ragQuery(_:options:)`.
 */
export async function ragQuery(
  question: string,
  options?: Omit<RAGQueryOptions, 'question'>
): Promise<RAGResult> {
  const native = ensureNative();
  const queryOptions: RAGQueryOptions = {
    question,
    systemPrompt: options?.systemPrompt,
    maxTokens: options?.maxTokens ?? 0,
    temperature: options?.temperature ?? 0,
    topP: options?.topP ?? 1.0,
    topK: options?.topK ?? 0,
  };
  const resultJson = await native.ragQuery(JSON.stringify(queryOptions));
  return parseRAGResult(resultJson);
}

/** Clear all documents from the pipeline. */
export async function ragClearDocuments(): Promise<void> {
  const native = ensureNative();
  await native.ragClearDocuments();
}

/** Get the number of indexed document chunks. */
export async function ragGetDocumentCount(): Promise<number> {
  const native = ensureNative();
  return native.ragGetDocumentCount();
}

/** Get pipeline statistics. */
export async function ragGetStatistics(): Promise<RAGStatistics> {
  const native = ensureNative();
  const json = await native.ragGetStatistics();
  try {
    const parsed = JSON.parse(json) as {
      indexedDocuments?: number;
      indexed_documents?: number;
      documentCount?: number;
      document_count?: number;
      indexedChunks?: number;
      indexed_chunks?: number;
      chunkCount?: number;
      chunk_count?: number;
      totalTokensIndexed?: number;
      total_tokens_indexed?: number;
      lastUpdatedMs?: number;
      last_updated_ms?: number;
      indexPath?: string;
      index_path?: string;
    };
    return {
      indexedDocuments:
        parsed.indexedDocuments ??
        parsed.indexed_documents ??
        parsed.documentCount ??
        parsed.document_count ??
        0,
      indexedChunks:
        parsed.indexedChunks ??
        parsed.indexed_chunks ??
        parsed.chunkCount ??
        parsed.chunk_count ??
        0,
      totalTokensIndexed:
        parsed.totalTokensIndexed ?? parsed.total_tokens_indexed ?? 0,
      lastUpdatedMs: parsed.lastUpdatedMs ?? parsed.last_updated_ms ?? 0,
      indexPath: parsed.indexPath ?? parsed.index_path,
    };
  } catch {
    return {
      indexedDocuments: 0,
      indexedChunks: 0,
      totalTokensIndexed: 0,
      lastUpdatedMs: 0,
    };
  }
}

function parseRAGResult(json: string): RAGResult {
  const parsed = JSON.parse(json) as {
    answer?: string;
    retrievedChunks?: Array<Partial<RAGSearchResult>>;
    retrieved_chunks?: Array<Partial<RAGSearchResult>>;
    contextUsed?: string;
    context_used?: string;
    retrievalTimeMs?: number;
    retrieval_time_ms?: number;
    generationTimeMs?: number;
    generation_time_ms?: number;
    totalTimeMs?: number;
    total_time_ms?: number;
  };
  const chunks = (parsed.retrievedChunks ?? parsed.retrieved_chunks ?? []).map(
    (chunk): RAGSearchResult => ({
      chunkId: chunk.chunkId ?? '',
      text: chunk.text ?? '',
      similarityScore: chunk.similarityScore ?? 0,
      sourceDocument: chunk.sourceDocument,
      metadata: chunk.metadata ?? {},
    })
  );
  return {
    answer: parsed.answer ?? '',
    retrievedChunks: chunks,
    contextUsed: parsed.contextUsed ?? parsed.context_used ?? '',
    retrievalTimeMs: parsed.retrievalTimeMs ?? parsed.retrieval_time_ms ?? 0,
    generationTimeMs: parsed.generationTimeMs ?? parsed.generation_time_ms ?? 0,
    totalTimeMs: parsed.totalTimeMs ?? parsed.total_time_ms ?? 0,
  };
}
