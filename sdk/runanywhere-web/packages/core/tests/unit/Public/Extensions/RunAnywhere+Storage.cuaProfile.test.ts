/**
 * Register-mapping coverage for `cuaProfile` (PR #605 review issue 9):
 * `RegisterModelOptions.cuaProfile` / `RegisterMultiFileOptions.cuaProfile`
 * must land on the built `ModelInfo.cuaProfile`, matching Swift/Kotlin/RN.
 */

import { describe, expect, it } from 'vitest';
import { InferenceFramework, ModelFileRole } from '@runanywhere/proto-ts/model_types';
import {
  buildMultiFileModelInfo,
  buildSingleFileModelInfo,
} from '../../../../src/Public/Extensions/RunAnywhere+Storage';

describe('register mapping: cuaProfile', () => {
  it('single-file registration carries cuaProfile onto ModelInfo', () => {
    const model = buildSingleFileModelInfo(
      'https://example.com/fara.gguf',
      'Fara1.5',
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      { id: 'fara1.5', cuaProfile: 'fara', contextLength: 4096 }
    );
    expect(model.cuaProfile).toBe('fara');
  });

  it('single-file registration omits cuaProfile when not supplied', () => {
    const model = buildSingleFileModelInfo(
      'https://example.com/model.gguf',
      'Some Model',
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      { id: 'some-model', contextLength: 4096 }
    );
    expect(model.cuaProfile).toBeUndefined();
  });

  it('multi-file registration carries cuaProfile onto ModelInfo', () => {
    const model = buildMultiFileModelInfo({
      id: 'fara1.5-4b-q4_k_m',
      name: 'Fara1.5 4B',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      files: [
        {
          url: 'https://example.com/fara.gguf',
          filename: 'fara.gguf',
          role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
          sizeBytes: 1000,
        },
        {
          url: 'https://example.com/mmproj-fara.gguf',
          filename: 'mmproj-fara.gguf',
          role: ModelFileRole.MODEL_FILE_ROLE_COMPANION,
          sizeBytes: 500,
        },
      ],
      cuaProfile: 'fara',
      contextLength: 4096,
    });
    expect(model.cuaProfile).toBe('fara');
  });
});
