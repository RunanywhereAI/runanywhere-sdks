import { afterEach, describe, expect, it } from 'vitest';
import { ProtoErrorCode } from '../../../../src/Foundation/SDKException';
import { RunAnywhere } from '../../../../src/Public/RunAnywhere';
import {
  Diffusion,
  cancelImageGeneration,
  generateImage,
  generateImageStream,
  inpaint,
  setDiffusionAvailabilityProvider,
} from '../../../../src/Public/Extensions/RunAnywhere+Diffusion';
import { clearRunanywhereModule } from '../../../../src/runtime/EmscriptenModule';

describe('RunAnywhere diffusion API (core lifecycle facade)', () => {
  afterEach(() => {
    setDiffusionAvailabilityProvider(null);
    clearRunanywhereModule();
  });

  it('reports unavailable until a diffusion WASM capability is registered', () => {
    expect(Diffusion.availability()).toMatchObject({
      available: false,
      reason: expect.stringContaining('Web diffusion is not available'),
    });
    expect(RunAnywhere.diffusion.availability().available).toBe(false);
  });

  it('surfaces an optional diagnostic provider without claiming a capability', () => {
    setDiffusionAvailabilityProvider(() => ({
      available: false,
      reason: 'Browser diffusion engine not linked into this WASM build.',
      acceleration: 'webgpu',
    }));

    expect(RunAnywhere.diffusion.availability()).toEqual({
      available: false,
      reason: 'Browser diffusion engine not linked into this WASM build.',
      acceleration: 'webgpu',
    });
  });

  it('exports lifecycle image-generation verbs with typed feature errors', async () => {
    await expect(generateImage({ prompt: 'a sunset' })).rejects.toMatchObject({
      code: expect.any(Number),
    });
    await expect(cancelImageGeneration()).rejects.toMatchObject({
      code: ProtoErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
    });
    await expect(inpaint({
      inputImage: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      maskImage: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    })).rejects.toBeTruthy();

    const iterator = generateImageStream({ prompt: 'a sunset' })[Symbol.asyncIterator]();
    await expect(iterator.next()).rejects.toBeTruthy();
    expect(typeof RunAnywhere.generateImage).toBe('function');
    expect(typeof RunAnywhere.generateImageStream).toBe('function');
    expect(typeof RunAnywhere.cancelImageGeneration).toBe('function');
    expect(typeof RunAnywhere.inpaint).toBe('function');
  });
});
