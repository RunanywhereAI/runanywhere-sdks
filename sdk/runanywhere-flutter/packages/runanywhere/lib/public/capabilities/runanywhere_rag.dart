// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_rag.dart — v4 RAG (Retrieval-Augmented Generation)
// capability. Owns pipeline lifecycle, document management,
// statistics, and querying. Mirrors Swift `RunAnywhere+RAG.swift`.

import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/generated/rag.pb.dart';
import 'package:runanywhere/internal/sdk_event_factories.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';
import 'package:runanywhere/public/events/event_bus.dart';

/// RAG (Retrieval-Augmented Generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.rag`.
class RunAnywhereRAG {
  RunAnywhereRAG._();
  static final RunAnywhereRAG _instance = RunAnywhereRAG._();
  static RunAnywhereRAG get shared => _instance;

  // -- pipeline lifecycle ---------------------------------------------------

  /// Create the RAG pipeline. Throws `SDKError.invalidState` if
  /// creation fails. Publishes a generated RAG SDKEvent on success.
  Future<void> createPipeline(RAGConfiguration config) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    try {
      await DartBridgeRAG.shared.createPipelineAsync(config);
      EventBus.shared.publish(SdkEventFactory.ragPipelineCreated());
    } catch (e) {
      EventBus.shared.publish(SdkEventFactory.ragFailed(e));
      throw SDKException.invalidState('RAG pipeline creation failed: $e');
    }
  }

  /// Destroy the RAG pipeline and release native resources.
  Future<void> destroyPipeline() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeRAG.shared.destroyPipeline();
    EventBus.shared.publish(SdkEventFactory.ragPipelineDestroyed());
  }

  // -- document management --------------------------------------------------

  /// Ingest a single document into the pipeline (chunk → embed → index).
  Future<void> ingest(String text, {String? metadataJSON}) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    EventBus.shared.publish(
      SdkEventFactory.ragIngestionStarted(text.length),
    );

    final stopwatch = Stopwatch()..start();

    try {
      await DartBridgeRAG.shared
          .addDocumentAsync(text, metadataJson: metadataJSON);
      stopwatch.stop();

      final chunkCount = DartBridgeRAG.shared.documentCount;
      EventBus.shared.publish(
        SdkEventFactory.ragIngestionCompleted(
          chunkCount: chunkCount,
          durationMs: stopwatch.elapsedMilliseconds.toDouble(),
        ),
      );
    } catch (e) {
      stopwatch.stop();
      EventBus.shared.publish(SdkEventFactory.ragFailed(e));
      throw SDKException.invalidState('RAG ingestion failed: $e');
    }
  }

  /// Ingest multiple documents in batch. Each map needs a `text` key
  /// and optionally a `metadataJson` key.
  Future<void> addDocumentsBatch(List<Map<String, String>> documents) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    final totalLength =
        documents.fold<int>(0, (sum, d) => sum + (d['text']?.length ?? 0));

    EventBus.shared.publish(
      SdkEventFactory.ragIngestionStarted(totalLength),
    );

    final stopwatch = Stopwatch()..start();

    try {
      await DartBridgeRAG.shared.addDocumentsBatchAsync(documents);
      stopwatch.stop();

      final chunkCount = DartBridgeRAG.shared.documentCount;
      EventBus.shared.publish(
        SdkEventFactory.ragIngestionCompleted(
          chunkCount: chunkCount,
          durationMs: stopwatch.elapsedMilliseconds.toDouble(),
        ),
      );
    } catch (e) {
      stopwatch.stop();
      EventBus.shared.publish(SdkEventFactory.ragFailed(e));
      throw SDKException.invalidState('RAG batch ingestion failed: $e');
    }
  }

  /// Clear every document from the pipeline.
  Future<void> clearDocuments() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    try {
      DartBridgeRAG.shared.clearDocuments();
    } catch (e) {
      throw SDKException.invalidState('RAG clear documents failed: $e');
    }
  }

  // -- retrieval & stats ----------------------------------------------------

  /// Number of indexed document chunks in the pipeline.
  Future<int> documentCount() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeRAG.shared.documentCount;
  }

  /// Pipeline statistics (raw JSON from the C pipeline).
  Future<RAGStatistics> getStatistics() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    try {
      return DartBridgeRAG.shared.getStatistics();
    } catch (e) {
      throw SDKException.invalidState('RAG get statistics failed: $e');
    }
  }

  // -- query ----------------------------------------------------------------

  /// Query the RAG pipeline with a natural-language question —
  /// retrieves relevant chunks and generates an answer.
  Future<RAGResult> query(
    String question, {
    RAGQueryOptions? options,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    EventBus.shared.publish(
      SdkEventFactory.ragQueryStarted(question.length),
    );

    try {
      final queryOptions = options ?? RAGQueryOptions(question: question);

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
        SdkEventFactory.ragQueryCompleted(
          answerLength: result.answer.length,
          chunksRetrieved: result.retrievedChunks.length,
          retrievalTimeMs: result.retrievalTimeMs.toDouble(),
          generationTimeMs: result.generationTimeMs.toDouble(),
          totalTimeMs: result.totalTimeMs.toDouble(),
        ),
      );

      return result;
    } catch (e) {
      EventBus.shared.publish(SdkEventFactory.ragFailed(e));
      throw SDKException.generationFailed('RAG query failed: $e');
    }
  }
}
