import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/errors.pbenum.dart' show ErrorCode;
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_ai/core/services/model_catalog_bootstrap.dart';
import 'package:runanywhere_ai/core/services/qhexrt_model_catalog.dart';
import 'package:runanywhere_ai/features/models/model_types.dart'
    show ExampleModelInfoView, ModelSelectionContext;
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

// Golden eligible IDs from kModelPolicies at 259521e299bb, intersected with
// this app catalog. Kitten nano deliberately selects only its v81 manifest.
const _eligibleIdsByArchitecture = <HexagonArch, List<String>>{
  HexagonArch.HEXAGON_ARCH_V75: [
    'canary_180m_flash',
    'canary_1b_flash',
    'embeddinggemma_300m',
    'internvl3_5_1b',
    'kokoro_en',
    'lfm2_5_230m',
    'lfm2_5_2_6b',
    'lfm2_5_350m',
    'magpie_tts_357m',
    'melotts_en',
    'moonshine_base',
    'moonshine_tiny',
    'nemotron_3_embed_1b',
    'nemotron_asr_streaming',
    'nemotron_nano_8b',
    'nemotron_ocr',
    'nemotron_ocr_v1',
    'nemotron_parse',
    'nv_embedqa_1b',
    'nv_rerankqa_1b',
    'parakeet_ctc_1_1b',
    'parakeet_rnnt_1_1b',
    'parakeet_tdt_0_6b_v2',
    'parakeet_tdt_0_6b_v3',
    'qwen3_0_6b',
    'qwen3_5_0_8b',
    'qwen3_5_2b',
    'qwen3_vl',
    'siglip2_base',
    'ternary_bonsai_1_7b',
    'whisper_base',
    'whisper_small',
  ],
  HexagonArch.HEXAGON_ARCH_V79: [
    'cosmos3_edge_diffusion',
    'cosmos3_edge_text',
    'cosmos3_edge_vlm',
    'deepseek_r1_distill_qwen_1_5b',
    'embeddinggemma_300m',
    'gemma4_e2b',
    'gemma4_e2b_vlm',
    'internvl3_5_1b',
    'lama_dilated',
    'lfm2_5_230m',
    'lfm2_5_2_6b',
    'lfm2_5_350m',
    'llama3_2_1b',
    'melotts_en',
    'moonshine_base',
    'moonshine_tiny',
    'phi_tiny_moe',
    'qwen3_5_0_8b',
    'qwen3_5_2b',
    'qwen3_5_4b',
    'qwen3_vl',
    'siglip2_base',
    'whisper_base',
    'whisper_small',
  ],
  HexagonArch.HEXAGON_ARCH_V81: [
    'bonsai_1_7b_1bit',
    'bonsai_27b_1bit',
    'bonsai_4b_1bit',
    'bonsai_8b_1bit',
    'canary_1b_flash',
    'canary_qwen_2_5b',
    'cosmos3_edge_diffusion',
    'cosmos3_edge_text',
    'cosmos3_edge_vlm',
    'deepseek_r1_distill_qwen_1_5b',
    'deepseek_r1_distill_qwen_7b',
    'embeddinggemma_300m',
    'gemma3n_e4b',
    'gemma4_e2b',
    'gemma4_e2b_vlm',
    'gemma4_e4b',
    'gemma4_e4b_vlm',
    'internvl3_5_1b',
    'kitten_micro_0_8',
    'kitten_mini_0_8',
    'kitten_nano_0_8',
    'kokoro_en',
    'lama_dilated',
    'lfm2_5_230m',
    'lfm2_5_2_6b',
    'lfm2_5_350m',
    'llama3_2_1b',
    'llama_embed_nemotron_8b',
    'magpie_tts_357m',
    'melotts_en',
    'moonshine_base',
    'moonshine_tiny',
    'nemoguard_content_8b',
    'nemoguard_topic_8b',
    'nemotron_asr_streaming',
    'nemotron_nano_8b',
    'nemotron_nano_vl_8b',
    'nemotron_ocr',
    'nemotron_ocr_v1',
    'nemotron_parse',
    'nv_embedcode_7b',
    'nv_embedqa_1b',
    'nv_rerankqa_1b',
    'parakeet_rnnt_1_1b',
    'parakeet_tdt_0_6b_v2',
    'parakeet_tdt_0_6b_v3',
    'phi_tiny_moe',
    'qwen3_0_6b',
    'qwen3_5_0_8b',
    'qwen3_5_2b',
    'qwen3_5_4b',
    'qwen3_vl_2b_text',
    'siglip2_base',
    'ternary_bonsai_1_7b',
    'whisper_base',
    'whisper_small',
  ],
};

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
        model.downloadBytes,
        anyOf(isNull, greaterThan(0)),
        reason: model.id,
      );
      expect(
        model.contextLength,
        anyOf(isNull, greaterThan(0)),
        reason: model.id,
      );
    }
  });

  test('QHexRT definitions preserve app-owned explicit URL metadata', () {
    const rows = QHexRTModelCatalog.models;

    expect(rows.map((model) => model.id).toSet(), hasLength(rows.length));
    for (final model in rows) {
      final request = model.toRegistrationRequest();
      expect(request.id, model.id);
      expect(request.name, model.name);
      expect(request.url, model.url);
      expect(request.framework, InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT);
      expect(request.category, model.category);
      expect(request.source, ModelSource.MODEL_SOURCE_REMOTE);
      expect(request.memoryRequiredBytes.toInt(), model.memoryBytes);
      expect(
        request.hasDownloadSizeBytes()
            ? request.downloadSizeBytes.toInt()
            : null,
        model.downloadBytes,
      );
      expect(
        request.hasContextLength() ? request.contextLength : null,
        model.contextLength,
      );
      expect(request.supportsThinking, model.supportsThinking);
      expect(request.supportsLora, model.supportsLora);
      expect(model.url, startsWith('https://'));
    }
  });

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
          if (request.id == 'qwen3_5_2b') {
            return null;
          }
          if (request.id == 'kokoro_en') {
            throw SDKException.make(
              code: ErrorCode.ERROR_CODE_NETWORK_ERROR,
              message: 'Network unavailable',
            );
          }
          throw SDKException.make(
            code: ErrorCode.ERROR_CODE_NOT_FOUND,
            message: 'Manifest unavailable',
          );
        },
      );

      expect(result.registered, 1);
      expect(result.failed, 1);
      expect(result.skippedNative, 58);
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

  for (final (label, id, architecture, expected) in [
    ('pinned match', 'canary_qwen_2_5b', HexagonArch.HEXAGON_ARCH_V81, true),
    (
      'pinned mismatch',
      'canary_qwen_2_5b',
      HexagonArch.HEXAGON_ARCH_V75,
      false,
    ),
    ('explicit exclusion', 'kokoro_en', HexagonArch.HEXAGON_ARCH_V79, false),
  ]) {
    test('isEligibleFor handles $label', () {
      final row = QHexRTModelCatalog.models.singleWhere((row) => row.id == id);
      expect(
        row.isEligibleFor(
          NpuCapability(supported: true, hexagonArch: architecture),
        ),
        expected,
      );
    });
  }

  test('unsupported devices reject every row, including matching pins', () {
    for (final architecture in _eligibleIdsByArchitecture.keys) {
      final capability = NpuCapability(
        supported: false,
        hexagonArch: architecture,
      );
      expect(
        QHexRTModelCatalog.models.where((row) => row.isEligibleFor(capability)),
        isEmpty,
      );
    }
  });

  for (final entry in _eligibleIdsByArchitecture.entries) {
    test('preserves complete catalog eligibility for ${entry.key}', () {
      final capability = NpuCapability(supported: true, hexagonArch: entry.key);
      final eligibleIds =
          QHexRTModelCatalog.models
              .where((row) => row.isEligibleFor(capability))
              .map((row) => row.id)
              .toList()
            ..sort();
      expect(eligibleIds, entry.value);
    });

    test(
      'skips ineligible rows before registration for ${entry.key}',
      () async {
        final calledIds = <String>[];
        final result = await QHexRTModelCatalog.registerWith(
          deviceEligible: true,
          capability: NpuCapability(supported: true, hexagonArch: entry.key),
          registrar: (request) async {
            calledIds.add(request.id);
            return ModelInfo(
              id: request.id,
              framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
            );
          },
        );
        expect(calledIds..sort(), entry.value);
        expect(result.registered, entry.value.length);
        expect(
          result.skippedNative,
          QHexRTModelCatalog.models.length - entry.value.length,
        );
        expect(result.failed, 0);
        expect(result.registeredModelIds, entry.value.toSet());
      },
    );
  }

  test('an unsupported capability never reaches the registrar', () async {
    final result = await QHexRTModelCatalog.registerWith(
      deviceEligible: true,
      capability: NpuCapability(
        supported: false,
        hexagonArch: HexagonArch.HEXAGON_ARCH_V81,
      ),
      registrar: (_) async =>
          fail('Unsupported devices must skip before registration'),
    );
    expect(result.registered, 0);
    expect(result.failed, 0);
    expect(result.skippedNative, QHexRTModelCatalog.models.length);
  });

  test('URL architecture folders and filenames always have matching pins', () {
    const architectureByName = {
      '75': HexagonArch.HEXAGON_ARCH_V75,
      '79': HexagonArch.HEXAGON_ARCH_V79,
      '81': HexagonArch.HEXAGON_ARCH_V81,
    };
    final pattern = RegExp(r'(?:^|[/_-])v(75|79|81)(?=[/_.-]|$)');
    final pinnedUrlIds = <String>[];
    for (final row in QHexRTModelCatalog.models) {
      final matches = pattern.allMatches(Uri.parse(row.url).path);
      if (matches.isNotEmpty) {
        pinnedUrlIds.add(row.id);
      }
      for (final match in matches) {
        expect(
          row.pinnedArchitecture,
          architectureByName[match.group(1)],
          reason: row.id,
        );
      }
    }
    expect(pinnedUrlIds..sort(), [
      'canary_qwen_2_5b',
      'kitten_micro_0_8',
      'kitten_mini_0_8',
      'kitten_nano_0_8',
    ]);
  });
}
