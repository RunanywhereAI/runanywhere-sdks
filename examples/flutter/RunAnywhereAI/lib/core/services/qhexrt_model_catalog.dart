import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

const _qhexrt = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT;
const _language = ModelCategory.MODEL_CATEGORY_LANGUAGE;
const _multimodal = ModelCategory.MODEL_CATEGORY_MULTIMODAL;
const _imageGeneration = ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION;
const _embedding = ModelCategory.MODEL_CATEGORY_EMBEDDING;
const _stt = ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION;
const _tts = ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS;
const _hnpuDescription = 'Qualcomm Hexagon NPU model bundle.';

typedef QHexRTCatalogRegistrar =
    Future<ModelInfo?> Function(RegisterModelFromUrlRequest request);

@immutable
class QHexRTCatalogModel {
  const QHexRTCatalogModel({
    required this.id,
    required this.name,
    required this.url,
    required this.category,
    required this.memoryBytes,
    this.contextLength,
    this.supportsThinking = false,
    this.supportsLora = false,
  });

  final String id;
  final String name;
  final String url;
  final ModelCategory category;
  final int memoryBytes;
  final int? contextLength;
  final bool supportsThinking;
  final bool supportsLora;

  RegisterModelFromUrlRequest toRegistrationRequest() =>
      RegisterModelFromUrlRequest(
        id: id,
        name: name,
        url: url,
        framework: _qhexrt,
        category: category,
        source: ModelSource.MODEL_SOURCE_REMOTE,
        memoryRequiredBytes: Int64(memoryBytes),
        downloadSizeBytes: Int64(memoryBytes),
        contextLength: contextLength,
        supportsThinking: supportsThinking,
        supportsLora: supportsLora,
        description: _hnpuDescription,
      );
}

@immutable
class QHexRTCatalogSnapshot {
  const QHexRTCatalogSnapshot({
    this.registeredModelIds = const <String>{},
    this.revision = 0,
  });

  final Set<String> registeredModelIds;
  final int revision;
}

@immutable
class QHexRTCatalogSeedResult {
  const QHexRTCatalogSeedResult({
    required this.registered,
    required this.failed,
    required this.skippedNative,
    required this.registeredModelIds,
  });

  final int registered;
  final int failed;
  final int skippedNative;
  final Set<String> registeredModelIds;
}

/// Flutter's app-owned QHexRT definitions and native registration results.
///
/// URLs and presentation metadata stay in the example app. Device probing,
/// architecture selection, model-ID materialization, and registry insertion
/// stay in QHexRT's native catalog facade.
abstract final class QHexRTModelCatalog {
  static final ValueNotifier<QHexRTCatalogSnapshot> snapshots = ValueNotifier(
    const QHexRTCatalogSnapshot(),
  );

  static Set<String> get registeredModelIds =>
      snapshots.value.registeredModelIds;

  /// Kept in lockstep with Android's `ModelCatalog.npuCatalog`.
  static const List<QHexRTCatalogModel> models = [
    QHexRTCatalogModel(
      id: 'lfm2_5_230m',
      name: 'LFM2.5 230M (HNPU)',
      url:
          'https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/lfm2-5-230m.json',
      category: _language,
      memoryBytes: 886089241,
      contextLength: 512,
    ),
    QHexRTCatalogModel(
      id: 'lfm2_5_350m',
      name: 'LFM2.5 350M (HNPU)',
      url:
          'https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/lfm2-5-350m-2048.json',
      category: _language,
      memoryBytes: 1441493515,
      contextLength: 2048,
    ),
    QHexRTCatalogModel(
      id: 'qwen3_5_0_8b',
      name: 'Qwen3.5 0.8B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json',
      category: _language,
      memoryBytes: 2046527848,
      contextLength: 1024,
      supportsThinking: true,
    ),
    QHexRTCatalogModel(
      id: 'qwen3_5_2b',
      name: 'Qwen3.5 2B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/qwen3_5_2b_HNPU/qwen3.5-2b-1024.json',
      category: _language,
      memoryBytes: 4817344861,
      contextLength: 1024,
    ),
    QHexRTCatalogModel(
      id: 'qwen3_5_4b',
      name: 'Qwen3.5 4B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/qwen3_5_4b_HNPU/qwen3.5-4b-1024.json',
      category: _language,
      memoryBytes: 6177585629,
      contextLength: 1024,
    ),
    QHexRTCatalogModel(
      id: 'qwen3_0_6b',
      name: 'Qwen3 0.6B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/qwen3_0_6b_HNPU/qwen3-0.6b-1024final.json',
      category: _language,
      memoryBytes: 1823248798,
      contextLength: 1024,
    ),
    QHexRTCatalogModel(
      id: 'llama3_2_1b',
      name: 'Llama 3.2 1B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/llama3_2_1b_HNPU/llama-3.2-1b.json',
      category: _language,
      memoryBytes: 3023821212,
    ),
    QHexRTCatalogModel(
      id: 'ternary_bonsai_1_7b',
      name: 'Ternary Bonsai 1.7B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/ternary_bonsai_1_7b_HNPU/ternary-bonsai-1.7b-1024.json',
      category: _language,
      memoryBytes: 2367579370,
      contextLength: 1024,
    ),
    QHexRTCatalogModel(
      id: 'phi_tiny_moe',
      name: 'Phi Tiny MoE (HNPU)',
      url: 'https://huggingface.co/runanywhere/phi_tiny_moe_HNPU/phimoe.json',
      category: _language,
      memoryBytes: 6100212369,
    ),
    QHexRTCatalogModel(
      id: 'embeddinggemma_300m',
      name: 'EmbeddingGemma 300M (HNPU)',
      url: 'https://huggingface.co/runanywhere/embeddinggemma_300m_HNPU',
      category: _embedding,
      memoryBytes: 566263339,
    ),
    QHexRTCatalogModel(
      id: 'gemma3n_e4b',
      name: 'Gemma 3n E4B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/gemma3n_e4b_HNPU/gemma-3n-E4B-it.json',
      category: _language,
      memoryBytes: 10929816419,
    ),
    QHexRTCatalogModel(
      id: 'gemma4_e2b',
      name: 'Gemma 4 E2B (HNPU)',
      url: 'https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b.json',
      category: _language,
      memoryBytes: 10532159450,
    ),
    QHexRTCatalogModel(
      id: 'gemma4_e4b',
      name: 'Gemma 4 E4B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/gemma4_e4b_HNPU/gemma-4-E4B.json',
      category: _language,
      memoryBytes: 13435056195,
    ),
    QHexRTCatalogModel(
      id: 'llama_embed_nemotron_8b',
      name: 'Llama Embed Nemotron 8B (HNPU)',
      url: 'https://huggingface.co/runanywhere/llama_embed_nemotron_8b_HNPU',
      category: _embedding,
      memoryBytes: 8079101598,
    ),
    QHexRTCatalogModel(
      id: 'nv_embedcode_7b',
      name: 'NV-EmbedCode 7B (HNPU)',
      url: 'https://huggingface.co/runanywhere/nv_embedcode_7b_HNPU',
      category: _embedding,
      memoryBytes: 7276868122,
    ),
    QHexRTCatalogModel(
      id: 'nv_embedqa_1b',
      name: 'NV-EmbedQA 1B (HNPU)',
      url: 'https://huggingface.co/runanywhere/nv_embedqa_1b_HNPU',
      category: _embedding,
      memoryBytes: 2493026133,
    ),
    QHexRTCatalogModel(
      id: 'nv_rerankqa_1b',
      name: 'NV-RerankQA 1B (HNPU)',
      url: 'https://huggingface.co/runanywhere/nv_rerankqa_1b_HNPU',
      category: _embedding,
      memoryBytes: 2494254905,
    ),
    QHexRTCatalogModel(
      id: 'deepseek_r1_distill_qwen_1_5b',
      name: 'DeepSeek R1 Distill Qwen 1.5B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_1_5b_HNPU/DeepSeek-R1-Distill-Qwen-1.5B.json',
      category: _language,
      memoryBytes: 6211227068,
      supportsThinking: true,
    ),
    QHexRTCatalogModel(
      id: 'deepseek_r1_distill_qwen_7b',
      name: 'DeepSeek R1 Distill Qwen 7B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_7b_HNPU/DeepSeek-R1-Distill-Qwen-7B.json',
      category: _language,
      memoryBytes: 8210665301,
      supportsThinking: true,
    ),
    QHexRTCatalogModel(
      id: 'nemotron_nano_8b',
      name: 'Llama 3.1 Nemotron Nano 8B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/nemotron_nano_8b_HNPU/nemotron-nano-8b.json',
      category: _language,
      memoryBytes: 8609694487,
    ),
    QHexRTCatalogModel(
      id: 'nemoguard_content_8b',
      name: 'NemoGuard 8B Content Safety (HNPU)',
      url:
          'https://huggingface.co/runanywhere/nemoguard_8b_content_safety_HNPU/nemoguard-content-8b.json',
      category: _language,
      memoryBytes: 8610354023,
    ),
    QHexRTCatalogModel(
      id: 'nemoguard_topic_8b',
      name: 'NemoGuard 8B Topic Control (HNPU)',
      url:
          'https://huggingface.co/runanywhere/nemoguard_8b_topic_control_HNPU/nemoguard-topic-8b.json',
      category: _language,
      memoryBytes: 8609694527,
    ),
    QHexRTCatalogModel(
      id: 'qwen3_vl_2b_text',
      name: 'Qwen3-VL 2B Text (HNPU)',
      url:
          'https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-text-512.json',
      category: _language,
      memoryBytes: 3220397297,
      contextLength: 512,
    ),
    QHexRTCatalogModel(
      id: 'qwen3_vl',
      name: 'Qwen3-VL 2B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-vlm-512.json',
      category: _multimodal,
      memoryBytes: 3220397297,
      contextLength: 512,
    ),
    QHexRTCatalogModel(
      id: 'internvl3_5_1b',
      name: 'InternVL3.5 1B (HNPU)',
      url: 'https://huggingface.co/runanywhere/internvl3_5_1b_HNPU',
      category: _multimodal,
      memoryBytes: 3067933894,
      contextLength: 512,
    ),
    QHexRTCatalogModel(
      id: 'gemma4_e2b_vlm',
      name: 'Gemma 4 E2B Image (HNPU)',
      url:
          'https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b-vlm.json',
      category: _multimodal,
      memoryBytes: 10532159450,
    ),
    QHexRTCatalogModel(
      id: 'gemma4_e4b_vlm',
      name: 'Gemma 4 E4B Image (HNPU)',
      url:
          'https://huggingface.co/runanywhere/gemma4_e4b_HNPU/gemma-4-E4B-vlm.json',
      category: _multimodal,
      memoryBytes: 13435056195,
    ),
    QHexRTCatalogModel(
      id: 'nemotron_nano_vl_8b',
      name: 'Llama 3.1 Nemotron Nano VL 8B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/nemotron_nano_vl_8b_HNPU/nemotron-vl-8b-vlm.json',
      category: _multimodal,
      memoryBytes: 10057258051,
    ),
    QHexRTCatalogModel(
      id: 'lama_dilated',
      name: 'LaMa Dilated (HNPU)',
      url: 'https://huggingface.co/runanywhere/lama_dilated_HNPU',
      category: _imageGeneration,
      memoryBytes: 98509597,
    ),
    QHexRTCatalogModel(
      id: 'nemotron_ocr',
      name: 'Nemotron OCR (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemotron_ocr_HNPU',
      category: _multimodal,
      memoryBytes: 121193004,
    ),
    QHexRTCatalogModel(
      id: 'nemotron_ocr_v1',
      name: 'Nemotron OCR v1 (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemotron_ocr_v1_HNPU',
      category: _multimodal,
      memoryBytes: 121406323,
    ),
    QHexRTCatalogModel(
      id: 'nemotron_parse',
      name: 'Nemotron Parse (HNPU)',
      url: 'https://huggingface.co/runanywhere/nemotron_parse_HNPU',
      category: _multimodal,
      memoryBytes: 1995206253,
    ),
    QHexRTCatalogModel(
      id: 'siglip2_base',
      name: 'SigLIP2 Base (HNPU)',
      url: 'https://huggingface.co/runanywhere/siglip2_base_HNPU',
      category: _embedding,
      memoryBytes: 789101244,
    ),
    QHexRTCatalogModel(
      id: 'whisper_base',
      name: 'Whisper Base (HNPU)',
      url:
          'https://huggingface.co/runanywhere/whisper_base_HNPU/whisper-base.json',
      category: _stt,
      memoryBytes: 221522616,
    ),
    QHexRTCatalogModel(
      id: 'whisper_small',
      name: 'Whisper Small (HNPU)',
      url:
          'https://huggingface.co/runanywhere/whisper_small_HNPU/whisper-small.json',
      category: _stt,
      memoryBytes: 676713240,
    ),
    QHexRTCatalogModel(
      id: 'moonshine_tiny',
      name: 'Moonshine Tiny (HNPU)',
      url:
          'https://huggingface.co/runanywhere/moonshine_tiny_HNPU/moonshine-tiny.json',
      category: _stt,
      memoryBytes: 84569427,
    ),
    QHexRTCatalogModel(
      id: 'moonshine_base',
      name: 'Moonshine Base (HNPU)',
      url:
          'https://huggingface.co/runanywhere/moonshine_base_HNPU/moonshine-base.json',
      category: _stt,
      memoryBytes: 167310675,
    ),
    QHexRTCatalogModel(
      id: 'parakeet_tdt_0_6b_v2',
      name: 'Parakeet TDT 0.6B v2 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v2_HNPU/parakeet-tdt-0.6b-v2.json',
      category: _stt,
      memoryBytes: 1280063837,
    ),
    QHexRTCatalogModel(
      id: 'parakeet_tdt_0_6b_v3',
      name: 'Parakeet TDT 0.6B v3 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v3_HNPU/parakeet-tdt-0.6b.json',
      category: _stt,
      memoryBytes: 1317902802,
    ),
    QHexRTCatalogModel(
      id: 'parakeet_rnnt_1_1b',
      name: 'Parakeet RNNT 1.1B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/parakeet_rnnt_1.1b_HNPU/parakeet-rnnt-1.1b.json',
      category: _stt,
      memoryBytes: 2211659923,
    ),
    QHexRTCatalogModel(
      id: 'canary_qwen_2_5b',
      name: 'Canary Qwen 2.5B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/canary_qwen_2.5b_HNPU/v81/canary-qwen-2.5b.json',
      category: _stt,
      memoryBytes: 5491333979,
    ),
    QHexRTCatalogModel(
      id: 'canary_1b_flash',
      name: 'Canary-1B-flash (HNPU)',
      url:
          'https://huggingface.co/runanywhere/canary_1b_flash_HNPU/canary-1b-flash.json',
      category: _stt,
      memoryBytes: 1835592227,
    ),
    QHexRTCatalogModel(
      id: 'nemotron_asr_streaming',
      name: 'Nemotron ASR Streaming 0.6B (HNPU)',
      url:
          'https://huggingface.co/runanywhere/nemotron_asr_streaming_HNPU/nemotron-3.5-asr-streaming-0.6b.json',
      category: _stt,
      memoryBytes: 1361283432,
    ),
    QHexRTCatalogModel(
      id: 'melotts_en',
      name: 'MeloTTS EN (HNPU)',
      url: 'https://huggingface.co/runanywhere/melotts_en_HNPU/melotts-en.json',
      category: _tts,
      memoryBytes: 120439053,
    ),
    QHexRTCatalogModel(
      id: 'kokoro_en',
      name: 'Kokoro-82M EN (HNPU)',
      url: 'https://huggingface.co/runanywhere/kokoro_en_HNPU/kokoro-en.json',
      category: _tts,
      memoryBytes: 470739484,
    ),
    QHexRTCatalogModel(
      id: 'kitten_nano_0_8',
      name: 'Kitten-nano-0.8-fp32 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/kitten_nano08_v81.json',
      category: _tts,
      memoryBytes: 95842227,
    ),
    QHexRTCatalogModel(
      id: 'kitten_mini_0_1',
      name: 'Kitten-mini-0.1 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/kitten_mini_0_1_HNPU/kitten_mini01_v81.json',
      category: _tts,
      memoryBytes: 449672060,
    ),
    QHexRTCatalogModel(
      id: 'kitten_mini_0_8',
      name: 'Kitten-mini-0.8 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/kitten_mini_0_8_HNPU/kitten_mini08_v81.json',
      category: _tts,
      memoryBytes: 778828575,
    ),
    QHexRTCatalogModel(
      id: 'kitten_micro_0_8',
      name: 'Kitten-micro-0.8 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/kitten_micro_0_8_HNPU/kitten_micro08_v81.json',
      category: _tts,
      memoryBytes: 338682302,
    ),
    QHexRTCatalogModel(
      id: 'kitten_nano_0_2',
      name: 'Kitten-nano-0.2 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/kitten_nano_0_2_HNPU/kitten_nano02_v81.json',
      category: _tts,
      memoryBytes: 105235740,
    ),
    QHexRTCatalogModel(
      id: 'kitten_nano_0_1',
      name: 'Kitten-nano-0.1 (HNPU)',
      url:
          'https://huggingface.co/runanywhere/kitten_nano_0_1_HNPU/kitten_nano01_v81.json',
      category: _tts,
      memoryBytes: 104733291,
    ),
  ];

  static bool isVisibleForNativeCatalog(ModelInfo model) {
    final isQHexRT =
        model.framework == _qhexrt ||
        (model.hasPreferredFramework() && model.preferredFramework == _qhexrt);
    return !isQHexRT || registeredModelIds.contains(model.id);
  }

  static Future<QHexRTCatalogSeedResult> registerForCurrentDevice() {
    final eligible = Platform.isAndroid && QHexRT.isAvailable;
    return registerWith(
      deviceEligible: eligible,
      registrar: (request) => QHexRT.registerModelForDevice(request: request),
    );
  }

  /// Dependency-injected registration seam for deterministic catalog tests.
  @visibleForTesting
  static Future<QHexRTCatalogSeedResult> registerWith({
    required bool deviceEligible,
    required QHexRTCatalogRegistrar registrar,
  }) async {
    var registered = 0;
    var failed = 0;
    var skippedNative = 0;
    final registeredIds = <String>{};

    if (!deviceEligible) {
      skippedNative = models.length;
    } else {
      for (final model in models) {
        try {
          final saved = await registrar(model.toRegistrationRequest());
          if (saved == null) {
            skippedNative++;
          } else {
            registered++;
            registeredIds.add(saved.id);
          }
        } catch (error) {
          failed++;
          debugPrint('QHexRT catalog: ${model.id} failed: $error');
        }
      }
    }

    final immutableIds = Set<String>.unmodifiable(registeredIds);
    snapshots.value = QHexRTCatalogSnapshot(
      registeredModelIds: immutableIds,
      revision: snapshots.value.revision + 1,
    );
    return QHexRTCatalogSeedResult(
      registered: registered,
      failed: failed,
      skippedNative: skippedNative,
      registeredModelIds: immutableIds,
    );
  }

  @visibleForTesting
  static void resetForTesting() {
    snapshots.value = const QHexRTCatalogSnapshot();
  }
}
