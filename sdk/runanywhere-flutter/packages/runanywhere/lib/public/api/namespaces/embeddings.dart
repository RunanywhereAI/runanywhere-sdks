// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.embeddings` and `RunAnywhere.rerank`.

import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/embeddings_options.pb.dart'
    show EmbeddingsRequest;
import 'package:runanywhere/generated/rerank.pb.dart'
    show RerankCandidate, RerankOptions, RerankRequest;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_embeddings.dart';
import 'package:runanywhere/native/dart_bridge_rerank.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

/// Text embedding.
class EmbeddingsApi {
  /// Bind the namespace. Reach it through `RunAnywhere.embeddings`.
  const EmbeddingsApi();

  /// Embed [texts], returning one vector per input in input order.
  ///
  /// ```dart
  /// final vectors = await RunAnywhere.embeddings.embed(['hello', 'world']);
  /// print(vectors.first.vector.length);
  /// ```
  ///
  /// Throws [SDKException] when no embedding model is loadable.
  Future<List<Embedding>> embed(
    List<String> texts, {
    String? model,
    EmbedOptions? options,
  }) async {
    if (texts.isEmpty) return const <Embedding>[];
    await ModelGate.ensureLoaded(
      modelId: model,
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    );
    final modelId =
        await ModelGate.currentId(ModelCategory.MODEL_CATEGORY_EMBEDDING);
    if (modelId == null) {
      throw SDKException.componentNotReady('Embeddings');
    }
    final result = await DartBridgeEmbeddings.shared.embedBatchAsync(
      EmbeddingsRequest(
        texts: texts,
        options: (options ?? EmbedOptions()).toProto(),
        modelId: modelId,
      ),
    );
    if (result.errorMessage.isNotEmpty) {
      throw SDKException.processingFailed(result.errorMessage);
    }
    final vectors = result.vectors.map(Embedding.fromProto).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return List<Embedding>.unmodifiable(vectors);
  }
}

/// Cross-encoder reranking.
class RerankApi {
  /// Bind the namespace. Reach it through `RunAnywhere.rerank`.
  const RerankApi();

  /// Score [documents] against [query], best first.
  ///
  /// ```dart
  /// final ranked = await RunAnywhere.rerank.rerank('cats', docs, topN: 3);
  /// print(ranked.first.index);
  /// ```
  ///
  /// Throws [SDKException] when no rerank model is loaded.
  Future<List<RankedResult>> rerank(
    String query,
    List<String> documents, {
    int? topN,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (documents.isEmpty) return const <RankedResult>[];
    await DartBridge.ensureServicesReady();

    final snapshot = RunAnywhereModelLifecycle.shared.componentSnapshot(
      SDKComponent.SDK_COMPONENT_RERANK,
    );
    if (snapshot == null) {
      throw SDKException.componentNotReady('Rerank');
    }
    final request = RerankRequest(
      query: query,
      candidates: List<RerankCandidate>.generate(
        documents.length,
        (i) => RerankCandidate(id: '$i', text: documents[i]),
      ),
      options: RerankOptions(topN: topN ?? 0),
    );
    final result = DartBridgeRerank.shared.rerank(request, snapshot);
    return List<RankedResult>.unmodifiable(
      result.items.map(RankedResult.fromProto),
    );
  }
}
