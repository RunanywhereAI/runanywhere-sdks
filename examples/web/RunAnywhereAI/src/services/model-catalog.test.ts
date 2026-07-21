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
  });
});
