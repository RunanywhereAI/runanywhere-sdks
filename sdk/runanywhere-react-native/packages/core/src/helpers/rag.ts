/**
 * helpers/rag — ergonomic helpers for proto-encoded RAG types.
 */

import { RAGConfiguration, RAGQueryOptions } from '@runanywhere/proto-ts/rag';

export {
  RAGConfiguration,
  RAGQueryOptions,
  type RAGSearchResult,
  type RAGResult,
  type RAGStatistics,
} from '@runanywhere/proto-ts/rag';

/** Default `RAGConfiguration` mirroring Swift `RAGConfiguration()` defaults. */
export function defaultRAGConfig(): RAGConfiguration {
  return RAGConfiguration.create({
    embeddingModelPath: '',
    llmModelPath: '',
    embeddingDimension: 384,
    topK: 5,
    similarityThreshold: 0.0,
    chunkSize: 512,
    chunkOverlap: 64,
  });
}

/** Default `RAGQueryOptions`. */
export function defaultRAGQueryOptions(question = ''): RAGQueryOptions {
  return RAGQueryOptions.create({
    question,
    systemPrompt: '',
    maxTokens: 512,
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
  });
}
