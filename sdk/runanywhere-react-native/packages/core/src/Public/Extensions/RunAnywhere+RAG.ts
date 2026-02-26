/**
 * RunAnywhere+RAG.ts
 *
 * RAG (Retrieval-Augmented Generation) pipeline extension.
 * Delegates to native RAGBridge via the core HybridObject.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RunAnywhere+RAG.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  RAGConfiguration,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
} from '../../types/RAGTypes';

const logger = new SDKLogger('RunAnywhere.RAG');

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  return requireNativeModule();
}

/**
 * Create a RAG pipeline with the given configuration.
 * Must be called before ingesting documents or querying.
 */
export async function ragCreatePipeline(config: RAGConfiguration): Promise<void> {
  const native = ensureNative();

  const configWithDefaults = {
    embeddingModelPath: config.embeddingModelPath,
    llmModelPath: config.llmModelPath,
    embeddingDimension: config.embeddingDimension ?? 384,
    topK: config.topK ?? 10,
    similarityThreshold: config.similarityThreshold ?? 0.15,
    maxContextTokens: config.maxContextTokens ?? 2048,
    chunkSize: config.chunkSize ?? 512,
    chunkOverlap: config.chunkOverlap ?? 50,
    promptTemplate: config.promptTemplate ?? '',
  };

  const success = await native.ragCreatePipeline(JSON.stringify(configWithDefaults));
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

/**
 * Ingest a document into the RAG pipeline.
 * The document is split into chunks, embedded, and indexed.
 */
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

/**
 * Add multiple documents in batch.
 */
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
 * Returns the generated answer and retrieved chunks.
 */
export async function ragQuery(
  question: string,
  options?: Omit<RAGQueryOptions, 'question'>
): Promise<RAGResult> {
  const native = ensureNative();

  const queryOptions: RAGQueryOptions = {
    question,
    ...options,
  };

  const resultJson = await native.ragQuery(JSON.stringify(queryOptions));
  return JSON.parse(resultJson) as RAGResult;
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
  const parsed = JSON.parse(json);
  return {
    documentCount: await ragGetDocumentCount(),
    chunkCount: parsed.chunk_count ?? 0,
    vectorStoreSize: parsed.vector_store_size_mb ?? 0,
    statsJson: json,
  };
}
