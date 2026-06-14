/**
 * RunAnywhere+RAG.ts
 *
 * RAG (Retrieval-Augmented Generation) pipeline extension. All shapes come
 * from `@runanywhere/proto-ts/rag`; commons owns the embedding,
 * vector-store, and query pipeline.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/RAG/RunAnywhere+RAG.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';
import type {
  RAGConfiguration,
  RAGQueryOptions,
  RAGResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';
import { rAGConfigurationDefaults } from '@runanywhere/proto-ts/convenience/rag_convenience';
import {
  ModelCategory,
  InferenceFramework,
  ModelLoadRequest,
  type ModelInfo,
  type ModelLoadResult,
} from '@runanywhere/proto-ts/model_types';
import { loadModel } from '../Models/RunAnywhere+ModelLifecycle';
import {
  RAGConfiguration as RAGConfigurationMessage,
  RAGDocument,
  RAGQueryOptions as RAGQueryOptionsMessage,
  RAGResult as RAGResultMessage,
  RAGStatistics as RAGStatisticsMessage,
} from '@runanywhere/proto-ts/rag';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

const logger = new SDKLogger('RunAnywhere.RAG');

function decodeRequired<T>(
  buffer: ArrayBuffer,
  decode: (bytes: Uint8Array) => T,
  operation: string
): T {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed(operation);
  }
  return decode(bytes);
}

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

/**
 * Create a RAG pipeline with the given configuration.
 *
 * Matches Swift: `RunAnywhere.ragCreatePipeline(_:)` — the config is passed
 * through to the C++ commons layer verbatim. Numeric RAGConfiguration fields
 * are proto3 `optional`, so absent fields are honored by commons (which stamps
 * canonical defaults via the `RAGBackendConfig` in-struct defaults applied in
 * `build_backend_config`) and explicit zero values (e.g. `chunkOverlap: 0` to
 * disable overlap) are preserved end-to-end. Callers that want the canonical
 * defaults can seed the input with the generated `rAGConfigurationDefaults()`
 * helper from `@runanywhere/proto-ts/convenience/rag_convenience`.
 */
export async function ragCreatePipeline(config: RAGConfiguration): Promise<void>;
/**
 * Create the RAG pipeline from registry models. Model artifact layout is
 * resolved by commons lifecycle rather than by JS file-name heuristics.
 *
 * Matches Swift: `RunAnywhere.ragCreatePipeline(embeddingModel:llmModel:baseConfiguration:)`.
 */
export async function ragCreatePipeline(models: {
  embeddingModel: ModelInfo;
  llmModel: ModelInfo;
  baseConfiguration?: RAGConfiguration;
}): Promise<void>;
export async function ragCreatePipeline(
  configOrModels:
    | RAGConfiguration
    | {
        embeddingModel: ModelInfo;
        llmModel: ModelInfo;
        baseConfiguration?: RAGConfiguration;
      }
): Promise<void> {
  if ('embeddingModel' in configOrModels && 'llmModel' in configOrModels) {
    const config = await ragResolvedConfiguration(
      configOrModels.embeddingModel,
      configOrModels.llmModel,
      configOrModels.baseConfiguration
    );
    return ragCreatePipeline(config);
  }
  const config = configOrModels as RAGConfiguration;
  // Swift parity: guard isInitialized (RunAnywhere+RAG.swift:59-61).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+RAG.swift:62 gates on ensureServicesReady.
  await ensureServicesReady();
  const success = await native.ragCreatePipelineProto(
    encodeProtoMessage(
      RAGConfigurationMessage.fromPartial(config),
      RAGConfigurationMessage
    )
  );
  if (!success) {
    throw SDKException.generationFailedWith('Failed to create RAG pipeline');
  }
  logger.info('RAG pipeline created');
}

/** Destroy the RAG pipeline and release resources. */
export async function ragDestroyPipeline(): Promise<void> {
  const native = ensureNative();
  await native.ragDestroyPipelineProto();
  logger.info('RAG pipeline destroyed');
}

/**
 * Ingest a proto document into the RAG pipeline.
 *
 * Primary overload — matches Swift: `RunAnywhere.ragIngest(_:)`.
 * Returns pipeline statistics after ingestion.
 */
export async function ragIngest(document: RAGDocument): Promise<RAGStatistics>;
/**
 * Ingest a text document into the RAG pipeline (convenience overload).
 *
 * Builds a `RAGDocument` proto from the text and optional JSON metadata,
 * then delegates to the primary overload. Matches Swift:
 * `RunAnywhere.ragIngest(text:metadataJSON:)`.
 */
export async function ragIngest(
  text: string,
  metadataJson?: string
): Promise<RAGStatistics>;
export async function ragIngest(
  textOrDocument: string | RAGDocument,
  metadataJson?: string
): Promise<RAGStatistics> {
  // Swift parity: guard isInitialized (RunAnywhere+RAG.swift:93-95).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+RAG.swift:96 gates on ensureServicesReady.
  await ensureServicesReady();
  let document: RAGDocument;
  if (typeof textOrDocument === 'string') {
    // The `metadata_json` proto field was deleted. Best-effort parse
    // of the legacy JSON blob into the typed `metadata` map.
    document = RAGDocument.create({
      id: '',
      text: textOrDocument,
      metadata: parseMetadata(metadataJson),
    });
  } else {
    document = textOrDocument;
  }
  const statsBytes = await native.ragIngestProto(
    encodeProtoMessage(document, RAGDocument)
  );
  return decodeRequired(statsBytes, RAGStatisticsMessage.decode, 'ragIngestProto');
}

function parseMetadata(json?: string): Record<string, string> {
  if (!json) return {};
  const trimmed = json.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return {};
  try {
    const parsed = JSON.parse(trimmed) as Record<string, unknown>;
    const out: Record<string, string> = {};
    for (const [k, v] of Object.entries(parsed)) {
      out[k] = typeof v === 'string' ? v : String(v);
    }
    return out;
  } catch {
    return {};
  }
}

/**
 * Ingest multiple proto documents in batch.
 *
 * Primary overload — matches Swift: `RunAnywhere.ragAddDocumentsBatch(documents:)`.
 */
export async function ragAddDocumentsBatch(
  documents: RAGDocument[]
): Promise<void>;
/**
 * Ingest multiple text documents in batch (convenience overload).
 *
 * Builds `RAGDocument` protos from the ad-hoc shapes, then delegates to
 * the primary overload.
 */
export async function ragAddDocumentsBatch(
  documents: Array<{ text: string; metadataJson?: string }>
): Promise<void>;
export async function ragAddDocumentsBatch(
  documents: RAGDocument[] | Array<{ text: string; metadataJson?: string }>
): Promise<void> {
  // Swift parity: guard isInitialized (RunAnywhere+RAG.swift:110-112).
  requireInitialized();
  for (const doc of documents) {
    // Distinguish RAGDocument proto (has typed `metadata` map) from the
    // convenience ad-hoc shape (has `metadataJson` string).
    if ('metadataJson' in doc) {
      const adHoc = doc as { text: string; metadataJson?: string };
      await ragIngest(adHoc.text, adHoc.metadataJson);
    } else {
      await ragIngest(doc as RAGDocument);
    }
  }
}

/**
 * Query the RAG pipeline with a question.
 *
 * Matches Swift: `RunAnywhere.ragQuery(_:options:)` — the options message is
 * forwarded verbatim (including `retrievalTopK`, `similarityThreshold`,
 * `stream`, and `disableThinking`). Unset numeric fields encode as proto3
 * zeros, which commons maps to the canonical `rac_default` values.
 */
export async function ragQuery(
  question: string,
  options?: Partial<Omit<RAGQueryOptions, 'question'>>
): Promise<RAGResult>;
/**
 * Query through the proto options message directly.
 *
 * Matches Swift: `RunAnywhere.ragQuery(_ options: RARAGQueryOptions)`.
 */
export async function ragQuery(options: RAGQueryOptions): Promise<RAGResult>;
export async function ragQuery(
  questionOrOptions: string | RAGQueryOptions,
  options?: Partial<Omit<RAGQueryOptions, 'question'>>
): Promise<RAGResult> {
  // Swift parity: guard isInitialized (RunAnywhere+RAG.swift:191-193).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+RAG.swift:194 gates on ensureServicesReady.
  await ensureServicesReady();
  const queryOptions: RAGQueryOptions =
    typeof questionOrOptions === 'string'
      ? RAGQueryOptionsMessage.fromPartial({
          ...options,
          // Defaults mirror Swift RARAGQueryOptions.defaults(question:)
          // (generated from IDL rac_default annotations): maxTokens 512,
          // temperature 0.7, topP 1.0. Caller-provided options override.
          maxTokens: options?.maxTokens ?? 512,
          temperature: options?.temperature ?? 0.7,
          topP: options?.topP ?? 1.0,
          question: questionOrOptions,
        })
      : questionOrOptions;
  const resultBytes = await native.ragQueryProto(
    encodeProtoMessage(queryOptions, RAGQueryOptionsMessage)
  );
  return decodeRequired(resultBytes, RAGResultMessage.decode, 'ragQueryProto');
}

/** Clear all documents from the pipeline. */
export async function ragClearDocuments(): Promise<void> {
  // Swift parity: guard isInitialized (RunAnywhere+RAG.swift:154-156).
  requireInitialized();
  const native = ensureNative();
  await native.ragClearProto();
}

/**
 * Get the number of indexed document chunks.
 *
 * Swift parity (RunAnywhere+RAG.swift:128-134): never throws — returns 0
 * when the SDK/pipeline is not ready or stats are unavailable.
 */
export async function ragGetDocumentCount(): Promise<number> {
  try {
    const stats = await ragGetStatistics();
    return stats.indexedChunks;
  } catch {
    return 0;
  }
}

/** Get pipeline statistics. Throws when the SDK or pipeline is not ready. */
export async function ragGetStatistics(): Promise<RAGStatistics> {
  // Swift parity: guard isInitialized (RunAnywhere+RAG.swift:143-145).
  requireInitialized();
  const native = ensureNative();
  const statsBytes = await native.ragStatsProto();
  return decodeRequired(statsBytes, RAGStatisticsMessage.decode, 'ragStatsProto');
}

/**
 * The current number of indexed document chunks in the pipeline.
 *
 * Matches Swift: `RunAnywhere.ragDocumentCount` (property; a function here
 * because JS getters cannot await).
 */
export async function ragDocumentCount(): Promise<number> {
  return ragGetDocumentCount();
}

/**
 * Build a generated RAG configuration from registry models by using commons
 * lifecycle resolution for primary and sidecar artifacts.
 *
 * Matches Swift: `RunAnywhere.ragResolvedConfiguration(embeddingModel:llmModel:baseConfiguration:)`
 * + `RARAGConfiguration.resolvingLifecycleArtifacts(embedding:llm:)` — commons
 * owns model-id → path resolution; this helper only stamps resolved model ids
 * onto the configuration after the lifecycle loads succeed.
 */
export async function ragResolvedConfiguration(
  embeddingModel: ModelInfo,
  llmModel: ModelInfo,
  baseConfiguration?: RAGConfiguration
): Promise<RAGConfiguration> {
  const embedding = await loadRAGArtifactModel(
    embeddingModel,
    ModelCategory.MODEL_CATEGORY_EMBEDDING,
    'Embedding'
  );
  const llm = await loadRAGArtifactModel(
    llmModel,
    ModelCategory.MODEL_CATEGORY_LANGUAGE,
    'LLM'
  );
  return {
    ...(baseConfiguration ?? rAGConfigurationDefaults()),
    embeddingModelId: embedding.modelId,
    llmModelId: llm.modelId,
  };
}

/**
 * Load one RAG artifact model through the commons lifecycle so artifact
 * paths are registered before session-create. Mirrors Swift's private
 * `loadRAGArtifactModel` (RunAnywhere+RAG.swift:201-225).
 */
async function loadRAGArtifactModel(
  model: ModelInfo,
  fallbackCategory: ModelCategory,
  errorLabel: string
): Promise<ModelLoadResult> {
  const request = ModelLoadRequest.fromPartial({
    modelId: model.id,
    category:
      model.category === ModelCategory.MODEL_CATEGORY_UNSPECIFIED
        ? fallbackCategory
        : model.category,
    ...(model.framework !== InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN
      ? { framework: model.framework }
      : {}),
  });
  const result = await loadModel(request);
  if (!result.success) {
    const message =
      result.errorMessage ||
      `${errorLabel} model lifecycle artifact resolution failed`;
    throw SDKException.modelLoadFailed(
      `${errorLabel} model '${model.id}': ${message}`
    );
  }
  return result;
}
