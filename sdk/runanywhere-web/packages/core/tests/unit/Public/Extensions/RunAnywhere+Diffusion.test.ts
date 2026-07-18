import { afterEach, describe, expect, it } from 'vitest';
import { ProtoErrorCode } from '../../../../src/Foundation/SDKException';
import { RunAnywhere } from '../../../../src/Public/RunAnywhere';
import {
  Diffusion,
  cancelImageGeneration,
  generateImage,
  generateImageStream,
  setDiffusionAvailabilityProvider,
} from '../../../../src/Public/Extensions/RunAnywhere+Diffusion';
import { clearRunanywhereModule } from '../../../../src/runtime/EmscriptenModule';

describe('RunAnywhere diffusion API shell', () => {
  afterEach(() => {
    setDiffusionAvailabilityProvider(null);
    clearRunanywhereModule();
  });

  it('reports unavailable until a real diffusion WASM adapter exists', () => {
    expect(Diffusion.availability()).toMatchObject({
      available: false,
      reason: expect.stringContaining('Web diffusion is not available'),
    });
    expect(RunAnywhere.diffusion.availability().available).toBe(false);
  });

  it('surfaces the package shell state without claiming a capability', () => {
    setDiffusionAvailabilityProvider(() => ({
      available: false,
      reason: 'Web diffusion is not available: no WebGPU/WASM diffusion engine has been shipped.',
      acceleration: 'webgpu',
    }));

    expect(RunAnywhere.diffusion.availability()).toEqual({
      available: false,
      reason: 'Web diffusion is not available: no WebGPU/WASM diffusion engine has been shipped.',
      acceleration: 'webgpu',
    });
  });

  it('exports unavailable image-generation verbs with a typed feature error', async () => {
    await expect(generateImage({ prompt: 'a sunset' })).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
      message: expect.stringContaining('Feature not available: generateImage'),
    });
    await expect(cancelImageGeneration()).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
    });

    const iterator = generateImageStream({ prompt: 'a sunset' })[Symbol.asyncIterator]();
    await expect(iterator.next()).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
    });
    expect(typeof RunAnywhere.generateImage).toBe('function');
    expect(typeof RunAnywhere.generateImageStream).toBe('function');
    expect(typeof RunAnywhere.cancelImageGeneration).toBe('function');
  });
});
