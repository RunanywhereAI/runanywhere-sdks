/// DartBridge+RAG
///
/// RAG pipeline bridge - manages C++ RAG pipeline lifecycle.
/// Mirrors Swift's CppBridge+RAG.swift pattern exactly.
///
/// This is a thin wrapper around C++ RAG pipeline functions.
/// All business logic is in C++ - Dart only manages the pipeline handle.
///
/// MEMORY SAFETY:
/// String pointers are freed in finally blocks.
/// Query results are copied to Dart objects before rac_rag_result_free is called.
library dart_bridge_rag;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// RAG pipeline bridge for C++ interop.
///
/// Provides access to the C++ RAG pipeline.
/// Handles pipeline lifecycle, document management, and query operations.
///
/// Matches Swift's CppBridge.RAG actor pattern.
///
/// Usage:
/// ```dart
/// DartBridgeRAG.registerBackend();
/// final rag = DartBridgeRAG.shared;
/// rag.createPipeline(config: myConfig);
/// rag.addDocument('My document text');
/// final result = rag.query(queryStruct);
/// ```
class DartBridgeRAG {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeRAG shared = DartBridgeRAG._();

  DartBridgeRAG._();

  // MARK: - State (matches Swift CppBridge.RAG exactly)

  Pointer<Void>? _pipeline; // rac_rag_pipeline_t* (opaque)
  final _logger = SDKLogger('DartBridge.RAG');

  // MARK: - Pipeline Lifecycle

  /// Create the RAG pipeline with configuration.
  ///
  /// [config] - Pointer to a populated RacRagConfigStruct.
  ///
  /// Throws if pipeline creation fails.
  void createPipeline({required Pointer<RacRagConfigStruct> config}) {
    final pipelinePtr = calloc<Pointer<Void>>();
    try {
      final lib = PlatformLoader.loadCommons();
      final createFn = lib.lookupFunction<RacRagPipelineCreateNative,
          RacRagPipelineCreateDart>('rac_rag_pipeline_create');

      final result = createFn(config, pipelinePtr);
      if (result != RAC_SUCCESS || pipelinePtr.value == nullptr) {
        throw StateError(
          'Failed to create RAG pipeline: ${RacResultCode.getMessage(result)}',
        );
      }

      _pipeline = pipelinePtr.value;
      _logger.debug('RAG pipeline created');
    } finally {
      calloc.free(pipelinePtr);
    }
  }

  /// Check if the pipeline has been created.
  bool get isCreated => _pipeline != null;

  /// Destroy the pipeline and release native resources.
  void destroy() {
    final pipeline = _pipeline;
    if (pipeline == null) return;

    try {
      final lib = PlatformLoader.loadCommons();
      final destroyFn = lib.lookupFunction<RacRagPipelineDestroyNative,
          RacRagPipelineDestroyDart>('rac_rag_pipeline_destroy');

      destroyFn(pipeline);
      _pipeline = null;
      _logger.debug('RAG pipeline destroyed');
    } catch (e) {
      _logger.error('Failed to destroy RAG pipeline: $e');
    }
  }

  // MARK: - Document Management

  /// Add a document to the RAG pipeline.
  ///
  /// The document will be split into chunks, embedded, and indexed.
  ///
  /// [text] - Document text content.
  /// [metadataJSON] - Optional JSON metadata string.
  ///
  /// Throws if pipeline is not created or document addition fails.
  void addDocument(String text, {String? metadataJSON}) {
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('RAG pipeline not created. Call createPipeline() first.');
    }

    final textPtr = text.toNativeUtf8();
    final metaPtr = metadataJSON?.toNativeUtf8();

    try {
      final lib = PlatformLoader.loadCommons();
      final addDocFn = lib.lookupFunction<RacRagAddDocumentNative,
          RacRagAddDocumentDart>('rac_rag_add_document');

      final result = addDocFn(
        pipeline,
        textPtr,
        metaPtr ?? nullptr,
      );

      if (result != RAC_SUCCESS) {
        throw StateError(
          'Failed to add document to RAG pipeline: ${RacResultCode.getMessage(result)}',
        );
      }
    } finally {
      calloc.free(textPtr);
      if (metaPtr != null) calloc.free(metaPtr);
    }
  }

  /// Clear all documents from the pipeline.
  ///
  /// Throws if pipeline is not created or clear operation fails.
  void clearDocuments() {
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('RAG pipeline not created. Call createPipeline() first.');
    }

    final lib = PlatformLoader.loadCommons();
    final clearFn = lib.lookupFunction<RacRagClearDocumentsNative,
        RacRagClearDocumentsDart>('rac_rag_clear_documents');

    final result = clearFn(pipeline);
    if (result != RAC_SUCCESS) {
      throw StateError(
        'Failed to clear RAG documents: ${RacResultCode.getMessage(result)}',
      );
    }
  }

  /// Get the number of indexed document chunks.
  ///
  /// Returns 0 if pipeline is not created.
  int get documentCount {
    final pipeline = _pipeline;
    if (pipeline == null) return 0;

    try {
      final lib = PlatformLoader.loadCommons();
      final countFn = lib.lookupFunction<RacRagGetDocumentCountNative,
          RacRagGetDocumentCountDart>('rac_rag_get_document_count');

      return countFn(pipeline);
    } catch (e) {
      _logger.debug('documentCount check failed: $e');
      return 0;
    }
  }

  // MARK: - Query

  /// Query the RAG pipeline.
  ///
  /// Retrieves relevant chunks and generates an answer.
  /// C memory is freed before returning — result is copied into a Dart object.
  ///
  /// [question] - User question string.
  /// [systemPrompt] - Optional system prompt override.
  /// [maxTokens] - Max tokens to generate (default 512).
  /// [temperature] - Sampling temperature (default 0.7).
  /// [topP] - Nucleus sampling (default 0.9).
  /// [topK] - Top-k sampling (default 40).
  ///
  /// Throws if pipeline is not created or query fails.
  RAGBridgeResult query(
    String question, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
  }) {
    final pipeline = _pipeline;
    if (pipeline == null) {
      throw StateError('RAG pipeline not created. Call createPipeline() first.');
    }

    final questionPtr = question.toNativeUtf8();
    final systemPromptPtr = systemPrompt?.toNativeUtf8();
    final queryPtr = calloc<RacRagQueryStruct>();
    final resultPtr = calloc<RacRagResultStruct>();

    final lib = PlatformLoader.loadCommons();
    final queryFn =
        lib.lookupFunction<RacRagQueryNative, RacRagQueryDart>('rac_rag_query');
    final freeFn = lib.lookupFunction<RacRagResultFreeNative,
        RacRagResultFreeDart>('rac_rag_result_free');

    var queryExecuted = false;

    try {
      // Populate query struct
      queryPtr.ref.question = questionPtr;
      queryPtr.ref.systemPrompt = systemPromptPtr ?? nullptr;
      queryPtr.ref.maxTokens = maxTokens;
      queryPtr.ref.temperature = temperature;
      queryPtr.ref.topP = topP;
      queryPtr.ref.topK = topK;

      final status = queryFn(pipeline, queryPtr, resultPtr);
      queryExecuted = true;
      if (status != RAC_SUCCESS) {
        throw StateError(
          'RAG query failed: ${RacResultCode.getMessage(status)}',
        );
      }

      // Copy result data to Dart objects BEFORE freeing
      final dartResult = RAGBridgeResult._fromStruct(resultPtr.ref);

      return dartResult;
    } finally {
      // Free C result memory if query was executed (even if _fromStruct throws)
      if (queryExecuted) {
        freeFn(resultPtr);
      }

      calloc.free(questionPtr);
      if (systemPromptPtr != null) calloc.free(systemPromptPtr);
      calloc.free(queryPtr);
      calloc.free(resultPtr);
    }
  }

  // MARK: - Backend Registration

  /// Register the RAG backend module.
  ///
  /// Must be called before using any RAG functionality.
  /// Returns RAC_SUCCESS (0) on success, error code otherwise.
  static int registerBackend() {
    try {
      final lib = PlatformLoader.loadCommons();
      final registerFn = lib.lookupFunction<RacBackendRagRegisterNative,
          RacBackendRagRegisterDart>('rac_backend_rag_register');

      return registerFn();
    } catch (e) {
      // Graceful degradation if RAG backend is not available
      return RacResultCode.errorModuleNotFound;
    }
  }

  /// Unregister the RAG backend module.
  ///
  /// Returns RAC_SUCCESS (0) on success, error code otherwise.
  static int unregisterBackend() {
    try {
      final lib = PlatformLoader.loadCommons();
      final unregisterFn = lib.lookupFunction<RacBackendRagUnregisterNative,
          RacBackendRagUnregisterDart>('rac_backend_rag_unregister');

      return unregisterFn();
    } catch (e) {
      // Graceful degradation if RAG backend is not available
      return RacResultCode.errorModuleNotFound;
    }
  }
}

// =============================================================================
// Dart-side Result Objects (safe copies of C memory)
// =============================================================================

/// A single retrieved chunk from vector search.
///
/// Safe Dart copy of rac_search_result_t — C memory has already been freed.
class RAGBridgeSearchResult {
  /// Chunk ID
  final String chunkId;

  /// Chunk text content
  final String text;

  /// Cosine similarity score (0.0–1.0)
  final double similarityScore;

  /// JSON metadata (may be empty)
  final String metadataJson;

  const RAGBridgeSearchResult({
    required this.chunkId,
    required this.text,
    required this.similarityScore,
    required this.metadataJson,
  });

  /// Copy fields from a native RacSearchResultStruct.
  factory RAGBridgeSearchResult._fromStruct(RacSearchResultStruct s) {
    return RAGBridgeSearchResult(
      chunkId: s.chunkId != nullptr ? s.chunkId.toDartString() : '',
      text: s.text != nullptr ? s.text.toDartString() : '',
      similarityScore: s.similarityScore,
      metadataJson: s.metadataJson != nullptr ? s.metadataJson.toDartString() : '',
    );
  }

  @override
  String toString() =>
      'RAGBridgeSearchResult(chunkId: $chunkId, score: $similarityScore)';
}

/// The result of a RAG query.
///
/// Safe Dart copy of rac_rag_result_t — C memory has already been freed.
class RAGBridgeResult {
  /// Generated answer text
  final String answer;

  /// Retrieved chunks used as context
  final List<RAGBridgeSearchResult> retrievedChunks;

  /// Full context text sent to the LLM
  final String contextUsed;

  /// Time taken for retrieval phase (ms)
  final double retrievalTimeMs;

  /// Time taken for LLM generation (ms)
  final double generationTimeMs;

  /// Total query time (ms)
  final double totalTimeMs;

  const RAGBridgeResult({
    required this.answer,
    required this.retrievedChunks,
    required this.contextUsed,
    required this.retrievalTimeMs,
    required this.generationTimeMs,
    required this.totalTimeMs,
  });

  /// Copy fields from a native RacRagResultStruct.
  ///
  /// Call this BEFORE freeing the C result with rac_rag_result_free.
  factory RAGBridgeResult._fromStruct(RacRagResultStruct s) {
    final chunks = <RAGBridgeSearchResult>[];

    if (s.retrievedChunks != nullptr && s.numChunks > 0) {
      for (var i = 0; i < s.numChunks; i++) {
        final chunkRef = (s.retrievedChunks + i).ref;
        chunks.add(RAGBridgeSearchResult._fromStruct(chunkRef));
      }
    }

    return RAGBridgeResult(
      answer: s.answer != nullptr ? s.answer.toDartString() : '',
      retrievedChunks: chunks,
      contextUsed: s.contextUsed != nullptr ? s.contextUsed.toDartString() : '',
      retrievalTimeMs: s.retrievalTimeMs,
      generationTimeMs: s.generationTimeMs,
      totalTimeMs: s.totalTimeMs,
    );
  }

  @override
  String toString() =>
      'RAGBridgeResult(answer: ${answer.substring(0, answer.length.clamp(0, 50))}..., '
      'chunks: ${retrievedChunks.length}, totalTimeMs: $totalTimeMs)';
}
