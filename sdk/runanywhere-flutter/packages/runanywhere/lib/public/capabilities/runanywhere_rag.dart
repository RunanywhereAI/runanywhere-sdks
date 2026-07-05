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

import 'dart:convert';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/model_types.pb.dart'
    show ModelInfo, ModelLoadRequest, ModelLoadResult;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show InferenceFramework, ModelCategory;
import 'package:runanywhere/generated/rag.pb.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// RAG (Retrieval-Augmented Generation) capability surface.
///
/// Access via `RunAnywhere.rag`.
class RunAnywhereRAG {
  RunAnywhereRAG._();
  static final RunAnywhereRAG _instance = RunAnywhereRAG._();
  static RunAnywhereRAG get shared => _instance;

  // -- pipeline lifecycle

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

  /// Build a generated RAG configuration from registry models by invoking
  /// commons lifecycle resolution. The resulting config carries model ids;
  /// C++ resolves id -> path during session creation.
  Future<RAGConfiguration> ragResolvedConfiguration({
    required ModelInfo embeddingModel,
    required ModelInfo llmModel,
    RAGConfiguration? baseConfiguration,
  }) async {
    final embedding = await _loadRAGArtifactModel(
      embeddingModel,
      fallbackCategory: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      errorLabel: 'Embedding',
    );
    final llm = await _loadRAGArtifactModel(
      llmModel,
      fallbackCategory: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      errorLabel: 'LLM',
    );
    return (baseConfiguration ?? RAGConfiguration())
        .resolvingLifecycleArtifacts(embedding: embedding, llm: llm);
  }

  /// Create the RAG pipeline from registry models.
  Future<void> ragCreatePipelineForModels({
    required ModelInfo embeddingModel,
    required ModelInfo llmModel,
    RAGConfiguration? baseConfiguration,
  }) async {
    final config = await ragResolvedConfiguration(
      embeddingModel: embeddingModel,
      llmModel: llmModel,
      baseConfiguration: baseConfiguration,
    );
    await createPipeline(config);
  }

  /// Swift-shaped alias for generated-config pipeline creation.
  Future<void> ragCreatePipeline(RAGConfiguration config) =>
      createPipeline(config);

  /// Destroy the RAG pipeline and release native resources.
  Future<void> destroyPipeline() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    DartBridgeRAG.shared.destroyPipeline();
  }

  /// Swift-shaped alias for pipeline destruction.
  Future<void> ragDestroyPipeline() => destroyPipeline();

  // -- document management

  /// Ingest a single document into the pipeline (chunk → embed → index).
  Future<void> ingest(String text, {String? metadataJSON}) async {
    await ragIngest(
      RAGDocument(text: text, metadata: _parseMetadataJSON(metadataJSON).entries),
    );
  }

  /// Ingest a generated-proto document through the C++ RAG ABI.
  Future<RAGStatistics> ragIngest(RAGDocument document) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }

    try {
      return await DartBridgeRAG.shared.ingestDocumentAsync(document);
    } catch (e) {
      throw SDKException.invalidState('RAG ingestion failed: $e');
    }
  }

  /// Ingest multiple documents in batch. Each map needs a `text` key
  /// and optionally a `metadataJson` key.
  Future<void> addDocumentsBatch(List<Map<String, String>> documents) async {
    await ragAddDocumentsBatch(
      documents
          .map((doc) => RAGDocument(
                text: doc['text'] ?? '',
                metadata: _parseMetadataJSON(doc['metadataJson']).entries,
              ))
          .toList(),
    );
  }

  /// Ingest multiple generated-proto documents.
  Future<void> ragAddDocumentsBatch(List<RAGDocument> documents) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (documents.isEmpty) return;

    try {
      for (final document in documents) {
        await DartBridgeRAG.shared.ingestDocumentAsync(document);
      }
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

  /// Swift-shaped alias for clearing documents.
  Future<void> ragClearDocuments() => clearDocuments();

  // -- retrieval & stats

  /// Number of indexed document chunks in the pipeline.
  Future<int> documentCount() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeRAG.shared.documentCount;
  }

  /// Canonical function-form document count.
  Future<int> ragGetDocumentCount() => documentCount();

  /// Convenience async getter matching Swift `ragDocumentCount`.
  Future<int> get ragDocumentCount => ragGetDocumentCount();

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

  /// Swift-shaped alias for statistics.
  Future<RAGStatistics> ragGetStatistics() => getStatistics();

  // -- query

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
      final effectiveOptions = RAGQueryOptions();
      if (options != null) {
        effectiveOptions.mergeFromMessage(options);
      }
      if (effectiveOptions.question.isEmpty) {
        effectiveOptions.question = question;
      }

      return await ragQuery(effectiveOptions);
    } catch (e) {
      throw SDKException.generationFailed('RAG query failed: $e');
    }
  }

  /// Query through the generated-proto C++ RAG ABI.
  Future<RAGResult> ragQuery(RAGQueryOptions options) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    return DartBridgeRAG.shared.queryAsync(options);
  }

  Future<ModelLoadResult> _loadRAGArtifactModel(
    ModelInfo model, {
    required ModelCategory fallbackCategory,
    required String errorLabel,
  }) async {
    final request = ModelLoadRequest(
      modelId: model.id,
      category: model.category == ModelCategory.MODEL_CATEGORY_UNSPECIFIED
          ? fallbackCategory
          : model.category,
      framework:
          model.framework != InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED
              ? model.framework
              : null,
    );
    final result = await RunAnywhereModelLifecycle.shared.load(request);
    if (!result.success) {
      final message = result.errorMessage.isNotEmpty
          ? result.errorMessage
          : '$errorLabel model lifecycle artifact resolution failed';
      throw SDKException.modelLoadFailed(model.id, message);
    }
    return result;
  }
}

extension RAGConfigurationResolvedArtifacts on RAGConfiguration {
  /// D-6 parity: lifecycle results prove the models were registered/resolved;
  /// the RAG session config itself carries model ids for commons to resolve.
  RAGConfiguration resolvingLifecycleArtifacts({
    required ModelLoadResult embedding,
    required ModelLoadResult llm,
  }) {
    return RAGConfiguration()
      ..mergeFromMessage(this)
      ..embeddingModelId = embedding.modelId
      ..llmModelId = llm.modelId;
  }
}

extension RAGDocumentConvenience on RAGDocument {
  static RAGDocument fromText(String text, {String? metadataJSON}) {
    return RAGDocument(text: text, metadata: _parseMetadataJSON(metadataJSON).entries);
  }
}

extension RAGQueryOptionsConvenience on RAGQueryOptions {
  static RAGQueryOptions defaultsForQuestion(String question) {
    return RAGQueryOptions(question: question);
  }
}

extension RAGResultTimeConvenience on RAGResult {
  Duration get totalTime => Duration(milliseconds: totalTimeMs.toInt());
}

extension RAGStatisticsTimeConvenience on RAGStatistics {
  DateTime? get lastUpdated {
    final millis = lastUpdatedMs.toInt();
    return millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
  }
}

Map<String, String> _parseMetadataJSON(String? json) {
  if (json == null || json.isEmpty) return const <String, String>{};
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const <String, String>{};
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  } catch (_) {
    return const <String, String>{};
  }
}
