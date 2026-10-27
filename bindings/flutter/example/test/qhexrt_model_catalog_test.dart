import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/core/services/model_catalog_bootstrap.dart';
import 'package:runanywhere_ai/core/services/qhexrt_model_catalog.dart';
import 'package:runanywhere_ai/features/models/model_types.dart'
    show ExampleModelInfoView, ModelSelectionContext;

void main() {
  tearDown(QHexRTModelCatalog.resetForTesting);

  // The Android counterpart of this catalog now lives in
  // github.com/RunanywhereAI/runanywhere-android, so the row-by-row parity
  // assertion this test used to make against `ModelCatalog.kt` is no longer
  // expressible here. What remains are the invariants this catalog owns.
  test('QHexRT catalog rows are well-formed and uniquely identified', () {
    const flutterRows = QHexRTModelCatalog.models;

    expect(flutterRows, hasLength(60));
    expect(
      flutterRows.map((model) => model.id).toSet(),
      hasLength(flutterRows.length),
    );
    for (final model in flutterRows) {
      expect(model.name, isNotEmpty, reason: model.id);
      expect(model.url, startsWith('https://'), reason: model.id);
      expect(model.memoryBytes, greaterThan(0), reason: model.id);
      expect(
        model.contextLength,
        anyOf(isNull, greaterThan(0)),
        reason: model.id,
      );
    }
  });

  test(
    'QHexRT definitions preserve app-owned explicit URL metadata',
    () {
      const rows = QHexRTModelCatalog.models;

      expect(rows.map((model) => model.id).toSet(), hasLength(rows.length));
      for (final model in rows) {
        final request = model.toRegistrationRequest();
        expect(request.id, model.id);
        expect(request.name, model.name);
        expect(request.url, model.url);
        expect(
          request.framework,
          InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
        );
        expect(request.category, model.category);
        expect(request.source, ModelSource.MODEL_SOURCE_REMOTE);
        expect(request.memoryRequiredBytes.toInt(), model.memoryBytes);
        expect(request.downloadSizeBytes.toInt(), model.memoryBytes);
        expect(
          request.hasContextLength() ? request.contextLength : null,
          model.contextLength,
        );
        expect(request.supportsThinking, model.supportsThinking);
        expect(request.supportsLora, model.supportsLora);
        expect(model.url, startsWith('https://'));
      }
    },
  );

  test(
    'native accepted IDs replace logical and stale QHexRT picker rows',
    () async {
      final seenIds = <String>{};
      final result = await QHexRTModelCatalog.registerWith(
        deviceEligible: true,
        registrar: (request) async {
          seenIds.add(request.id);
          if (request.id == 'qwen3_5_0_8b') {
            return ModelInfo(
              id: 'qwen3_5_0_8b_v81',
              framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
            );
          }
          return null;
        },
      );

      expect(result.registered, 1);
      expect(result.failed, 0);
      expect(result.skippedNative, 59);
      expect(result.registeredModelIds, {'qwen3_5_0_8b_v81'});
      expect(seenIds, hasLength(60));
      expect(seenIds, contains('kokoro_en'));

      final cpu = ModelInfo(
        id: 'cpu-model',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      );
      final staleLogical = ModelInfo(
        id: 'qwen3_5_0_8b',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      );
      final acceptedNative = ModelInfo(
        id: 'qwen3_5_0_8b_v81',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      );

      expect(QHexRTModelCatalog.isVisibleForNativeCatalog(cpu), isTrue);
      expect(
        QHexRTModelCatalog.isVisibleForNativeCatalog(staleLogical),
        isFalse,
      );
      expect(
        QHexRTModelCatalog.isVisibleForNativeCatalog(acceptedNative),
        isTrue,
      );
    },
  );

  test('non-Android registration clears accepted QHexRT IDs', () async {
    await QHexRTModelCatalog.registerWith(
      deviceEligible: true,
      registrar: (request) async => ModelInfo(
        id: '${request.id}_native',
        framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      ),
    );
    var registrarCalled = false;

    final result = await QHexRTModelCatalog.registerWith(
      deviceEligible: false,
      registrar: (_) async {
        registrarCalled = true;
        return null;
      },
    );

    expect(registrarCalled, isFalse);
    expect(result.registeredModelIds, isEmpty);
    expect(result.skippedNative, 60);
    expect(QHexRTModelCatalog.registeredModelIds, isEmpty);
    expect(QHexRTModelCatalog.snapshots.value.revision, 2);
  });

  test('RAG accepts QHexRT generators and embedders but not rerankers', () {
    final portableLlamaEmbedding = ModelInfo(
      id: 'nemotron-3-embed-1b-q4_k_m',
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    );
    final qhexrtEmbedding = ModelInfo(
      id: 'embeddinggemma_300m_v81',
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    );
    final qhexrtReranker = ModelInfo(
      id: 'nv_rerankqa_1b_v81',
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    );
    final qhexrtLlm = ModelInfo(
      id: 'qwen3_5_0_8b_v81',
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    );

    expect(
      ModelSelectionContext.ragEmbedding.includes(portableLlamaEmbedding),
      isTrue,
    );
    expect(
      ModelSelectionContext.ragEmbedding.includes(qhexrtEmbedding),
      isTrue,
    );
    expect(
      ModelSelectionContext.ragEmbedding.includes(qhexrtReranker),
      isFalse,
    );
    expect(ModelSelectionContext.ragLLM.includes(qhexrtLlm), isTrue);
  });

  test('portable NVIDIA embedding rows stay pinned to validated GGUFs', () {
    expect(
      portableNvidiaEmbeddingCatalog
          .map((model) => model.id)
          .toList(growable: false),
      [
        'nemotron-3-embed-1b-q4_k_m',
        'llama-nemotron-embed-1b-v2-q4_k_m',
        'llama-embed-nemotron-8b-q4_k_m',
      ],
    );
    expect(
      portableNvidiaEmbeddingCatalog
          .map((model) => model.memoryRequirement)
          .toList(growable: false),
      [749352096, 807690624, 4625233184],
    );
    expect(
      portableNvidiaEmbeddingCatalog.map((model) => model.url),
      everyElement(matches(RegExp(r'/resolve/[0-9a-f]{40}/.*\.gguf$'))),
    );
  });

  test('non-QHexRT IDs do not inherit native QHexRT auth policy', () {
    final cpuModelWithSharedId = ModelInfo(
      id: 'qwen3_0_6b',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    );

    expect(cpuModelWithSharedId.requiresHfAuth, isFalse);
  });
}
