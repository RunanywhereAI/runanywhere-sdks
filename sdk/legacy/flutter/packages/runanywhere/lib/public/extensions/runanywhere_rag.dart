/// RunAnywhere + RAG
///
/// Public API for Retrieval-Augmented Generation (RAG) pipeline operations.
/// Mirrors Swift's RunAnywhere+RAG.swift extension pattern.
///
/// Developer-facing API surface for RAG. All methods wrap DartBridgeRAG calls
/// with initialization guards, event publishing, and typed error conversion.
library runanywhere_rag;

import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
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
  /// Passes [config] to the C++ bridge which handles JSON parsing, model path
  /// resolution, and pipeline creation. Publishes [SDKRAGEvent.pipelineCreated].
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  /// Throws [SDKError.invalidState] if pipeline creation fails.
  static Future<void> ragCreatePipeline(RAGConfiguration config) async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    try {
      await DartBridgeRAG.shared.createPipelineAsync(config);

      EventBus.shared.publish(SDKRAGEvent.pipelineCreated());
    } catch (e) {
      EventBus.shared.publish(SDKRAGEvent.error(message: e.toString()));
      throw SDKError.invalidState('RAG pipeline creation failed: $e');
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

    DartBridgeRAG.shared.destroyPipeline();
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
      await DartBridgeRAG.shared.addDocumentAsync(text, metadataJson: metadataJSON);

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

  /// Ingest multiple documents in batch.
  ///
  /// More efficient than calling [ragIngest] multiple times.
  /// Publishes [SDKRAGEvent.ingestionStarted] before and
  /// [SDKRAGEvent.ingestionComplete] after the operation.
  ///
  /// [documents] - List of document maps with 'text' and optional 'metadataJson' keys.
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  /// Throws [SDKError.invalidState] if batch ingestion fails.
  static Future<void> ragAddDocumentsBatch(
      List<Map<String, String>> documents) async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    final totalLength =
        documents.fold<int>(0, (sum, d) => sum + (d['text']?.length ?? 0));

    EventBus.shared.publish(
      SDKRAGEvent.ingestionStarted(documentLength: totalLength),
    );

    final stopwatch = Stopwatch()..start();

    try {
      await DartBridgeRAG.shared.addDocumentsBatchAsync(documents);

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
      throw SDKError.invalidState('RAG batch ingestion failed: $e');
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

  /// Get pipeline statistics.
  ///
  /// Returns a [RAGStatistics] with the raw JSON from the C pipeline.
  ///
  /// Throws [SDKError.notInitialized] if SDK is not initialized.
  /// Throws [SDKError.invalidState] if statistics retrieval fails.
  static Future<RAGStatistics> ragGetStatistics() async {
    if (!RunAnywhere.isSDKInitialized) {
      throw SDKError.notInitialized();
    }

    try {
      return DartBridgeRAG.shared.getStatistics();
    } catch (e) {
      throw SDKError.invalidState('RAG get statistics failed: $e');
    }
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
      final queryOptions = options ?? RAGQueryOptions(question: question);

      // If caller provided options but with a different question field,
      // create a new options with the positional question.
      final effectiveOptions = queryOptions.question == question
          ? queryOptions
          : RAGQueryOptions(
              question: question,
              systemPrompt: queryOptions.systemPrompt,
              maxTokens: queryOptions.maxTokens,
              temperature: queryOptions.temperature,
              topP: queryOptions.topP,
              topK: queryOptions.topK,
            );

      final result = await DartBridgeRAG.shared.queryAsync(effectiveOptions);

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
