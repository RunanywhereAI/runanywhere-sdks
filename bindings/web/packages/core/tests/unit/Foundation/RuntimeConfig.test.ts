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

  it('exposes advisory per-module WASM32 budgets below the address-space ceiling', () => {
    const budget = Runtime.memoryBudget;

    expect(budget.wasm32AddressSpaceBytes).toBe(4 * 1024 ** 3);
    expect(
      Object.values(budget.perModuleSoftLimitBytes)
        .every((limit) => limit > 0 && limit < budget.wasm32AddressSpaceBytes),
    ).toBe(true);
  });
});
