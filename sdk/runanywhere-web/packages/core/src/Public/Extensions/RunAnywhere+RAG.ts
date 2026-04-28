/**
 * RunAnywhere+RAG.ts
 *
 * Top-level RAG (Retrieval-Augmented Generation) API — mirrors Swift
 * `RunAnywhere+RAG.swift` and React Native's `RunAnywhere+RAG.ts`.
 *
 * As with LoRA, the Web WASM build doesn't yet ship the `rac_rag_*` C ABI;
 * methods dispatch to a `RAGProvider` installed by a backend. If no provider
 * is registered (today's state), each method throws `BackendNotAvailable`.
 *
 * Note: an alternate Web-native RAG path runs entirely in JS (see the
 * Documents view in the example app). Backends can register that JS-only
 * implementation here so the public API is the same regardless.
 */

import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import type {
  RAGConfiguration,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';

const logger = new SDKLogger('RAG');

export interface RAGProvider {
  ragCreatePipeline(config: RAGConfiguration): Promise<void>;
  ragDestroyPipeline(): Promise<void>;
  ragIngest(text: string, metadataJson?: string): Promise<void>;
  ragAddDocumentsBatch?(documents: Array<{ text: string; metadataJson?: string }>): Promise<void>;
  ragQuery(question: string, options?: Omit<RAGQueryOptions, 'question'>): Promise<RAGResult>;
  ragClearDocuments(): Promise<void>;
  ragGetDocumentCount(): Promise<number>;
  ragGetStatistics?(): Promise<RAGStatistics>;
}

let _provider: RAGProvider | null = null;

export function setRAGProvider(provider: RAGProvider | null): void {
  _provider = provider;
}

function requireProvider(): RAGProvider {
  if (_provider == null) {
    // Phase C-prime: throw SDKException — wraps proto-typed wire envelope.
    throw SDKException.backendNotAvailable(
      'RAG',
      'No RAG backend registered. Install a Web SDK build that ships the ' +
      'rac_rag_* WASM exports, or register a JS-only RAG provider via setRAGProvider().',
    );
  }
  return _provider;
}

// ---------------------------------------------------------------------------
// Pipeline lifecycle
// ---------------------------------------------------------------------------

export async function ragCreatePipeline(config: RAGConfiguration): Promise<void> {
  await requireProvider().ragCreatePipeline(config);
  logger.info('RAG pipeline created');
}

export async function ragDestroyPipeline(): Promise<void> {
  await requireProvider().ragDestroyPipeline();
  logger.info('RAG pipeline destroyed');
}

// ---------------------------------------------------------------------------
// Document ingestion
// ---------------------------------------------------------------------------

export async function ragIngest(text: string, metadataJson?: string): Promise<void> {
  await requireProvider().ragIngest(text, metadataJson);
}

export async function ragAddDocumentsBatch(
  documents: Array<{ text: string; metadataJson?: string }>,
): Promise<void> {
  const p = requireProvider();
  if (p.ragAddDocumentsBatch) return p.ragAddDocumentsBatch(documents);
  // Fallback: serial ingestion
  for (const d of documents) await p.ragIngest(d.text, d.metadataJson);
}

export async function ragClearDocuments(): Promise<void> {
  await requireProvider().ragClearDocuments();
}

export async function ragDocumentCount(): Promise<number> {
  return requireProvider().ragGetDocumentCount();
}

// ---------------------------------------------------------------------------
// Query
// ---------------------------------------------------------------------------

export async function ragQuery(
  question: string,
  options?: Omit<RAGQueryOptions, 'question'>,
): Promise<RAGResult> {
  return requireProvider().ragQuery(question, options);
}

export async function ragGetStatistics(): Promise<RAGStatistics> {
  const p = requireProvider();
  if (p.ragGetStatistics) return p.ragGetStatistics();
  // Synthesize minimal stats from documentCount.
  const indexedDocuments = await p.ragGetDocumentCount();
  return {
    indexedDocuments,
    indexedChunks: indexedDocuments,
    totalTokensIndexed: 0,
    lastUpdatedMs: 0,
    indexPath: undefined,
  };
}

export const RAG = {
  setProvider: setRAGProvider,
  createPipeline: ragCreatePipeline,
  destroyPipeline: ragDestroyPipeline,
  ingest: ragIngest,
  addDocumentsBatch: ragAddDocumentsBatch,
  query: ragQuery,
  clearDocuments: ragClearDocuments,
  documentCount: ragDocumentCount,
  getStatistics: ragGetStatistics,
};
