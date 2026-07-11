import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/core/services/qhexrt_model_catalog.dart';
import 'package:runanywhere_ai/features/models/model_types.dart'
    show ExampleModelInfoView, ModelSelectionContext;

void main() {
  tearDown(QHexRTModelCatalog.resetForTesting);

  test('Flutter QHexRT catalog exactly matches the 51 Android rows', () {
    final kotlinRows = _parseKotlinCatalog();
    const flutterRows = QHexRTModelCatalog.models;

    expect(flutterRows, hasLength(51));
    expect(
      flutterRows.map((model) => model.id).toList(),
      kotlinRows.map((model) => model.id).toList(),
    );

    for (final flutterModel in flutterRows) {
      final kotlinModel = kotlinRows.singleWhere(
        (model) => model.id == flutterModel.id,
      );
      expect(flutterModel.name, kotlinModel.name, reason: flutterModel.id);
      expect(flutterModel.url, kotlinModel.url, reason: flutterModel.id);
      expect(
        flutterModel.category,
        kotlinModel.category,
        reason: flutterModel.id,
      );
      expect(
        flutterModel.memoryBytes,
        kotlinModel.memoryBytes,
        reason: flutterModel.id,
      );
      expect(
        flutterModel.contextLength,
        kotlinModel.contextLength,
        reason: flutterModel.id,
      );
      expect(
        flutterModel.supportsThinking,
        kotlinModel.supportsThinking,
        reason: flutterModel.id,
      );
    }
  });

  test(
    'QHexRT requests preserve app-owned metadata for native registration',
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
      expect(result.skippedNative, 50);
      expect(result.registeredModelIds, {'qwen3_5_0_8b_v81'});
      expect(seenIds, hasLength(51));
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
    expect(result.skippedNative, 51);
    expect(QHexRTModelCatalog.registeredModelIds, isEmpty);
    expect(QHexRTModelCatalog.snapshots.value.revision, 2);
  });

  test('RAG accepts QHexRT generators and embedders but not rerankers', () {
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
      ModelSelectionContext.ragEmbedding.includes(qhexrtEmbedding),
      isTrue,
    );
    expect(
      ModelSelectionContext.ragEmbedding.includes(qhexrtReranker),
      isFalse,
    );
    expect(ModelSelectionContext.ragLLM.includes(qhexrtLlm), isTrue);
  });

  test('non-QHexRT IDs do not inherit native QHexRT auth policy', () {
    final cpuModelWithSharedId = ModelInfo(
      id: 'qwen3_0_6b',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    );

    expect(cpuModelWithSharedId.requiresHfAuth, isFalse);
  });
}

List<_KotlinCatalogModel> _parseKotlinCatalog() {
  final candidates = [
    File(
      '../../android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/ModelCatalog.kt',
    ),
    File(
      'examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/ModelCatalog.kt',
    ),
  ];
  final sourceFile = candidates.firstWhere(
    (candidate) => candidate.existsSync(),
    orElse: () => throw StateError('Android ModelCatalog.kt not found'),
  );
  final source = sourceFile.readAsStringSync();
  final start = source.indexOf('val npuCatalog:');
  final end = source.indexOf('// The Play build', start);
  final catalogSource = source.substring(start, end);
  final rowPattern = RegExp(
    r'SingleFileModel\("([^"]+)", "([^"]+)", "([^"]+)", QHEXRT, ([A-Z_]+), ([0-9_]+)L([^)]*)\)',
  );

  return rowPattern
      .allMatches(catalogSource)
      .map((match) {
        final optionalArguments = match.group(6)!;
        final contextMatch = RegExp(
          r'contextLength = ([0-9_]+)',
        ).firstMatch(optionalArguments);
        return _KotlinCatalogModel(
          id: match.group(1)!,
          name: match.group(2)!,
          url: match.group(3)!,
          category: _kotlinCategory(match.group(4)!),
          memoryBytes: int.parse(match.group(5)!.replaceAll('_', '')),
          contextLength: contextMatch == null
              ? null
              : int.parse(contextMatch.group(1)!.replaceAll('_', '')),
          supportsThinking: optionalArguments.contains(
            'supportsThinking = true',
          ),
        );
      })
      .toList(growable: false);
}

ModelCategory _kotlinCategory(String category) => switch (category) {
  'LANGUAGE' => ModelCategory.MODEL_CATEGORY_LANGUAGE,
  'MULTIMODAL' => ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  'IMAGE_GENERATION' => ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
  'EMBEDDING' => ModelCategory.MODEL_CATEGORY_EMBEDDING,
  'STT' => ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  'TTS' => ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  _ => throw StateError('Unknown Kotlin category: $category'),
};

class _KotlinCatalogModel {
  const _KotlinCatalogModel({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
    required this.memoryBytes,
    required this.contextLength,
    required this.supportsThinking,
  });

  final String id;
  final String name;
  final String url;
  final ModelCategory category;
  final int memoryBytes;
  final int? contextLength;
  final bool supportsThinking;
}
