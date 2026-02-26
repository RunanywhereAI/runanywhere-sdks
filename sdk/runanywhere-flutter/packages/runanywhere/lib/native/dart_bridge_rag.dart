/// DartBridge+RAG
///
/// RAG pipeline bridge - manages C++ RAG pipeline lifecycle.
/// Mirrors Swift's CppBridge+RAG.swift pattern.
///
/// The RAG pipeline is a feature (like Voice Agent) that orchestrates
/// LLM and Embeddings services for Retrieval-Augmented Generation.
library dart_bridge_rag;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

// =============================================================================
// RAG Types (mirrors Swift RAGTypes.swift / Kotlin RAGTypes.kt)
// =============================================================================

/// Configuration for creating a RAG pipeline.
class RAGConfiguration {
  /// Path to the ONNX embedding model
  final String embeddingModelPath;

  /// Path to the GGUF LLM model
  final String llmModelPath;

  /// Embedding vector dimension (default: 384 for all-MiniLM-L6-v2)
  final int embeddingDimension;

  /// Number of top chunks to retrieve per query
  final int topK;

  /// Minimum cosine similarity threshold 0.0-1.0
  final double similarityThreshold;

  /// Maximum tokens for context sent to the LLM
  final int maxContextTokens;

  /// Tokens per chunk when splitting documents
  final int chunkSize;

  /// Overlap tokens between consecutive chunks
  final int chunkOverlap;

  /// Prompt template with {context} and {query} placeholders
  final String? promptTemplate;

  /// Optional configuration JSON for the embedding model
  final String? embeddingConfigJson;

  /// Optional configuration JSON for the LLM model
  final String? llmConfigJson;

  const RAGConfiguration({
    required this.embeddingModelPath,
    required this.llmModelPath,
    this.embeddingDimension = 384,
    this.topK = 10,
    this.similarityThreshold = 0.15,
    this.maxContextTokens = 2048,
    this.chunkSize = 512,
    this.chunkOverlap = 50,
    this.promptTemplate,
    this.embeddingConfigJson,
    this.llmConfigJson,
  });
}

/// Options for querying the RAG pipeline.
class RAGQueryOptions {
  final String question;
  final String? systemPrompt;
  final int maxTokens;
  final double temperature;
  final double topP;
  final int topK;

  const RAGQueryOptions({
    required this.question,
    this.systemPrompt,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
  });
}

/// A single retrieved document chunk.
class RAGSearchResult {
  final String chunkId;
  final String text;
  final double similarityScore;
  final String? metadataJson;

  const RAGSearchResult({
    required this.chunkId,
    required this.text,
    required this.similarityScore,
    this.metadataJson,
  });
}

/// Result of a RAG query.
class RAGResult {
  final String answer;
  final List<RAGSearchResult> retrievedChunks;
  final String? contextUsed;
  final double retrievalTimeMs;
  final double generationTimeMs;
  final double totalTimeMs;

  const RAGResult({
    required this.answer,
    required this.retrievedChunks,
    this.contextUsed,
    required this.retrievalTimeMs,
    required this.generationTimeMs,
    required this.totalTimeMs,
  });
}

// =============================================================================
// FFI Struct for rac_rag_config_t (legacy standalone config)
// =============================================================================

final class _RacRagConfig extends Struct {
  external Pointer<Utf8> embeddingModelPath;
  external Pointer<Utf8> llmModelPath;
  @Size()
  external int embeddingDimension;
  @Size()
  external int topK;
  @Float()
  external double similarityThreshold;
  @Size()
  external int maxContextTokens;
  @Size()
  external int chunkSize;
  @Size()
  external int chunkOverlap;
  external Pointer<Utf8> promptTemplate;
  external Pointer<Utf8> embeddingConfigJson;
  external Pointer<Utf8> llmConfigJson;
}

final class _RacRagQuery extends Struct {
  external Pointer<Utf8> question;
  external Pointer<Utf8> systemPrompt;
  @Int32()
  external int maxTokens;
  @Float()
  external double temperature;
  @Float()
  external double topP;
  @Int32()
  external int topK;
}

final class _RacSearchResult extends Struct {
  external Pointer<Utf8> chunkId;
  external Pointer<Utf8> text;
  @Float()
  external double similarityScore;
  external Pointer<Utf8> metadataJson;
}

final class _RacRagResult extends Struct {
  external Pointer<Utf8> answer;
  external Pointer<_RacSearchResult> retrievedChunks;
  @Size()
  external int numChunks;
  external Pointer<Utf8> contextUsed;
  @Double()
  external double retrievalTimeMs;
  @Double()
  external double generationTimeMs;
  @Double()
  external double totalTimeMs;
}

// =============================================================================
// FFI Function Typedefs
// =============================================================================

typedef _RagRegisterNative = Int32 Function();
typedef _RagRegisterDart = int Function();

typedef _RagCreateStandaloneNative = Int32 Function(
    Pointer<_RacRagConfig> config, Pointer<Pointer<Void>> outPipeline);
typedef _RagCreateStandaloneDart = int Function(
    Pointer<_RacRagConfig> config, Pointer<Pointer<Void>> outPipeline);

typedef _RagDestroyNative = Void Function(Pointer<Void> pipeline);
typedef _RagDestroyDart = void Function(Pointer<Void> pipeline);

typedef _RagAddDocumentNative = Int32 Function(
    Pointer<Void> pipeline, Pointer<Utf8> text, Pointer<Utf8> metadata);
typedef _RagAddDocumentDart = int Function(
    Pointer<Void> pipeline, Pointer<Utf8> text, Pointer<Utf8> metadata);

typedef _RagQueryNative = Int32 Function(
    Pointer<Void> pipeline, Pointer<_RacRagQuery> query, Pointer<_RacRagResult> result);
typedef _RagQueryDart = int Function(
    Pointer<Void> pipeline, Pointer<_RacRagQuery> query, Pointer<_RacRagResult> result);

typedef _RagClearNative = Int32 Function(Pointer<Void> pipeline);
typedef _RagClearDart = int Function(Pointer<Void> pipeline);

typedef _RagCountNative = Size Function(Pointer<Void> pipeline);
typedef _RagCountDart = int Function(Pointer<Void> pipeline);

typedef _RagResultFreeNative = Void Function(Pointer<_RacRagResult> result);
typedef _RagResultFreeDart = void Function(Pointer<_RacRagResult> result);

// =============================================================================
// DartBridgeRAG — FFI bridge to rac_rag_pipeline_* C API
// =============================================================================

/// RAG pipeline bridge for C++ interop.
///
/// Mirrors Swift's CppBridge.RAG actor pattern.
class DartBridgeRAG {
  static final DartBridgeRAG shared = DartBridgeRAG._();

  DartBridgeRAG._();

  final _logger = SDKLogger('DartBridge.RAG');
  Pointer<Void>? _pipeline;
  bool _registered = false;

  bool get isCreated => _pipeline != null;

  /// Register the RAG module (call once before using RAG).
  void register() {
    if (_registered) return;

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagRegisterNative, _RagRegisterDart>(
        'rac_backend_rag_register');

    final result = fn();
    if (result != RAC_SUCCESS && result != -401) {
      _logger.error('Failed to register RAG module: $result');
      return;
    }

    _registered = true;
    _logger.debug('RAG module registered');
  }

  /// Create a RAG pipeline with the given configuration.
  void createPipeline(RAGConfiguration config) {
    if (!_registered) register();

    final lib = PlatformLoader.loadCommons();
    final fn =
        lib.lookupFunction<_RagCreateStandaloneNative, _RagCreateStandaloneDart>(
            'rac_rag_pipeline_create_standalone');

    final cConfig = calloc<_RacRagConfig>();
    final outPipeline = calloc<Pointer<Void>>();

    try {
      cConfig.ref.embeddingModelPath =
          config.embeddingModelPath.toNativeUtf8();
      cConfig.ref.llmModelPath = config.llmModelPath.toNativeUtf8();
      cConfig.ref.embeddingDimension = config.embeddingDimension;
      cConfig.ref.topK = config.topK;
      cConfig.ref.similarityThreshold = config.similarityThreshold;
      cConfig.ref.maxContextTokens = config.maxContextTokens;
      cConfig.ref.chunkSize = config.chunkSize;
      cConfig.ref.chunkOverlap = config.chunkOverlap;
      cConfig.ref.promptTemplate = config.promptTemplate != null
          ? config.promptTemplate!.toNativeUtf8()
          : nullptr;
      cConfig.ref.embeddingConfigJson = config.embeddingConfigJson != null
          ? config.embeddingConfigJson!.toNativeUtf8()
          : nullptr;
      cConfig.ref.llmConfigJson = config.llmConfigJson != null
          ? config.llmConfigJson!.toNativeUtf8()
          : nullptr;

      final result = fn(cConfig, outPipeline);
      if (result != RAC_SUCCESS || outPipeline.value == nullptr) {
        throw Exception('Failed to create RAG pipeline: error $result');
      }

      // Destroy existing pipeline if any
      if (_pipeline != null) {
        destroyPipeline();
      }

      _pipeline = outPipeline.value;
      _logger.debug('RAG pipeline created');
    } finally {
      calloc.free(cConfig.ref.embeddingModelPath);
      calloc.free(cConfig.ref.llmModelPath);
      if (cConfig.ref.promptTemplate != nullptr) {
        calloc.free(cConfig.ref.promptTemplate);
      }
      if (cConfig.ref.embeddingConfigJson != nullptr) {
        calloc.free(cConfig.ref.embeddingConfigJson);
      }
      if (cConfig.ref.llmConfigJson != nullptr) {
        calloc.free(cConfig.ref.llmConfigJson);
      }
      calloc.free(cConfig);
      calloc.free(outPipeline);
    }
  }

  /// Destroy the RAG pipeline.
  void destroyPipeline() {
    if (_pipeline == null) return;

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagDestroyNative, _RagDestroyDart>(
        'rac_rag_pipeline_destroy');

    fn(_pipeline!);
    _pipeline = null;
    _logger.debug('RAG pipeline destroyed');
  }

  /// Add a document to the pipeline.
  void addDocument(String text, {String? metadataJson}) {
    _ensurePipeline();

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagAddDocumentNative, _RagAddDocumentDart>(
        'rac_rag_add_document');

    final cText = text.toNativeUtf8();
    final cMeta = metadataJson != null ? metadataJson.toNativeUtf8() : nullptr;

    try {
      final result = fn(_pipeline!, cText, cMeta);
      if (result != RAC_SUCCESS) {
        throw Exception('Failed to add document: error $result');
      }
    } finally {
      calloc.free(cText);
      if (cMeta != nullptr) calloc.free(cMeta);
    }
  }

  /// Clear all documents from the pipeline.
  void clearDocuments() {
    _ensurePipeline();

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagClearNative, _RagClearDart>(
        'rac_rag_clear_documents');

    fn(_pipeline!);
  }

  /// Get the number of indexed document chunks.
  int get documentCount {
    if (_pipeline == null) return 0;

    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<_RagCountNative, _RagCountDart>(
        'rac_rag_get_document_count');

    return fn(_pipeline!);
  }

  /// Query the RAG pipeline.
  RAGResult query(RAGQueryOptions options) {
    _ensurePipeline();

    final lib = PlatformLoader.loadCommons();
    final queryFn = lib.lookupFunction<_RagQueryNative, _RagQueryDart>(
        'rac_rag_query');
    final freeFn = lib.lookupFunction<_RagResultFreeNative, _RagResultFreeDart>(
        'rac_rag_result_free');

    final cQuery = calloc<_RacRagQuery>();
    final cResult = calloc<_RacRagResult>();

    try {
      cQuery.ref.question = options.question.toNativeUtf8();
      cQuery.ref.systemPrompt = options.systemPrompt != null
          ? options.systemPrompt!.toNativeUtf8()
          : nullptr;
      cQuery.ref.maxTokens = options.maxTokens;
      cQuery.ref.temperature = options.temperature;
      cQuery.ref.topP = options.topP;
      cQuery.ref.topK = options.topK;

      final status = queryFn(_pipeline!, cQuery, cResult);
      if (status != RAC_SUCCESS) {
        throw Exception('RAG query failed: error $status');
      }

      // Convert C result to Dart
      final answer = cResult.ref.answer != nullptr
          ? cResult.ref.answer.toDartString()
          : '';
      final contextUsed = cResult.ref.contextUsed != nullptr
          ? cResult.ref.contextUsed.toDartString()
          : null;

      final chunks = <RAGSearchResult>[];
      for (int i = 0; i < cResult.ref.numChunks; i++) {
        final c = cResult.ref.retrievedChunks[i];
        chunks.add(RAGSearchResult(
          chunkId: c.chunkId != nullptr ? c.chunkId.toDartString() : '',
          text: c.text != nullptr ? c.text.toDartString() : '',
          similarityScore: c.similarityScore,
          metadataJson:
              c.metadataJson != nullptr ? c.metadataJson.toDartString() : null,
        ));
      }

      final result = RAGResult(
        answer: answer,
        retrievedChunks: chunks,
        contextUsed: contextUsed,
        retrievalTimeMs: cResult.ref.retrievalTimeMs,
        generationTimeMs: cResult.ref.generationTimeMs,
        totalTimeMs: cResult.ref.totalTimeMs,
      );

      freeFn(cResult);
      return result;
    } finally {
      calloc.free(cQuery.ref.question);
      if (cQuery.ref.systemPrompt != nullptr) {
        calloc.free(cQuery.ref.systemPrompt);
      }
      calloc.free(cQuery);
      calloc.free(cResult);
    }
  }

  void _ensurePipeline() {
    if (_pipeline == null) {
      throw StateError('RAG pipeline not created. Call createPipeline() first.');
    }
  }
}
