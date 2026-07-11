import { HexagonArch } from '@runanywhere/proto-ts/hardware_profile';
import {
  InferenceFramework,
  ModelCategory,
  ModelInfo,
  ModelSource,
} from '@runanywhere/proto-ts/model_types';
import {
  filterVisibleNativeNpuCatalog,
  getNpuCatalogSnapshot,
  NPU_BUNDLES,
  publishNpuCatalogAcceptance,
  subscribeNpuCatalog,
  toNpuRegistrationRequest,
  visibleNativeNpuCatalogModelOrNull,
} from '../../src/services/NpuModelCatalog';

const V75 = HexagonArch.HEXAGON_ARCH_V75;
const V79 = HexagonArch.HEXAGON_ARCH_V79;
const V81 = HexagonArch.HEXAGON_ARCH_V81;

const EXPECTED_ARCHES: Readonly<Record<string, readonly HexagonArch[]>> = {
  lfm2_5_230m: [V75, V79, V81],
  lfm2_5_350m: [V75, V79, V81],
  qwen3_5_0_8b: [V75, V79, V81],
  qwen3_5_2b: [V75, V79, V81],
  qwen3_5_4b: [V79, V81],
  qwen3_0_6b: [V75, V79, V81],
  llama3_2_1b: [V79, V81],
  ternary_bonsai_1_7b: [V75, V81],
  phi_tiny_moe: [V79, V81],
  embeddinggemma_300m: [V75, V79, V81],
  gemma3n_e4b: [V81],
  gemma4_e2b: [V79, V81],
  gemma4_e4b: [V81],
  llama_embed_nemotron_8b: [V81],
  nv_embedcode_7b: [V81],
  nv_embedqa_1b: [V75, V79, V81],
  nv_rerankqa_1b: [V75, V79, V81],
  deepseek_r1_distill_qwen_1_5b: [V79, V81],
  deepseek_r1_distill_qwen_7b: [V81],
  nemotron_nano_8b: [V81],
  nemoguard_content_8b: [V81],
  nemoguard_topic_8b: [V81],
  qwen3_vl_2b_text: [V81],
  qwen3_vl: [V75, V79],
  internvl3_5_1b: [V75, V79, V81],
  gemma4_e2b_vlm: [V79, V81],
  gemma4_e4b_vlm: [V81],
  nemotron_nano_vl_8b: [V81],
  lama_dilated: [V79, V81],
  nemotron_ocr: [V75],
  nemotron_ocr_v1: [V75],
  nemotron_parse: [V75],
  siglip2_base: [V75, V79, V81],
  whisper_base: [V75, V79, V81],
  whisper_small: [V75, V79, V81],
  moonshine_tiny: [V75, V79, V81],
  moonshine_base: [V75, V79, V81],
  parakeet_tdt_0_6b_v2: [V75, V81],
  parakeet_tdt_0_6b_v3: [V75, V81],
  parakeet_rnnt_1_1b: [V75, V81],
  canary_qwen_2_5b: [V81],
  canary_1b_flash: [V75, V81],
  nemotron_asr_streaming: [V75, V81],
  melotts_en: [V75, V79, V81],
  kokoro_en: [V75, V81],
  kitten_nano_0_8: [V75, V81],
  kitten_mini_0_1: [V81],
  kitten_mini_0_8: [V81],
  kitten_micro_0_8: [V81],
  kitten_nano_0_2: [V81],
  kitten_nano_0_1: [V81],
};

describe('React Native QHexRT catalog', () => {
  it('matches all 51 Kotlin rows and their exact Hexagon architecture sets', () => {
    expect(NPU_BUNDLES).toHaveLength(51);
    expect(NPU_BUNDLES.map((bundle) => bundle.id)).toEqual(
      Object.keys(EXPECTED_ARCHES)
    );
    expect(
      Object.fromEntries(
        NPU_BUNDLES.map((bundle) => [bundle.id, bundle.supportedArches])
      )
    ).toEqual(EXPECTED_ARCHES);
  });

  it('keeps Kotlin context, thinking, auth, and RAG embedding metadata', () => {
    expect(
      Object.fromEntries(
        NPU_BUNDLES.filter((bundle) => bundle.contextLength !== undefined).map(
          (bundle) => [bundle.id, bundle.contextLength]
        )
      )
    ).toEqual({
      lfm2_5_230m: 512,
      lfm2_5_350m: 2_048,
      qwen3_5_0_8b: 1_024,
      qwen3_5_2b: 1_024,
      qwen3_5_4b: 1_024,
      qwen3_0_6b: 1_024,
      ternary_bonsai_1_7b: 1_024,
      qwen3_vl_2b_text: 512,
      qwen3_vl: 512,
      internvl3_5_1b: 512,
    });
    expect(
      NPU_BUNDLES.filter((bundle) => bundle.supportsThinking).map(
        (bundle) => bundle.id
      )
    ).toEqual([
      'qwen3_5_0_8b',
      'deepseek_r1_distill_qwen_1_5b',
      'deepseek_r1_distill_qwen_7b',
    ]);
    expect(
      NPU_BUNDLES.filter((bundle) => bundle.requiresHfAuth).map(
        (bundle) => bundle.id
      )
    ).toEqual(['kokoro_en']);
    expect(
      NPU_BUNDLES.filter(
        (bundle) => bundle.modality === ModelCategory.MODEL_CATEGORY_EMBEDDING
      ).map((bundle) => bundle.id)
    ).toEqual([
      'embeddinggemma_300m',
      'llama_embed_nemotron_8b',
      'nv_embedcode_7b',
      'nv_embedqa_1b',
      'nv_rerankqa_1b',
      'siglip2_base',
    ]);
  });

  it('maps app metadata into the canonical device-registration request', () => {
    const bundle = NPU_BUNDLES.find(
      (candidate) => candidate.id === 'qwen3_5_0_8b'
    );
    expect(bundle).toBeDefined();
    const request = toNpuRegistrationRequest(bundle!);

    expect(request).toMatchObject({
      id: 'qwen3_5_0_8b',
      name: 'Qwen3.5 0.8B (HNPU)',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      source: ModelSource.MODEL_SOURCE_REMOTE,
      memoryRequiredBytes: 2_046_527_848,
      downloadSizeBytes: 2_046_527_848,
      contextLength: 1_024,
      supportsThinking: true,
      supportsLora: false,
      description: 'Qualcomm Hexagon NPU model bundle.',
    });
  });

  it('retains native IDs, advances revisions, and hides stale QHexRT rows', () => {
    const ordinary = ModelInfo.fromPartial({
      id: 'cpu-model',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    });
    const accepted = ModelInfo.fromPartial({
      id: 'accepted-npu',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    });
    const stale = ModelInfo.fromPartial({
      id: 'stale-npu',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    });
    const stalePreferred = ModelInfo.fromPartial({
      id: 'stale-preferred-npu',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      preferredFramework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    });
    const acceptedPreferred = ModelInfo.fromPartial({
      id: 'accepted-preferred-npu',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      preferredFramework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
    });
    const listener = jest.fn();
    const unsubscribe = subscribeNpuCatalog(listener);
    const previousRevision = getNpuCatalogSnapshot().revision;

    publishNpuCatalogAcceptance(['accepted-npu', 'accepted-preferred-npu']);
    expect(getNpuCatalogSnapshot().revision).toBe(previousRevision + 1);
    expect(
      filterVisibleNativeNpuCatalog([
        ordinary,
        accepted,
        stale,
        stalePreferred,
        acceptedPreferred,
      ]).map((model) => model.id)
    ).toEqual(['cpu-model', 'accepted-npu', 'accepted-preferred-npu']);
    expect(visibleNativeNpuCatalogModelOrNull(stalePreferred)).toBeNull();
    expect(visibleNativeNpuCatalogModelOrNull(acceptedPreferred)).toBe(
      acceptedPreferred
    );

    publishNpuCatalogAcceptance(['accepted-npu', 'accepted-preferred-npu']);
    expect(getNpuCatalogSnapshot().revision).toBe(previousRevision + 2);
    expect(listener).toHaveBeenCalledTimes(2);
    unsubscribe();
  });
});
