/**
 * Characterizes which `LoadOptions` fields `models.load()` rejects at
 * preflight because the commons load ABI has no wire path for them yet
 * (PR #605 review issue 8). Per the v4 public API spec, silently dropping
 * an accepted field is forbidden, so unsupported knobs are reported for
 * `models.load` to throw on rather than merely warn about.
 */

import { unsupportedLoadOptionKeys } from '../../../../src/Public/Api/LoadOptionsSupport';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';

describe('unsupportedLoadOptionKeys', () => {
  it('reports nothing for undefined options', () => {
    expect(unsupportedLoadOptionKeys(undefined)).toEqual([]);
  });

  it('does not report framework, which does reach commons', () => {
    expect(
      unsupportedLoadOptionKeys({
        framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      })
    ).toEqual([]);
  });

  it('does not report a single backendPreferences entry', () => {
    expect(
      unsupportedLoadOptionKeys({
        backendPreferences: [{ backend: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP }],
      })
    ).toEqual([]);
  });

  it('reports contextLength, threads, and accelerator individually', () => {
    expect(unsupportedLoadOptionKeys({ contextLength: 4096 })).toEqual([
      'contextLength',
    ]);
    expect(unsupportedLoadOptionKeys({ threads: 4 })).toEqual(['threads']);
    expect(unsupportedLoadOptionKeys({ accelerator: 'gpu' })).toEqual(['accelerator']);
    expect(unsupportedLoadOptionKeys({ useGpu: true })).toEqual(['accelerator']);
  });

  it('reports multiple backendPreferences entries', () => {
    const keys = unsupportedLoadOptionKeys({
      backendPreferences: [
        { backend: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP },
        { backend: InferenceFramework.INFERENCE_FRAMEWORK_ONNX },
      ],
    });
    expect(keys).toHaveLength(1);
    expect(keys[0]).toMatch(/^backendPreferences/);
  });

  it('combines every unsupported knob in a stable order', () => {
    expect(
      unsupportedLoadOptionKeys({
        contextLength: 4096,
        threads: 4,
        accelerator: 'cpu',
      })
    ).toEqual(['contextLength', 'threads', 'accelerator']);
  });
});
