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

describe('React Native QHexRT catalog', () => {
  it('keeps 48 unique app-owned URL and presentation rows', () => {
    expect(NPU_BUNDLES).toHaveLength(48);
    expect(new Set(NPU_BUNDLES.map((bundle) => bundle.id))).toHaveProperty(
      'size',
      48
    );
    expect(
      NPU_BUNDLES.every((bundle) => bundle.url.startsWith('https://'))
    ).toBe(true);
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
