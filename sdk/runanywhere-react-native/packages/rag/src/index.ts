/**
 * index.ts
 *
 * Main entry point for @runanywhere/rag package
 */

export { RAG, createRAG, createRAGConfig, DEFAULT_PROMPT_TEMPLATE } from './RAG';
export type { Document } from './RAG';
export type {
  RAGConfig,
  RAGQuery,
  RAGResult,
  RAGChunk,
  RAGStatistics,
  RunAnywhereRAG,
} from './specs/RunAnywhereRAG.nitro';
