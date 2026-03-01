/// RunAnywhere + RAG
///
/// Public API for Retrieval-Augmented Generation (RAG) pipeline operations.
/// Mirrors Swift's RunAnywhere+RAG.swift extension pattern.
///
/// Developer-facing API surface for RAG. All methods wrap DartBridgeRAG calls
/// with initialization guards, event publishing, and typed error conversion.
library runanywhere_rag;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/extensions/rag_module.dart';
import 'package:runanywhere/public/runanywhere.dart';
import 'package:runanywhere/public/types/rag_types.dart';

// =============================================================================
// RAG Extension Methods
// =============================================================================

/// Extension providing static RAG pipeline methods on RunAnywhere.
///
/// All methods check SDK initialization before proceeding, publish lifecycle
/// events to EventBus, and convert bridge errors to typed SDKError exceptions.
///
/// Usage:
/// ```dart
/// await RunAnywhereRAG.ragCreatePipeline(config);
/// await RunAnywhereRAG.ragIngest(text);
/// final result = await RunAnywhereRAG.ragQuery(question);
/// await RunAnywhereRAG.ragDestroyPipeline();
/// ```
extension RunAnywhereRAG on RunAnywhere {
  // MARK: - Pipeline Lifecycle

  /// Create the RAG pipeline with the given configuration.
  ///
  /// Marshals [config] to a native [RacRagConfigStruct] via FFI, calls
  /// [DartBridgeRAG.createPipeline], then publishes [SDKRAGEvent.pipelineCreated].
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  /// Throws [SDKError.invalidState] if pipeline creation fails.
  static Future<void> ragCreatePipeline(RAGConfiguration config) async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    if (!RAGModule.isRegistered) {
      throw SDKError.invalidState(
        'RAG backend not registered. Call RAGModule.register() first.',
      );
    }

    final embeddingModelPathPtr = config.embeddingModelPath.toNativeUtf8();
    final llmModelPathPtr = config.llmModelPath.toNativeUtf8();
    final promptTemplatePtr = config.promptTemplate?.toNativeUtf8();
    final embeddingConfigJsonPtr = config.embeddingConfigJSON?.toNativeUtf8();
    final llmConfigJsonPtr = config.llmConfigJSON?.toNativeUtf8();
    final configPtr = calloc<RacRagConfigStruct>();

    try {
      configPtr.ref.embeddingModelPath = embeddingModelPathPtr;
      configPtr.ref.llmModelPath = llmModelPathPtr;
      configPtr.ref.embeddingDimension = config.embeddingDimension;
      configPtr.ref.topK = config.topK;
      configPtr.ref.similarityThreshold = config.similarityThreshold;
      configPtr.ref.maxContextTokens = config.maxContextTokens;
      configPtr.ref.chunkSize = config.chunkSize;
      configPtr.ref.chunkOverlap = config.chunkOverlap;
      configPtr.ref.promptTemplate = promptTemplatePtr ?? nullptr;
      configPtr.ref.embeddingConfigJson = embeddingConfigJsonPtr ?? nullptr;
      configPtr.ref.llmConfigJson = llmConfigJsonPtr ?? nullptr;

      DartBridgeRAG.shared.createPipeline(config: configPtr);

      EventBus.shared.publish(SDKRAGEvent.pipelineCreated());
    } catch (e) {
      EventBus.shared.publish(SDKRAGEvent.error(message: e.toString()));
      throw SDKError.invalidState('RAG pipeline creation failed: $e');
    } finally {
      calloc.free(embeddingModelPathPtr);
      calloc.free(llmModelPathPtr);
      if (promptTemplatePtr != null) calloc.free(promptTemplatePtr);
      if (embeddingConfigJsonPtr != null) calloc.free(embeddingConfigJsonPtr);
      if (llmConfigJsonPtr != null) calloc.free(llmConfigJsonPtr);
      calloc.free(configPtr);
    }
  }

  /// Destroy the RAG pipeline and release native resources.
  ///
  /// Publishes [SDKRAGEvent.pipelineDestroyed] after destruction.
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  static Future<void> ragDestroyPipeline() async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    DartBridgeRAG.shared.destroy();
    EventBus.shared.publish(SDKRAGEvent.pipelineDestroyed());
  }

  // MARK: - Document Management

  /// Ingest a document into the RAG pipeline.
  ///
  /// Splits [text] into chunks, embeds them, and indexes them for retrieval.
  /// Publishes [SDKRAGEvent.ingestionStarted] before and
  /// [SDKRAGEvent.ingestionComplete] after the operation.
  ///
  /// [text] - Document text content to ingest.
  /// [metadataJSON] - Optional JSON metadata string to associate with the document.
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  /// Throws [SDKError.invalidState] if ingestion fails.
  static Future<void> ragIngest(String text, {String? metadataJSON}) async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    EventBus.shared.publish(
      SDKRAGEvent.ingestionStarted(documentLength: text.length),
    );

    final stopwatch = Stopwatch()..start();

    try {
      DartBridgeRAG.shared.addDocument(text, metadataJSON: metadataJSON);

      stopwatch.stop();

      final chunkCount = DartBridgeRAG.shared.documentCount;

      EventBus.shared.publish(
        SDKRAGEvent.ingestionComplete(
          chunkCount: chunkCount,
          durationMs: stopwatch.elapsedMilliseconds.toDouble(),
        ),
      );
    } catch (e) {
      stopwatch.stop();
      EventBus.shared.publish(SDKRAGEvent.error(message: e.toString()));
      throw SDKError.invalidState('RAG ingestion failed: $e');
    }
  }

  /// Clear all documents from the RAG pipeline.
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  /// Throws [SDKError.invalidState] if clearing fails.
  static Future<void> ragClearDocuments() async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    try {
      DartBridgeRAG.shared.clearDocuments();
    } catch (e) {
      throw SDKError.invalidState('RAG clear documents failed: $e');
    }
  }

  // MARK: - Retrieval

  /// Get the number of indexed document chunks in the pipeline.
  ///
  /// Returns 0 if the pipeline has not been created.
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  static Future<int> ragDocumentCount() async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    return DartBridgeRAG.shared.documentCount;
  }

  // MARK: - Query

  /// Query the RAG pipeline with a natural language question.
  ///
  /// Retrieves relevant document chunks and generates an AI answer.
  /// Publishes [SDKRAGEvent.queryStarted] before and
  /// [SDKRAGEvent.queryComplete] after the operation.
  ///
  /// [question] - The user's natural language question.
  /// [options] - Optional query parameters (system prompt, token limits, etc.).
  ///
  /// Returns a [RAGResult] with the generated answer, retrieved chunks, and timing.
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  /// Throws [SDKError.generationFailed] if the query fails.
  static Future<RAGResult> ragQuery(
    String question, {
    RAGQueryOptions? options,
  }) async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    EventBus.shared.publish(
      SDKRAGEvent.queryStarted(questionLength: question.length),
    );

    try {
      final bridgeResult = DartBridgeRAG.shared.query(
        question,
        systemPrompt: options?.systemPrompt,
        maxTokens: options?.maxTokens ?? 512,
        temperature: options?.temperature ?? 0.7,
        topP: options?.topP ?? 0.9,
        topK: options?.topK ?? 40,
      );

      final result = RAGResult.fromBridge(bridgeResult);

      EventBus.shared.publish(
        SDKRAGEvent.queryComplete(
          answerLength: result.answer.length,
          chunksRetrieved: result.retrievedChunks.length,
          retrievalTimeMs: result.retrievalTimeMs,
          generationTimeMs: result.generationTimeMs,
          totalTimeMs: result.totalTimeMs,
        ),
      );

      return result;
    } catch (e) {
      EventBus.shared.publish(SDKRAGEvent.error(message: e.toString()));
      throw SDKError.generationFailed('RAG query failed: $e');
    }
  }
}
