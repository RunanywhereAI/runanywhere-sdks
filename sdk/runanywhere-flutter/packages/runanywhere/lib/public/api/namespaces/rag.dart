// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.rag` — retrieval-augmented generation as a session object.

import 'dart:async';

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/rag.pb.dart' as rag_pb;
import 'package:runanywhere/generated/rag.pbenum.dart'
    show RAGStreamEventKind;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';

/// Retrieval-augmented generation sessions.
class RagApi {
  /// Bind the namespace. Reach it through `RunAnywhere.rag`.
  const RagApi();

  /// Open a session over [embeddingModel], optionally generating with
  /// [llmModel].
  ///
  /// ```dart
  /// final s = await RunAnywhere.rag.open(embeddingModel: ModelRef('minilm'));
  /// await s.ingest(const RagDocument('the sky is blue'));
  /// ```
  ///
  /// Throws [SDKException] when a model cannot be loaded or the index cannot
  /// be created.
  Future<RagSession> open({
    required ModelRef embeddingModel,
    ModelRef? llmModel,
    RagConfig? config,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();
    // The RAG backend registers itself here so callers never do backend wiring.
    DartBridgeRAG.shared.register();
    await ModelGate.ensureLoaded(
      modelId: embeddingModel.id,
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    );
    if (llmModel != null) {
      await ModelGate.ensureLoaded(
        modelId: llmModel.id,
        category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      );
    }

    final effective = config ?? RagConfig();
    try {
      await DartBridgeRAG.shared.createPipelineAsync(
        effective.toProto(
          embeddingModelId: embeddingModel.id,
          llmModelId: llmModel?.id,
        ),
      );
    } catch (error) {
      throw SDKException.invalidState('RAG session creation failed: $error');
    }
    return RagSession._(effective, generates: llmModel != null);
  }
}

/// One RAG corpus with its index.
///
/// The Flutter RAG bridge owns a single native session, so opening a new
/// session supersedes any earlier one; calls on a superseded session throw.
class RagSession {
  RagSession._(this._config, {required this.generates}) {
    _active = this;
  }

  static RagSession? _active;

  final RagConfig _config;

  /// True when the session was opened with an LLM and can answer questions.
  final bool generates;

  bool _closed = false;

  /// Index [document] into the corpus.
  ///
  /// Throws [SDKException] when the session is closed or ingestion fails.
  Future<void> ingest(RagDocument document) async {
    _requireLive();
    try {
      await DartBridgeRAG.shared.ingestDocumentAsync(_toProto(document));
    } catch (error) {
      throw SDKException.invalidState('RAG ingestion failed: $error');
    }
  }

  /// Index every document in [documents].
  ///
  /// Throws [SDKException] when the session is closed or ingestion fails.
  Future<void> ingestAll(List<RagDocument> documents) async {
    for (final document in documents) {
      await ingest(document);
    }
  }

  /// Retrieve the chunks closest to [query] without generating an answer.
  ///
  /// Throws [SDKException] when the session is closed or retrieval fails.
  Future<List<Match>> search(String query, {int? topK}) async {
    _requireLive();
    // Commons publishes no retrieval-only verb: the query verb is asked for a
    // single output token so the retrieval half is all that costs anything.
    final result = await DartBridgeRAG.shared.queryAsync(
      _queryOptions(query, LlmOptions(maxOutputTokens: 1), topK: topK),
    );
    if (result.hasError()) {
      throw SDKException.processingFailed(result.error.message);
    }
    return List<Match>.unmodifiable(
      result.retrievedChunks.map(Match.fromProto),
    );
  }

  /// Answer [question] from the corpus.
  ///
  /// Throws [SDKException] when the session is closed, has no LLM, or
  /// generation fails.
  Future<RagResult> query(String question, {LlmOptions? options}) async {
    _requireLive();
    _requireGeneration();
    final result = await DartBridgeRAG.shared.queryAsync(
      _queryOptions(question, options),
    );
    if (result.hasError()) {
      throw SDKException.generationFailed(result.error.message);
    }
    return RagResult.fromProto(result);
  }

  /// Answer [question], emitting retrieved chunks then answer tokens.
  ///
  /// Throws [SDKException] into the consumer when the query fails.
  Stream<RagEvent> queryStream(
    String question, {
    LlmOptions? options,
  }) async* {
    _requireLive();
    _requireGeneration();
    final retrieved = <Match>[];
    await for (final event in DartBridgeRAG.shared.queryStream(
      _queryOptions(question, options),
    )) {
      switch (event.kind) {
        case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED:
          if (event.hasChunk()) {
            retrieved.add(Match.fromProto(event.chunk));
          }
        case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_CONTEXT_READY:
          yield RagRetrieved(List<Match>.unmodifiable(retrieved));
        case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_TOKEN:
          if (event.token.isNotEmpty) {
            yield RagToken(event.token);
          }
        case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_COMPLETED:
          if (event.hasResult()) {
            yield RagCompleted(RagResult.fromProto(event.result));
          }
        case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_ERROR:
          throw SDKException.generationFailed(
            event.hasError() && event.error.message.isNotEmpty
                ? event.error.message
                : 'RAG query failed',
          );
        case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED:
        case RAGStreamEventKind.RAG_STREAM_EVENT_KIND_UNSPECIFIED:
          break;
      }
    }
  }

  /// Document, chunk, and index-size counts.
  ///
  /// Throws [SDKException] when the session is closed.
  Future<RagStats> stats() async {
    _requireLive();
    return RagStats.fromProto(DartBridgeRAG.shared.getStatistics());
  }

  /// Drop every document from the corpus, keeping the session open.
  ///
  /// Throws [SDKException] when the session is closed.
  Future<void> clear() async {
    _requireLive();
    DartBridgeRAG.shared.clearDocuments();
  }

  /// Destroy the index and release native resources.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(_active, this)) {
      DartBridgeRAG.shared.destroyPipeline();
      _active = null;
    }
  }

  rag_pb.RAGQueryOptions _queryOptions(
    String question,
    LlmOptions? options, {
    int? topK,
  }) {
    final proto = rag_pb.RAGQueryOptions(
      question: question,
      retrievalTopK: topK ?? _config.topK,
    );
    final threshold = _config.similarityThreshold;
    if (threshold != null) proto.similarityThreshold = threshold;
    if (options != null) proto.generation = options.toProto();
    return proto;
  }

  rag_pb.RAGDocument _toProto(RagDocument document) {
    final proto = rag_pb.RAGDocument(text: document.text);
    final metadata = document.metadata;
    if (metadata != null) proto.metadata.addAll(metadata);
    final source = document.sourceUri;
    if (source != null) proto.sourceUri = source;
    return proto;
  }

  void _requireLive() {
    if (_closed || !identical(_active, this)) {
      throw SDKException.invalidState('RAG session is closed');
    }
  }

  void _requireGeneration() {
    if (!generates) {
      throw SDKException.invalidState(
        'RAG session was opened for retrieval only; pass llmModel to generate',
      );
    }
  }
}
