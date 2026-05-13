/**
 * helpers/rag
 *
 * Swift-parity conveniences for generated RAG proto types.
 */

import {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  type RAGResult,
  type RAGStatistics,
} from '@runanywhere/proto-ts/rag';
import type { ModelLoadResult } from '@runanywhere/proto-ts/model_types';

export {
  RAGConfiguration,
  RAGDocument,
  RAGQueryOptions,
  type RAGIngestRequest,
  type RAGIngestResult,
  type RAGQueryRequest,
  type RAGResult,
  type RAGSearchResult,
  type RAGServiceState,
  type RAGStatistics,
  type RAGStreamEvent,
  RAGStreamEventKind,
} from '@runanywhere/proto-ts/rag';

export function ragConfigurationResolvingLifecycleArtifacts(
  config: RAGConfiguration,
  embedding: ModelLoadResult,
  llm: ModelLoadResult
): RAGConfiguration {
  return RAGConfiguration.create({
    ...config,
    embeddingModelId: embedding.modelId,
    llmModelId: llm.modelId,
  });
}

export function ragDocumentFromText(
  text: string,
  metadataJSON?: string
): ReturnType<typeof RAGDocument.create> {
  return RAGDocument.create({
    text,
    metadata: parseMetadata(metadataJSON),
  });
}

export function ragQueryOptionsDefaults(question: string): RAGQueryOptions {
  return RAGQueryOptions.create({
    question,
    systemPrompt: '',
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
    retrievalTopK: 0,
    similarityThreshold: 0,
    stream: false,
  });
}

export const defaultRAGQueryOptions = ragQueryOptionsDefaults;

export function ragResultTotalTime(result: RAGResult): number {
  return result.totalTimeMs / 1000;
}

export function ragStatisticsLastUpdated(
  statistics: RAGStatistics
): Date | undefined {
  return statistics.lastUpdatedMs > 0
    ? new Date(statistics.lastUpdatedMs)
    : undefined;
}

function parseMetadata(json?: string): Record<string, string> {
  if (!json) return {};
  const trimmed = json.trim();
  if (!trimmed) return {};
  try {
    const parsed = JSON.parse(trimmed) as Record<string, unknown>;
    return Object.fromEntries(
      Object.entries(parsed).map(([key, value]) => [key, String(value)])
    );
  } catch {
    return {};
  }
}
