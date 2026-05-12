// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_rag.dart — v4 RAG (Retrieval-Augmented Generation)
// capability. Owns pipeline lifecycle, document management,
// statistics, and querying. Mirrors Swift `RunAnywhere+RAG.swift`.
//
// Note: All RAG SDKEvents are auto-published by C++ commons
// (rac_rag_proto_abi.cpp). Dart does not re-emit duplicates;
// consumers subscribe via `EventBus.shared.stream` which surfaces
// commons-emitted events through `rac_sdk_event_subscribe`.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/rag.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';

/// RAG (Retrieval-Augmented Generation) capability surface.
///
/// Access via `RunAnywhereSDK.instance.rag`.
class RunAnywhereRAG {
  RunAnywhereRAG._();
  static final RunAnywhereRAG _instance = RunAnywhereRAG._();
  static RunAnywhereRAG get shared => _instance;

  // -- pipeline lifecycle ---------------------------------------------------

  /// Create the RAG pipeline. Throws `SDKError.invalidState` if
  /// creation fails. C++ commons auto-publishes the RAG SDKEvent.
  Future<void> createPipeline(RAGConfiguration config) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    try {
      await DartBridgeRAG.shared.createPipelineAsync(config);
    } catch (e) {
      throw SDKException.invalidState('RAG pipeline creation failed: $e');
    }
  }

  /// Destroy the RAG pipeline and release native resources.
  Future<void> destroyPipeline() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeRAG.shared.destroyPipeline();
  }

  // -- document management --------------------------------------------------

  /// Ingest a single document into the pipeline (chunk → embed → index).
  Future<void> ingest(String text, {String? metadataJSON}) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    try {
      await DartBridgeRAG.shared
          .addDocumentAsync(text, metadataJson: metadataJSON);
    } catch (e) {
      throw SDKException.invalidState('RAG ingestion failed: $e');
    }
  }

  /// Ingest multiple documents in batch. Each map needs a `text` key
  /// and optionally a `metadataJson` key.
  Future<void> addDocumentsBatch(List<Map<String, String>> documents) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    try {
      await DartBridgeRAG.shared.addDocumentsBatchAsync(documents);
    } catch (e) {
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

      return await DartBridgeRAG.shared.queryAsync(effectiveOptions);
    } catch (e) {
      throw SDKException.generationFailed('RAG query failed: $e');
    }
  }
}
