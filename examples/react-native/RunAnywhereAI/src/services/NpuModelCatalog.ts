import {
  InferenceFramework,
  ModelCategory,
  type ModelInfo,
  ModelSource,
  RegisterModelFromUrlRequest,
} from '@runanywhere/proto-ts/model_types';

const HNPU_DESCRIPTION = 'Qualcomm Hexagon NPU model bundle.';

export type NpuBundle = Readonly<{
  id: string;
  name: string;
  url: string;
  modality: ModelCategory;
  estimatedSizeBytes: number;
  contextLength?: number;
  supportsThinking?: boolean;
}>;

/**
 * App-owned QHexRT catalog. Keep this in lockstep with the Kotlin Android
 * example: native QHexRT owns device probing, per-model architecture/auth
 * policy, and chip-folder selection; the example owns URLs and presentation.
 */
export const NPU_BUNDLES: readonly NpuBundle[] = [
  {
    id: 'lfm2_5_230m',
    name: 'LFM2.5 230M (HNPU)',
    url: 'https://huggingface.co/runanywhere/lfm2_5_230m_HNPU/lfm2-5-230m.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 886_089_241,
    contextLength: 512,
  },
  {
    id: 'lfm2_5_350m',
    name: 'LFM2.5 350M (HNPU)',
    url: 'https://huggingface.co/runanywhere/lfm2_5_350m_HNPU/lfm2-5-350m-2048.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 1_441_493_515,
    contextLength: 2_048,
  },
  {
    id: 'qwen3_5_0_8b',
    name: 'Qwen3.5 0.8B (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_5_0_8b_HNPU/qwen3.5-0.8b-1024.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 2_046_527_848,
    contextLength: 1_024,
    supportsThinking: true,
  },
  {
    id: 'qwen3_5_2b',
    name: 'Qwen3.5 2B (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_5_2b_HNPU/qwen3.5-2b-1024.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 4_817_344_861,
    contextLength: 1_024,
  },
  {
    id: 'qwen3_5_4b',
    name: 'Qwen3.5 4B (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_5_4b_HNPU/qwen3.5-4b-1024.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 6_177_585_629,
    contextLength: 1_024,
  },
  {
    id: 'qwen3_0_6b',
    name: 'Qwen3 0.6B (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_0_6b_HNPU/qwen3-0.6b-1024final.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 1_823_248_798,
    contextLength: 1_024,
  },
  {
    id: 'llama3_2_1b',
    name: 'Llama 3.2 1B (HNPU)',
    url: 'https://huggingface.co/runanywhere/llama3_2_1b_HNPU/llama-3.2-1b.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 3_023_821_212,
  },
  {
    id: 'ternary_bonsai_1_7b',
    name: 'Ternary Bonsai 1.7B (HNPU)',
    url: 'https://huggingface.co/runanywhere/ternary_bonsai_1_7b_HNPU/ternary-bonsai-1.7b-1024.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 2_367_579_370,
    contextLength: 1_024,
  },
  {
    id: 'phi_tiny_moe',
    name: 'Phi Tiny MoE (HNPU)',
    url: 'https://huggingface.co/runanywhere/phi_tiny_moe_HNPU/phimoe.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 6_100_212_369,
  },
  {
    id: 'embeddinggemma_300m',
    name: 'EmbeddingGemma 300M (HNPU)',
    url: 'https://huggingface.co/runanywhere/embeddinggemma_300m_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    estimatedSizeBytes: 566_263_339,
  },
  {
    id: 'gemma3n_e4b',
    name: 'Gemma 3n E4B (HNPU)',
    url: 'https://huggingface.co/runanywhere/gemma3n_e4b_HNPU/gemma-3n-E4B-it.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 10_929_816_419,
  },
  {
    id: 'gemma4_e2b',
    name: 'Gemma 4 E2B (HNPU)',
    url: 'https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 10_532_159_450,
  },
  {
    id: 'gemma4_e4b',
    name: 'Gemma 4 E4B (HNPU)',
    url: 'https://huggingface.co/runanywhere/gemma4_e4b_HNPU/gemma-4-E4B.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 13_435_056_195,
  },
  {
    id: 'llama_embed_nemotron_8b',
    name: 'Llama Embed Nemotron 8B (HNPU)',
    url: 'https://huggingface.co/runanywhere/llama_embed_nemotron_8b_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    estimatedSizeBytes: 8_079_101_598,
  },
  {
    id: 'nv_embedcode_7b',
    name: 'NV-EmbedCode 7B (HNPU)',
    url: 'https://huggingface.co/runanywhere/nv_embedcode_7b_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    estimatedSizeBytes: 7_276_868_122,
  },
  {
    id: 'nv_embedqa_1b',
    name: 'NV-EmbedQA 1B (HNPU)',
    url: 'https://huggingface.co/runanywhere/nv_embedqa_1b_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    estimatedSizeBytes: 2_493_026_133,
  },
  {
    id: 'nv_rerankqa_1b',
    name: 'NV-RerankQA 1B (HNPU)',
    url: 'https://huggingface.co/runanywhere/nv_rerankqa_1b_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    estimatedSizeBytes: 2_494_254_905,
  },
  {
    id: 'deepseek_r1_distill_qwen_1_5b',
    name: 'DeepSeek R1 Distill Qwen 1.5B (HNPU)',
    url: 'https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_1_5b_HNPU/DeepSeek-R1-Distill-Qwen-1.5B.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 6_211_227_068,
    supportsThinking: true,
  },
  {
    id: 'deepseek_r1_distill_qwen_7b',
    name: 'DeepSeek R1 Distill Qwen 7B (HNPU)',
    url: 'https://huggingface.co/runanywhere/deepseek_r1_distill_qwen_7b_HNPU/DeepSeek-R1-Distill-Qwen-7B.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 8_210_665_301,
    supportsThinking: true,
  },
  {
    id: 'nemotron_nano_8b',
    name: 'Llama 3.1 Nemotron Nano 8B (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemotron_nano_8b_HNPU/nemotron-nano-8b.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 8_609_694_487,
  },
  {
    id: 'nemoguard_content_8b',
    name: 'NemoGuard 8B Content Safety (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemoguard_8b_content_safety_HNPU/nemoguard-content-8b.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 8_610_354_023,
  },
  {
    id: 'nemoguard_topic_8b',
    name: 'NemoGuard 8B Topic Control (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemoguard_8b_topic_control_HNPU/nemoguard-topic-8b.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 8_609_694_527,
  },
  {
    id: 'qwen3_vl_2b_text',
    name: 'Qwen3-VL 2B Text (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-text-512.json',
    modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    estimatedSizeBytes: 3_220_397_297,
    contextLength: 512,
  },
  {
    id: 'qwen3_vl',
    name: 'Qwen3-VL 2B (HNPU)',
    url: 'https://huggingface.co/runanywhere/qwen3_vl_HNPU/qwen3vl-2b-vlm-512.json',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 3_220_397_297,
    contextLength: 512,
  },
  {
    id: 'internvl3_5_1b',
    name: 'InternVL3.5 1B (HNPU)',
    url: 'https://huggingface.co/runanywhere/internvl3_5_1b_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 3_067_933_894,
    contextLength: 512,
  },
  {
    id: 'gemma4_e2b_vlm',
    name: 'Gemma 4 E2B Image (HNPU)',
    url: 'https://huggingface.co/runanywhere/gemma4_e2b_HNPU/gemma4-e2b-vlm.json',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 10_532_159_450,
  },
  {
    id: 'gemma4_e4b_vlm',
    name: 'Gemma 4 E4B Image (HNPU)',
    url: 'https://huggingface.co/runanywhere/gemma4_e4b_HNPU/gemma-4-E4B-vlm.json',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 13_435_056_195,
  },
  {
    id: 'nemotron_nano_vl_8b',
    name: 'Llama 3.1 Nemotron Nano VL 8B (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemotron_nano_vl_8b_HNPU/nemotron-vl-8b-vlm.json',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 10_057_258_051,
  },
  {
    id: 'lama_dilated',
    name: 'LaMa Dilated (HNPU)',
    url: 'https://huggingface.co/runanywhere/lama_dilated_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
    estimatedSizeBytes: 98_509_597,
  },
  {
    id: 'nemotron_ocr',
    name: 'Nemotron OCR (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemotron_ocr_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 121_193_004,
  },
  {
    id: 'nemotron_ocr_v1',
    name: 'Nemotron OCR v1 (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemotron_ocr_v1_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 121_406_323,
  },
  {
    id: 'nemotron_parse',
    name: 'Nemotron Parse (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemotron_parse_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
    estimatedSizeBytes: 1_995_206_253,
  },
  {
    id: 'siglip2_base',
    name: 'SigLIP2 Base (HNPU)',
    url: 'https://huggingface.co/runanywhere/siglip2_base_HNPU',
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    estimatedSizeBytes: 789_101_244,
  },
  {
    id: 'whisper_base',
    name: 'Whisper Base (HNPU)',
    url: 'https://huggingface.co/runanywhere/whisper_base_HNPU/whisper-base.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 221_522_616,
  },
  {
    id: 'whisper_small',
    name: 'Whisper Small (HNPU)',
    url: 'https://huggingface.co/runanywhere/whisper_small_HNPU/whisper-small.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 676_713_240,
  },
  {
    id: 'moonshine_tiny',
    name: 'Moonshine Tiny (HNPU)',
    url: 'https://huggingface.co/runanywhere/moonshine_tiny_HNPU/moonshine-tiny.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 84_569_427,
  },
  {
    id: 'moonshine_base',
    name: 'Moonshine Base (HNPU)',
    url: 'https://huggingface.co/runanywhere/moonshine_base_HNPU/moonshine-base.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 167_310_675,
  },
  {
    id: 'parakeet_tdt_0_6b_v2',
    name: 'Parakeet TDT 0.6B v2 (HNPU)',
    url: 'https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v2_HNPU/parakeet-tdt-0.6b-v2.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 1_280_063_837,
  },
  {
    id: 'parakeet_tdt_0_6b_v3',
    name: 'Parakeet TDT 0.6B v3 (HNPU)',
    url: 'https://huggingface.co/runanywhere/parakeet_tdt_0.6b_v3_HNPU/parakeet-tdt-0.6b.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 1_317_902_802,
  },
  {
    id: 'parakeet_rnnt_1_1b',
    name: 'Parakeet RNNT 1.1B (HNPU)',
    url: 'https://huggingface.co/runanywhere/parakeet_rnnt_1.1b_HNPU/parakeet-rnnt-1.1b.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 2_211_659_923,
  },
  {
    id: 'canary_qwen_2_5b',
    name: 'Canary Qwen 2.5B (HNPU)',
    url: 'https://huggingface.co/runanywhere/canary_qwen_2.5b_HNPU/v81/canary-qwen-2.5b.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 5_491_333_979,
  },
  {
    id: 'canary_1b_flash',
    name: 'Canary-1B-flash (HNPU)',
    url: 'https://huggingface.co/runanywhere/canary_1b_flash_HNPU/canary-1b-flash.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 1_835_592_227,
  },
  {
    id: 'nemotron_asr_streaming',
    name: 'Nemotron ASR Streaming 0.6B (HNPU)',
    url: 'https://huggingface.co/runanywhere/nemotron_asr_streaming_HNPU/nemotron-3.5-asr-streaming-0.6b.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
    estimatedSizeBytes: 1_361_283_432,
  },
  {
    id: 'melotts_en',
    name: 'MeloTTS EN (HNPU)',
    url: 'https://huggingface.co/runanywhere/melotts_en_HNPU/melotts-en.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    estimatedSizeBytes: 120_439_053,
  },
  {
    id: 'kokoro_en',
    name: 'Kokoro-82M EN (HNPU)',
    url: 'https://huggingface.co/runanywhere/kokoro_en_HNPU/kokoro-en.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    estimatedSizeBytes: 470_739_484,
  },
  {
    id: 'kitten_nano_0_8',
    name: 'Kitten-nano-0.8-fp32 (HNPU)',
    url: 'https://huggingface.co/runanywhere/kitten_nano_0_8_HNPU/kitten_nano08_v81.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    estimatedSizeBytes: 95_842_227,
  },
  {
    id: 'kitten_mini_0_8',
    name: 'Kitten-mini-0.8 (HNPU)',
    url: 'https://huggingface.co/runanywhere/kitten_mini_0_8_HNPU/kitten_mini08_v81.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    estimatedSizeBytes: 778_828_575,
  },
  {
    id: 'kitten_micro_0_8',
    name: 'Kitten-micro-0.8 (HNPU)',
    url: 'https://huggingface.co/runanywhere/kitten_micro_0_8_HNPU/kitten_micro08_v81.json',
    modality: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    estimatedSizeBytes: 338_682_302,
  },
];

export function toNpuRegistrationRequest(
  bundle: NpuBundle
): RegisterModelFromUrlRequest {
  return RegisterModelFromUrlRequest.fromPartial({
    id: bundle.id,
    name: bundle.name,
    url: bundle.url,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    category: bundle.modality,
    source: ModelSource.MODEL_SOURCE_REMOTE,
    memoryRequiredBytes: bundle.estimatedSizeBytes,
    downloadSizeBytes: bundle.estimatedSizeBytes,
    contextLength: bundle.contextLength,
    supportsThinking: bundle.supportsThinking ?? false,
    supportsLora: false,
    description: HNPU_DESCRIPTION,
  });
}

export type NpuCatalogSnapshot = Readonly<{
  registeredModelIds: ReadonlySet<string>;
  revision: number;
}>;

let npuCatalogSnapshot: NpuCatalogSnapshot = {
  registeredModelIds: new Set<string>(),
  revision: 0,
};
const npuCatalogListeners = new Set<() => void>();

export function getNpuCatalogSnapshot(): NpuCatalogSnapshot {
  return npuCatalogSnapshot;
}

export function publishNpuCatalogAcceptance(
  registeredModelIds: Iterable<string>
): void {
  npuCatalogSnapshot = {
    registeredModelIds: new Set(registeredModelIds),
    revision: npuCatalogSnapshot.revision + 1,
  };
  npuCatalogListeners.forEach((listener) => listener());
}

export function subscribeNpuCatalog(listener: () => void): () => void {
  npuCatalogListeners.add(listener);
  return () => npuCatalogListeners.delete(listener);
}

/** Keep ordinary rows and only QHexRT rows accepted by native registration. */
export function isVisibleForNativeNpuCatalog(
  model: Pick<ModelInfo, 'id' | 'framework' | 'preferredFramework'>,
  registeredNpuIds: ReadonlySet<string> = npuCatalogSnapshot.registeredModelIds
): boolean {
  const usesQHexRT =
    model.framework === InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT ||
    model.preferredFramework === InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT;
  return !usesQHexRT || registeredNpuIds.has(model.id);
}

export function visibleNativeNpuCatalogModelOrNull<T extends ModelInfo>(
  model: T | null | undefined,
  registeredNpuIds: ReadonlySet<string> = npuCatalogSnapshot.registeredModelIds
): T | null {
  return model && isVisibleForNativeNpuCatalog(model, registeredNpuIds)
    ? model
    : null;
}

export function filterVisibleNativeNpuCatalog<T extends ModelInfo>(
  models: readonly T[],
  registeredNpuIds: ReadonlySet<string> = npuCatalogSnapshot.registeredModelIds
): T[] {
  return models.filter((model) =>
    isVisibleForNativeNpuCatalog(model, registeredNpuIds)
  );
}
