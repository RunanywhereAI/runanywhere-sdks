/**
 * Characterizes which `LoadOptions` fields `models.load()` warns about
 * because the commons load ABI has no wire path for them yet
 * (PR #605 review issue 8).
 */

import { ignoredLoadOptionKeys } from '../../../../src/Public/Api/LoadOptionsSupport';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';

describe('ignoredLoadOptionKeys', () => {
  it('reports nothing for undefined options', () => {
    expect(ignoredLoadOptionKeys(undefined)).toEqual([]);
  });

  it('does not report framework, which does reach commons', () => {
    expect(
      ignoredLoadOptionKeys({
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      })
    ).toEqual([]);
  });

  it('reports contextLength, threads, and useGpu individually', () => {
    expect(ignoredLoadOptionKeys({ contextLength: 4096 })).toEqual([
      'contextLength',
    ]);
    expect(ignoredLoadOptionKeys({ threads: 4 })).toEqual(['threads']);
    expect(ignoredLoadOptionKeys({ useGpu: true })).toEqual(['useGpu']);
  });

  it('combines every ignored knob in a stable order', () => {
    expect(
      ignoredLoadOptionKeys({ contextLength: 4096, threads: 4, useGpu: false })
    ).toEqual(['contextLength', 'threads', 'useGpu']);
  });
});
