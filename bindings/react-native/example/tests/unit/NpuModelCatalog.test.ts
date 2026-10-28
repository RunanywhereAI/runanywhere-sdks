import {
  HexagonArch,
  NpuCapability,
} from '@runanywhere/proto-ts/hardware_profile';
import {
  InferenceFramework,
  ModelCategory,
  ModelInfo,
  ModelSource,
} from '@runanywhere/proto-ts/model_types';
import {
  filterVisibleNativeNpuCatalog,
  getNpuCatalogSnapshot,
  isNpuBundleEligible,
  NPU_BUNDLES,
  publishNpuCatalogAcceptance,
  subscribeNpuCatalog,
  toNpuModelRegistration,
  visibleNativeNpuCatalogModelOrNull,
} from '../../src/services/NpuModelCatalog';

// Golden eligible IDs from kModelPolicies at 259521e299bb, intersected with
// this app catalog. Kitten nano deliberately selects only its v81 manifest.
const eligibleIdsByArchitecture: ReadonlyArray<
  readonly [HexagonArch, readonly string[]]
> = [
  [
    HexagonArch.HEXAGON_ARCH_V75,
    [
      'canary_1b_flash',
      'embeddinggemma_300m',
      'internvl3_5_1b',
      'kokoro_en',
      'lfm2_5_230m',
      'lfm2_5_2_6b',
      'lfm2_5_350m',
      'melotts_en',
      'moonshine_base',
      'moonshine_tiny',
      'nemotron_asr_streaming',
      'nemotron_nano_8b',
      'nemotron_ocr',
      'nemotron_ocr_v1',
      'nemotron_parse',
      'nv_embedqa_1b',
      'nv_rerankqa_1b',
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
  ],
  [
    HexagonArch.HEXAGON_ARCH_V79,
    [
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
  ],
  [
    HexagonArch.HEXAGON_ARCH_V81,
    [
      'canary_1b_flash',
      'canary_qwen_2_5b',
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
  ],
];

describe('React Native QHexRT catalog', () => {
  it('keeps 49 unique app-owned URL and presentation rows', () => {
    expect(NPU_BUNDLES).toHaveLength(49);
    expect(new Set(NPU_BUNDLES.map((bundle) => bundle.id))).toHaveProperty(
      'size',
      49
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
      lfm2_5_2_6b: 512,
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
      'lfm2_5_2_6b',
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

  it('forwards explicit QHexRT registration metadata through the core API', () => {
    const bundle = NPU_BUNDLES.find((row) => row.id === 'qwen3_5_0_8b');
    expect(bundle).toBeDefined();

    const registration = toNpuModelRegistration(bundle!);
    expect(registration).toMatchObject({
      id: 'qwen3_5_0_8b',
      name: 'Qwen3.5 0.8B (HNPU)',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      memoryRequirementBytes: 2_046_527_848,
      contextLength: 1_024,
      supportsThinking: true,
      source: ModelSource.MODEL_SOURCE_REMOTE,
      description: 'Qualcomm Hexagon NPU model bundle.',
    });
    expect(registration).not.toHaveProperty('downloadSizeBytes');
    expect(registration).not.toHaveProperty('supportsLora');
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

  it.each([
    ['pinned match', 'canary_qwen_2_5b', HexagonArch.HEXAGON_ARCH_V81, true],
    [
      'pinned mismatch',
      'canary_qwen_2_5b',
      HexagonArch.HEXAGON_ARCH_V75,
      false,
    ],
    ['explicit exclusion', 'kokoro_en', HexagonArch.HEXAGON_ARCH_V79, false],
  ] as const)('handles %s', (_label, id, hexagonArch, expected) => {
    const bundle = NPU_BUNDLES.find((row) => row.id === id)!;
    expect(
      isNpuBundleEligible(
        bundle,
        NpuCapability.fromPartial({
          supported: true,
          hexagonArch,
        })
      )
    ).toBe(expected);
  });

  it('rejects every row on unsupported devices, including matching pins', () => {
    for (const [hexagonArch] of eligibleIdsByArchitecture) {
      const capability = NpuCapability.fromPartial({
        supported: false,
        hexagonArch,
      });
      expect(
        NPU_BUNDLES.filter((row) => isNpuBundleEligible(row, capability))
      ).toEqual([]);
    }
  });

  it.each(eligibleIdsByArchitecture)(
    'preserves the complete catalog eligibility matrix for %s',
    (hexagonArch, expectedIds) => {
      const capability = NpuCapability.fromPartial({
        supported: true,
        hexagonArch,
      });
      expect(
        NPU_BUNDLES.filter((row) => isNpuBundleEligible(row, capability))
          .map((row) => row.id)
          .sort()
      ).toEqual(expectedIds);
    }
  );

  it('pins every architecture named by a URL folder or manifest filename', () => {
    const architectureByName = {
      '75': HexagonArch.HEXAGON_ARCH_V75,
      '79': HexagonArch.HEXAGON_ARCH_V79,
      '81': HexagonArch.HEXAGON_ARCH_V81,
    } as const;
    const pinnedUrlIds: string[] = [];
    for (const row of NPU_BUNDLES) {
      const matches = [
        ...new URL(row.url).pathname.matchAll(
          /(?:^|[/_-])v(75|79|81)(?=[/_.-]|$)/g
        ),
      ];
      if (matches.length > 0) pinnedUrlIds.push(row.id);
      for (const match of matches) {
        expect(row.pinnedArchitecture).toBe(
          architectureByName[match[1] as keyof typeof architectureByName]
        );
      }
    }
    expect(pinnedUrlIds.sort()).toEqual([
      'canary_qwen_2_5b',
      'kitten_micro_0_8',
      'kitten_mini_0_8',
      'kitten_nano_0_8',
    ]);
  });
});
