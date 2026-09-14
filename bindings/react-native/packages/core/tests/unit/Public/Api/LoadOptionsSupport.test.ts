/**
 * Characterizes which `LoadOptions` fields `models.load()` rejects at
 * preflight because the commons load ABI has no wire path for them yet
 * (PR #605 review issue 8). Per the v4 public API spec, silently dropping
 * an accepted field is forbidden, so unsupported knobs are reported for
 * `models.load` to throw on rather than merely warn about.
 *
 * `contextLength` and the ordered `backendPreferences` list are carried by
 * `ModelLoadRequest` now, so only `threads` (retired) and `accelerator`
 * remain unsupported.
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

  it('does not report contextLength, which now reaches commons', () => {
    expect(unsupportedLoadOptionKeys({ contextLength: 4096 })).toEqual([]);
  });

  it('does not report ordered backendPreferences, which now reach commons', () => {
    expect(
      unsupportedLoadOptionKeys({
        backendPreferences: [
          { backend: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP },
          { backend: InferenceFramework.INFERENCE_FRAMEWORK_ONNX },
        ],
      })
    ).toEqual([]);
  });

  it('reports threads and accelerator individually', () => {
    expect(unsupportedLoadOptionKeys({ threads: 4 })).toEqual(['threads']);
    expect(unsupportedLoadOptionKeys({ accelerator: 'gpu' })).toEqual(['accelerator']);
    expect(unsupportedLoadOptionKeys({ useGpu: true })).toEqual(['accelerator']);
  });

  it('combines every unsupported knob in a stable order', () => {
    expect(
      unsupportedLoadOptionKeys({
        contextLength: 4096,
        threads: 4,
        accelerator: 'cpu',
      })
    ).toEqual(['threads', 'accelerator']);
  });
});
