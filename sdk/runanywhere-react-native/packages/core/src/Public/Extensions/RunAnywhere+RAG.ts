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
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';
import {
  RAGConfiguration as RAGConfigurationMessage,
  RAGDocument,
  RAGQueryOptions as RAGQueryOptionsMessage,
  RAGResult as RAGResultMessage,
  RAGStatistics as RAGStatisticsMessage,
} from '@runanywhere/proto-ts/rag';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.RAG');

function decodeRequired<T>(
  buffer: ArrayBuffer,
  decode: (bytes: Uint8Array) => T,
  operation: string
): T {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw new Error(`${operation} returned an empty proto result`);
  }
  return decode(bytes);
}

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
  const configWithDefaults = RAGConfigurationMessage.create({
    ...config,
    embeddingDimension: config.embeddingDimension ?? 384,
    topK: config.topK ?? 3,
    similarityThreshold: config.similarityThreshold ?? 0.12,
    chunkSize: config.chunkSize ?? 180,
    chunkOverlap: config.chunkOverlap ?? 30,
    maxContextTokens: config.maxContextTokens ?? 0,
  });
  const success = await native.ragCreatePipelineProto(
    bytesToArrayBuffer(RAGConfigurationMessage.encode(configWithDefaults).finish())
  );
  if (!success) {
    throw new Error('Failed to create RAG pipeline');
  }
  logger.info('RAG pipeline created');
}

/** Destroy the RAG pipeline and release resources. */
export async function ragDestroyPipeline(): Promise<void> {
  const native = ensureNative();
  await native.ragDestroyPipelineProto();
  logger.info('RAG pipeline destroyed');
}

/** Ingest a document into the RAG pipeline. */
export async function ragIngest(
  text: string,
  metadataJson?: string
): Promise<void> {
  const native = ensureNative();
  const document = RAGDocument.create({
    id: '',
    text,
    metadataJson,
    metadata: {},
  });
  await native.ragIngestProto(bytesToArrayBuffer(RAGDocument.encode(document).finish()));
}

/** Add multiple documents in batch. */
export async function ragAddDocumentsBatch(
  documents: Array<{ text: string; metadataJson?: string }>
): Promise<void> {
  for (const document of documents) {
    await ragIngest(document.text, document.metadataJson);
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
  const resultBytes = await native.ragQueryProto(
    bytesToArrayBuffer(RAGQueryOptionsMessage.encode(queryOptions).finish())
  );
  return decodeRequired(resultBytes, RAGResultMessage.decode, 'ragQueryProto');
}

/** Clear all documents from the pipeline. */
export async function ragClearDocuments(): Promise<void> {
  const native = ensureNative();
  await native.ragClearProto();
}

/** Get the number of indexed document chunks. */
export async function ragGetDocumentCount(): Promise<number> {
  const stats = await ragGetStatistics();
  return stats.indexedChunks;
}

/** Get pipeline statistics. */
export async function ragGetStatistics(): Promise<RAGStatistics> {
  const native = ensureNative();
  const statsBytes = await native.ragStatsProto();
  return decodeRequired(statsBytes, RAGStatisticsMessage.decode, 'ragStatsProto');
}
