import { describe, expect, it } from 'vitest';
import {
  InferenceFramework,
  ModelCategory,
  ModelFormat,
} from '@runanywhere/proto-ts/model_types';
import {
  WebModelCompatibilityCode,
  getCatalog,
  webModelCompatibility,
  webSizeCompatibility,
} from './model-catalog';

describe('Web catalog integrity', () => {
  it('registers every catalog id exactly once', () => {
    // `registerModelCatalog()` iterates CATALOG and registers each entry, so a
    // repeated id silently overwrites the earlier registration and makes the
    // `registered === CATALOG.length` check meaningless. Four Bonsai rows were
    // duplicated this way.
    const ids = getCatalog().map(({ id }) => id);
    const duplicates = ids.filter((id, index) => ids.indexOf(id) !== index);

    expect(duplicates).toEqual([]);
    expect(new Set(ids).size).toBe(getCatalog().length);
  });

  it('keeps one quantization per llama.cpp model', () => {
    // Two quants of the same model cost a catalog slot and a "which one?"
    // decision without adding a capability. lfm2-350m-q8_0 is the row this
    // rule drops (the file header documents the omission).
    expect(getCatalog().some(({ id }) => id === 'lfm2-350m-q8_0')).toBe(false);
    expect(getCatalog().some(({ id }) => id === 'lfm2-350m-q4_k_m')).toBe(true);
  });

  it('registers the LFM2.5 230M Q4_K_M row and clears the WASM32 gate', () => {
    const model = getCatalog().find(({ id }) => id === 'lfm2.5-230m-q4_k_m');

    expect(model).toMatchObject({
      name: 'LiquidAI LFM2.5 230M Q4_K_M',
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      format: ModelFormat.MODEL_FORMAT_GGUF,
      downloadSizeBytes: 153_406_304,
      memoryRequiredBytes: 190_000_000,
      downloadUrl:
        'https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF/resolve/main/LFM2.5-230M-Q4_K_M.gguf',
    });
    expect(model && webModelCompatibility(model)).toEqual({ supported: true });
  });

  it('keeps the four PrismML Bonsai 1-bit rows with vendor-and-quant names', () => {
    const bonsai = getCatalog().filter(({ id }) => id.startsWith('bonsai-'));

    expect(bonsai.map(({ id }) => id)).toEqual([
      'bonsai-1.7b-q1_0',
      'bonsai-4b-q1_0',
      'bonsai-8b-q1_0',
      'bonsai-27b-q1_0',
    ]);
    for (const entry of bonsai) {
      expect(entry.name).toMatch(/^PrismML Bonsai .* 1-bit Q1_0/);
      expect(entry.supportsThinking).toBe(true);
    }

    // Only the 27B flagship is WASM32-gated; the other three run in-browser.
    for (const entry of bonsai.filter(({ id }) => id !== 'bonsai-27b-q1_0')) {
      expect(webModelCompatibility(entry)).toEqual({ supported: true });
    }
    const flagship = bonsai.find(({ id }) => id === 'bonsai-27b-q1_0');
    expect(flagship && webModelCompatibility(flagship)).toMatchObject({
      supported: false,
      code: WebModelCompatibilityCode.WASM32_ADDRESS_SPACE,
      actionLabel: 'Too large for Web WASM',
    });
  });
});

describe('NVIDIA Web catalog support', () => {
  it('catalogs but rejects Nemotron Mini before its simultaneous WASM32 footprint is downloaded', () => {
    const model = getCatalog().find(
      ({ id }) => id === 'nemotron-mini-4b-instruct-q4_k_m',
    );

    expect(model).toMatchObject({
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      format: ModelFormat.MODEL_FORMAT_GGUF,
      downloadSizeBytes: 2_697_387_072,
      contextLength: 4096,
      downloadUrl:
        'https://huggingface.co/bartowski/Nemotron-Mini-4B-Instruct-GGUF/resolve/fb49cde090c86092d89905bea2ffc41c23c2615e/Nemotron-Mini-4B-Instruct-Q4_K_M.gguf',
    });
    expect(model && webModelCompatibility(model)).toMatchObject({
      supported: false,
      code: WebModelCompatibilityCode.WASM32_ADDRESS_SPACE,
    });
  });

  it('registers the validated Nemotron 3 Embed llama.cpp artifact', () => {
    const model = getCatalog().find(
      ({ id }) => id === 'nemotron-3-embed-1b-q4_k_m',
    );

    expect(model).toMatchObject({
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      format: ModelFormat.MODEL_FORMAT_GGUF,
      downloadSizeBytes: 749_352_096,
      downloadUrl:
        'https://huggingface.co/zenmagnets/Nemotron-3-Embed-1B-Q4_K_M-GGUF/resolve/06df1fde6f7009c91f6cc3cd520081921929a678/nemotron-3-embed-1b-q4_k_m.gguf',
    });
    expect(model && webModelCompatibility(model)).toEqual({ supported: true });
  });

  it('registers the validated Llama Nemotron Embed 1B v2 artifact', () => {
    const model = getCatalog().find(
      ({ id }) => id === 'llama-nemotron-embed-1b-v2-q4_k_m',
    );

    expect(model).toMatchObject({
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      format: ModelFormat.MODEL_FORMAT_GGUF,
      downloadSizeBytes: 807_690_624,
      downloadUrl:
        'https://huggingface.co/mykor/llama-nemotron-embed-1b-v2-GGUF/resolve/bf7c9832b1d76f86777379e58b7b74805ee58006/llama-nemotron-embed-1B-v2-Q4_K_M.gguf',
    });
    expect(model && webModelCompatibility(model)).toEqual({ supported: true });
  });

  it('rejects the standard Nemotron Nano 8B Q4_K_M artifact before download', () => {
    expect(getCatalog().some(
      ({ downloadUrl }) => downloadUrl.includes('nvidia_Llama-3.1-Nemotron-Nano-8B-v1'),
    )).toBe(false);
    expect(webSizeCompatibility(4_920_736_864, 4_920_736_864)).toMatchObject({
      supported: false,
      code: WebModelCompatibilityCode.WASM32_ADDRESS_SPACE,
    });
  });

  it('registers exact pinned NVIDIA Sherpa-ONNX bundles', () => {
    const expected = new Map([
      ['sherpa-nemo-parakeet-tdt-0.6b-v2-int8', ['1ab9323565ddb038682214b292f588070a538ce2', 661_190_513]],
      ['sherpa-nemo-parakeet-tdt-0.6b-v3-int8', ['2bda32ec70b097a55adaa07d9a7173915b43cc78', 670_478_772]],
      ['sherpa-nemo-canary-180m-flash-int8', ['9077164e0d3dd1d5353743e89ceaa1d3a770838c', 207_170_046]],
      ['sherpa-nemotron-3.5-asr-streaming-0.6b-560ms-int8', ['ab43d895f5985b1bbab8b6eac8607fcdc05343f3', 682_215_356]],
    ] as const);

    for (const [id, [revision, sizeBytes]] of expected) {
      const model = getCatalog().find((entry) => entry.id === id);
      expect(model).toMatchObject({
        framework: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        format: ModelFormat.MODEL_FORMAT_ONNX,
        downloadSizeBytes: sizeBytes,
      });
      expect(model?.files?.length).toBeGreaterThanOrEqual(3);
      expect(model?.files?.every(({ url }) => url.includes(`/resolve/${revision}/`))).toBe(true);
      expect(model?.files?.some(({ filename }) => filename === 'tokens.txt')).toBe(true);
    }

    const nemotron = getCatalog().find(
      ({ id }) => id === 'sherpa-nemotron-3.5-asr-streaming-0.6b-560ms-int8',
    );
    expect(nemotron?.files?.map(({ filename, sizeBytes }) => [filename, sizeBytes])).toEqual([
      ['encoder.int8.onnx', 657_601_403],
      ['decoder.int8.onnx', 14_978_075],
      ['joiner.int8.onnx', 9_504_438],
      ['tokens.txt', 131_440],
    ]);
    expect(nemotron && webModelCompatibility(nemotron)).toEqual({ supported: true });
  });
});
