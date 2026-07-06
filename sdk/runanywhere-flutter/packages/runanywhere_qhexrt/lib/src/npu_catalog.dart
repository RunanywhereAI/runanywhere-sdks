/// Curated QHexRT NPU catalog — one manifest-pinned hf.co folder ref per
/// bundle (`https://huggingface.co/<repo>/<arch>/<manifest>.json`). Commons
/// + the engine-registered QHexRT bundle policy resolve the full file set
/// (sizes, checksums, nested paths) from the Hub tree at registration — no
/// file lists in the SDK. Context binaries are arch-exact ([arch] is the
/// Hexagon architecture they were compiled for: v75+), so registration
/// filters to the arch probed on the running device.
///
/// Kept in lockstep with the Kotlin (`runanywhere-core-qhexrt`) and React
/// Native (`@runanywhere/qhexrt`) SDK packages.

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart';
import 'package:runanywhere_qhexrt/runanywhere_qhexrt.dart';

/// One QHexRT NPU bundle reference: an HF folder-bundle URL pinned to the
/// bundle's manifest (`huggingface.co/<repo>/<arch>/<manifest>.json`).
class _NpuRef {
  const _NpuRef({
    required this.id,
    required this.name,
    required this.modality,
    required this.arch,
    required this.url,
  });

  final String id;
  final String name;
  final ModelCategory modality;
  final String arch;
  final String url;
}

const List<_NpuRef> _npuRefs = [
  _NpuRef(
    id: 'lfm2_5_230m_v79',
    name: 'LFM2.5 230M (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    arch: 'v79',
    url:
        'https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v79/lfm2-5-230m.json',
  ),
  _NpuRef(
    id: 'lfm2_5_230m_v81',
    name: 'LFM2.5 230M (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/v81/lfm2-5-230m.json',
  ),
  _NpuRef(
    id: 'lfm2_5_350m_v79',
    name: 'LFM2.5 350M (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    arch: 'v79',
    url:
        'https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v79/lfm2-5-350m-2048.json',
  ),
  _NpuRef(
    id: 'lfm2_5_350m_v81',
    name: 'LFM2.5 350M (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/v81/lfm2-5-350m-2048.json',
  ),
  _NpuRef(
    id: 'qwen3_5_0_8b_v81',
    name: 'Qwen3.5 0.8B (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/v81/qwen3.5-0.8b-1024.json',
  ),
  _NpuRef(
    id: 'qwen3_vl_v79',
    name: 'Qwen3-VL 2B (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    arch: 'v79',
    url:
        'https://huggingface.co/runanywhere/qwen3_vl_HNPU/v79/qwen3vl-2b-vlm-512.json',
  ),
  _NpuRef(
    id: 'internvl3_5_1b_v79',
    name: 'InternVL3.5 1B (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    arch: 'v79',
    url:
        'https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v79/internvl3_5-1b-512.json',
  ),
  _NpuRef(
    id: 'internvl3_5_1b_v81',
    name: 'InternVL3.5 1B (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/internvl3_5_1b_HNPU/v81/internvl3_5-1b.json',
  ),
  _NpuRef(
    id: 'whisper_base_v79',
    name: 'Whisper Base (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    arch: 'v79',
    url:
        'https://huggingface.co/runanywhere/whisper_base_HNPU/v79/whisper-base.json',
  ),
  _NpuRef(
    id: 'whisper_small_v79',
    name: 'Whisper Small (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    arch: 'v79',
    url:
        'https://huggingface.co/runanywhere/whisper_small_HNPU/v79/whisper-small.json',
  ),
  _NpuRef(
    id: 'moonshine_tiny_v81',
    name: 'Moonshine Tiny (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/moonshine_tiny_HNPU/v81/moonshine-tiny.json',
  ),
  _NpuRef(
    id: 'moonshine_base_v81',
    name: 'Moonshine Base (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/moonshine_base_HNPU/v81/moonshine-base.json',
  ),
  _NpuRef(
    id: 'melotts_en_v79',
    name: 'MeloTTS EN (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    arch: 'v79',
    url:
        'https://huggingface.co/runanywhere/melotts_en_HNPU/v79/melotts-en.json',
  ),
  _NpuRef(
    id: 'melotts_en_v81',
    name: 'MeloTTS EN (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/melotts_en_HNPU/v81/melotts-en.json',
  ),
  _NpuRef(
    id: 'kokoro_en_v81',
    name: 'Kokoro-82M EN (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/kokoro_en_HNPU/v81/kokoro-en.json',
  ),
  _NpuRef(
    id: 'kitten_nano_0_8_v81',
    name: 'Kitten-nano-0.8-fp32 (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/v81/kitten_nano08_v81.json',
  ),
  _NpuRef(
    id: 'kitten_mini_0_1_v81',
    name: 'Kitten-mini-0.1 (HNPU)',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    arch: 'v81',
    url:
        'https://huggingface.co/runanywhere/kitten_mini_0_1_HNPU/v81/kitten_mini01_v81.json',
  ),
];

/// Seed the QHexRT NPU catalog: probe the device NPU, register arch-matching
/// bundles via the SDK's canonical from-url path, then refresh the model
/// registry. Safe to re-run on every cold launch — commons merges runtime
/// fields on re-registration.
///
/// Does NOT call [QHexRT.register] — the caller must register the backend
/// separately (before or after catalog seeding) so the two concerns stay
/// decoupled: "enable the engine" vs "populate the catalog."
///
/// On unsupported devices this is a no-op (no bundles match) and returns 0.
///
/// Returns the number of NPU bundles successfully registered.
Future<int> seedNpuCatalog() async {
  if (!QHexRT.isAvailable) {
    debugPrint('QHexRT NPU not available; skipping NPU catalog seed');
    return 0;
  }

  final npu = QHexRT.probeNpu();
  if (!npu.qhexrtSupported) {
    debugPrint('QHexRT NPU not supported on this device; skipping NPU catalog seed');
    return 0;
  }

  final arch = npu.archName;
  final bundles = _npuRefs.where((r) => r.arch == arch).toList();
  var count = 0;
  for (final r in bundles) {
    try {
      await RunAnywhere.models.register(
        id: r.id,
        name: r.name,
        url: r.url,
        framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
        modality: r.modality,
        memoryRequirement: 0,
      );
      count++;
    } catch (e) {
      debugPrint('Failed to register NPU bundle ${r.id}: $e');
    }
  }

  debugPrint('QHexRT NPU bundles registered for $arch: $count');
  return count;
}