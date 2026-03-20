/// DartBridge+RAG
///
/// RAG pipeline bridge - manages C++ RAG pipeline lifecycle.
/// Mirrors Swift's CppBridge+RAG.swift pattern.
library dart_bridge_rag;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

// =============================================================================
// Bridge-internal types (prefixed RAGBridge* to avoid conflict with public
// rag_types.dart which defines the developer-facing RAGConfiguration etc.)
// =============================================================================

/// Internal bridge type for a retrieved document chunk.
class RAGBridgeSearchResult {
  final String chunkId;
  final String text;
  final double similarityScore;
  final String metadataJson;

  const RAGBridgeSearchResult({
    required this.chunkId,
    required this.text,
    required this.similarityScore,
    required this.metadataJson,
  });
}

/// Internal bridge type for a RAG query result.
class RAGBridgeResult {
  final String answer;
  final List<RAGBridgeSearchResult> retrievedChunks;
  final String contextUsed;
  final double retrievalTimeMs;
  final double generationTimeMs;
  final double totalTimeMs;

  const RAGBridgeResult({
    required this.answer,
    required this.retrievedChunks,
    required this.contextUsed,
    required this.retrievalTimeMs,
    required this.generationTimeMs,
    required this.totalTimeMs,
  });
}

// =============================================================================
// DartBridgeRAG — FFI bridge to rac_rag_pipeline_* C API
// =============================================================================

/// RAG pipeline bridge for C++ interop.
class DartBridgeRAG {
  static final DartBridgeRAG shared = DartBridgeRAG._();

  DartBridgeRAG._();

  final _logger = SDKLogger('DartBridge.RAG');
  Pointer<Void>? _pipeline;

  bool get isCreated => _pipeline != null;

  // ---------------------------------------------------------------------------
  // Static registration helpers (called by RAGModule)
  // ---------------------------------------------------------------------------

  /// Register the RAG backend with the C++ service registry.
  static int registerBackend() {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<RacBackendRagRegisterNative,
          RacBackendRagRegisterDart>('rac_backend_rag_register');
      return fn();
    } catch (e) {
      return RacResultCode.errorBackendNotFound;
    }
  }

  /// Unregister the RAG backend from the C++ service registry.
  static int unregisterBackend() {
    try {
      final lib = PlatformLoader.loadCommons();
      final fn = lib.lookupFunction<RacBackendRagUnregisterNative,
          RacBackendRagUnregisterDart>('rac_backend_rag_unregister');
      return fn();
    } catch (e) {
      return RacResultCode.errorBackendNotFound;
    }
  }

  // ---------------------------------------------------------------------------
  // Pipeline lifecycle
  // ---------------------------------------------------------------------------

  /// Create a RAG pipeline from a pre-filled [RacRagConfigStruct] pointer.
  ///
  /// Used by [RunAnywhereRAG.ragCreatePipeline] which marshals the Dart
  /// [RAGConfiguration] into the struct before calling this method.
  void createPipeline({required Pointer<RacRagConfigStruct> config}) {
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<RacRagPipelineCreateNative,
        RacRagPipelineCreateDart>('rac_rag_pipeline_create');

    final outPipeline = calloc<Pointer<Void>>();
    try {
      final result = fn(config, outPipeline);
      if (result != RAC_SUCCESS || outPipeline.value == nullptr) {
        throw Exception('Failed to create RAG pipeline: error $result');
      }
      if (_pipeline != null) destroy();
      _pipeline = outPipeline.value;
      _logger.debug('RAG pipeline created');
    } finally {
      calloc.free(outPipeline);
    }
  }

  /// Destroy the RAG pipeline and release native resources.
  void destroy() {
    if (_pipeline == null) return;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<RacRagPipelineDestroyNative,
        RacRagPipelineDestroyDart>('rac_rag_pipeline_destroy');
    fn(_pipeline!);
    _pipeline = null;
    _logger.debug('RAG pipeline destroyed');
  }

  // ---------------------------------------------------------------------------
  // Document management
  // ---------------------------------------------------------------------------

  /// Add a document to the pipeline.
  void addDocument(String text, {String? metadataJSON}) {
    _ensurePipeline();
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<RacRagAddDocumentNative,
        RacRagAddDocumentDart>('rac_rag_add_document');

    final cText = text.toNativeUtf8();
    final cMeta =
        metadataJSON != null ? metadataJSON.toNativeUtf8() : nullptr;
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
    final fn = lib.lookupFunction<RacRagClearDocumentsNative,
        RacRagClearDocumentsDart>('rac_rag_clear_documents');
    fn(_pipeline!);
  }

  /// Number of indexed document chunks.
  int get documentCount {
    if (_pipeline == null) return 0;
    final lib = PlatformLoader.loadCommons();
    final fn = lib.lookupFunction<RacRagGetDocumentCountNative,
        RacRagGetDocumentCountDart>('rac_rag_get_document_count');
    return fn(_pipeline!);
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Query the RAG pipeline with individual parameters.
  ///
  /// Returns a [RAGBridgeResult] that callers (e.g. [RunAnywhereRAG]) convert
  /// to the public [RAGResult] via [RAGResult.fromBridge].
  RAGBridgeResult query(
    String question, {
    String? systemPrompt,
    int maxTokens = 512,
    double temperature = 0.7,
    double topP = 0.9,
    int topK = 40,
  }) {
    _ensurePipeline();
    final lib = PlatformLoader.loadCommons();
    final queryFn = lib.lookupFunction<RacRagQueryNative, RacRagQueryDart>(
        'rac_rag_query');
    final freeFn = lib.lookupFunction<RacRagResultFreeNative,
        RacRagResultFreeDart>('rac_rag_result_free');

    final cQuery = calloc<RacRagQueryStruct>();
    final cResult = calloc<RacRagResultStruct>();

    try {
      cQuery.ref.question = question.toNativeUtf8();
      cQuery.ref.systemPrompt =
          systemPrompt != null ? systemPrompt.toNativeUtf8() : nullptr;
      cQuery.ref.maxTokens = maxTokens;
      cQuery.ref.temperature = temperature;
      cQuery.ref.topP = topP;
      cQuery.ref.topK = topK;

      final status = queryFn(_pipeline!, cQuery, cResult);
      if (status != RAC_SUCCESS) {
        throw Exception('RAG query failed: error $status');
      }

      final answer =
          cResult.ref.answer != nullptr ? cResult.ref.answer.toDartString() : '';
      final contextUsed = cResult.ref.contextUsed != nullptr
          ? cResult.ref.contextUsed.toDartString()
          : '';

      final chunks = <RAGBridgeSearchResult>[];
      for (int i = 0; i < cResult.ref.numChunks; i++) {
        final c = cResult.ref.retrievedChunks[i];
        chunks.add(RAGBridgeSearchResult(
          chunkId: c.chunkId != nullptr ? c.chunkId.toDartString() : '',
          text: c.text != nullptr ? c.text.toDartString() : '',
          similarityScore: c.similarityScore,
          metadataJson:
              c.metadataJson != nullptr ? c.metadataJson.toDartString() : '',
        ));
      }

      final result = RAGBridgeResult(
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
