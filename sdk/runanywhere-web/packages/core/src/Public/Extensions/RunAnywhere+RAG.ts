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
import { RAGProtoAdapter } from '../../Adapters/ModalityProtoAdapter';
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

export type RAGAvailabilitySource = 'provider' | 'wasm-exports' | 'unavailable';

export interface RAGAvailability {
  available: boolean;
  source: RAGAvailabilitySource;
  reason: string;
  missingExports: string[];
}

let _provider: RAGProvider | null = null;

export function setRAGProvider(provider: RAGProvider | null): void {
  _provider = provider;
}

export function getRAGAvailability(): RAGAvailability {
  if (_provider) {
    return {
      available: true,
      source: 'provider',
      reason: 'RAG provider registered.',
      missingExports: [],
    };
  }

  const adapter = RAGProtoAdapter.tryDefault();
  if (!adapter) {
    return {
      available: false,
      source: 'unavailable',
      reason: 'No RAG provider registered and no Web WASM module is active.',
      missingExports: [],
    };
  }

  const missingExports = adapter.missingRAGExports();
  if (missingExports.length > 0) {
    return {
      available: false,
      source: 'unavailable',
      reason: 'RAG is unavailable in this Web WASM build. The native RAG exports are missing, likely because RAC_BACKEND_RAG=OFF.',
      missingExports,
    };
  }

  return {
    available: false,
    source: 'wasm-exports',
    reason: 'Native RAG exports are present, but no Web RAG provider is registered for the public API.',
    missingExports: [],
  };
}

export function isRAGAvailable(): boolean {
  return getRAGAvailability().available;
}

function requireProvider(feature = 'RAG'): RAGProvider {
  if (_provider == null) {
    const availability = getRAGAvailability();
    // Phase C-prime: throw SDKException — wraps proto-typed wire envelope.
    throw SDKException.backendNotAvailable(
      feature,
      `${availability.reason}` +
      (availability.missingExports.length > 0
        ? ` Missing exports: ${availability.missingExports.join(', ')}.`
        : ''),
    );
  }
  return _provider;
}

// ---------------------------------------------------------------------------
// Pipeline lifecycle
// ---------------------------------------------------------------------------

export async function ragCreatePipeline(config: RAGConfiguration): Promise<void> {
  await requireProvider('RAG.createPipeline').ragCreatePipeline(config);
  logger.info('RAG pipeline created');
}

export async function ragDestroyPipeline(): Promise<void> {
  await requireProvider('RAG.destroyPipeline').ragDestroyPipeline();
  logger.info('RAG pipeline destroyed');
}

// ---------------------------------------------------------------------------
// Document ingestion
// ---------------------------------------------------------------------------

export async function ragIngest(text: string, metadataJson?: string): Promise<void> {
  await requireProvider('RAG.ingest').ragIngest(text, metadataJson);
}

export async function ragAddDocumentsBatch(
  documents: Array<{ text: string; metadataJson?: string }>,
): Promise<void> {
  const p = requireProvider('RAG.addDocumentsBatch');
  if (p.ragAddDocumentsBatch) return p.ragAddDocumentsBatch(documents);
  // Fallback: serial ingestion
  for (const d of documents) await p.ragIngest(d.text, d.metadataJson);
}

export async function ragClearDocuments(): Promise<void> {
  await requireProvider('RAG.clearDocuments').ragClearDocuments();
}

/** Canonical name: `ragGetDocumentCount` (§9). */
export async function ragGetDocumentCount(): Promise<number> {
  return requireProvider('RAG.getDocumentCount').ragGetDocumentCount();
}

// ---------------------------------------------------------------------------
// Query
// ---------------------------------------------------------------------------

export async function ragQuery(
  question: string,
  options?: Omit<RAGQueryOptions, 'question'>,
): Promise<RAGResult> {
  return requireProvider('RAG.query').ragQuery(question, options);
}

export async function ragGetStatistics(): Promise<RAGStatistics> {
  const p = requireProvider('RAG.getStatistics');
  if (p.ragGetStatistics) return p.ragGetStatistics();
  // Synthesize minimal stats from documentCount.
  const indexedDocuments = await p.ragGetDocumentCount();
  return {
    indexedDocuments,
    indexedChunks: indexedDocuments,
    totalTokensIndexed: 0,
    lastUpdatedMs: 0,
    indexPath: undefined,
    statsJson: undefined,
    vectorStoreSizeBytes: 0,
  };
}

export const RAG = {
  setProvider: setRAGProvider,
  availability: getRAGAvailability,
  isAvailable: isRAGAvailable,
  createPipeline: ragCreatePipeline,
  destroyPipeline: ragDestroyPipeline,
  ingest: ragIngest,
  addDocumentsBatch: ragAddDocumentsBatch,
  query: ragQuery,
  clearDocuments: ragClearDocuments,
  getDocumentCount: ragGetDocumentCount,
  getStatistics: ragGetStatistics,
};
