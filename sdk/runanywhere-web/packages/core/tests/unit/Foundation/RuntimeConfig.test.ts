import { afterEach, describe, expect, it } from 'vitest';
import {
  Runtime,
  setAccelerationSwitcher,
  setActiveAccelerationMode,
} from '../../../src/Foundation/RuntimeConfig';

afterEach(() => {
  setAccelerationSwitcher(null);
  setActiveAccelerationMode(null);
  Runtime.preferred = 'auto';
});

describe('Runtime acceleration state', () => {
  it('preserves the backend-reported mode when it differs from the request', async () => {
    setActiveAccelerationMode('cpu');
    setAccelerationSwitcher(async (requested) => {
      expect(requested).toBe('webgpu');
      // Simulate WebGPU capability resolution or fallback choosing CPU.
      setActiveAccelerationMode('cpu');
    });

    await Runtime.setAcceleration('webgpu');

    expect(Runtime.preferred).toBe('webgpu');
    expect(Runtime.active).toBe('cpu');
  });
});
