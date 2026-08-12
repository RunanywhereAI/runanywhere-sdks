import { afterEach, describe, expect, it, vi } from 'vitest';
import { Hardware } from '../../../../src/Public/Extensions/RunAnywhere+Hardware';

describe('Hardware.profile', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('collects browser CPU, memory, GPU and user-agent details', async () => {
    vi.stubGlobal('navigator', {
      hardwareConcurrency: 12,
      deviceMemory: 16,
      userAgent: 'TestBrowser/1.0',
      storage: { getDirectory: vi.fn() },
      gpu: {
        requestAdapter: vi.fn().mockResolvedValue({
          requestAdapterInfo: vi.fn().mockResolvedValue({
            vendor: 'TestVendor',
            architecture: 'TestGPU',
            description: 'Test GPU adapter',
          }),
        }),
      },
    });

    await expect(Hardware.profile()).resolves.toMatchObject({
      hardwareConcurrency: 12,
      deviceMemoryGB: 16,
      userAgent: 'TestBrowser/1.0',
      hasWebGPU: true,
      gpuAdapterInfo: { vendor: 'TestVendor', architecture: 'TestGPU' },
    });
  });
});
