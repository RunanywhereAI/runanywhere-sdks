import { describe, expect, it, vi } from 'vitest';

import { readFileSync } from 'node:fs';

import { CommonsModule, type CoreCommonsModule } from '../../../src/runtime/CommonsModule';

describe('CommonsModule shutdown', () => {
  it('quiesces callbacks and clears every native state owner before releasing adapters', () => {
    const calls: string[] = [];
    const bridge = new CommonsModule();
    const module = {
      _rac_shutdown: vi.fn(() => calls.push('core')),
    } as unknown as CoreCommonsModule;
    const internals = bridge as unknown as {
      _module: CoreCommonsModule;
      _loaded: boolean;
      _deviceRegistrationAdapter: { cleanup(): void };
      _platformAdapter: { cleanup(): void };
    };
    internals._module = module;
    internals._loaded = true;
    internals._deviceRegistrationAdapter = {
      cleanup: () => calls.push('device'),
    };
    internals._platformAdapter = {
      cleanup: () => calls.push('platform'),
    };

    bridge.shutdown();

    expect(calls).toEqual(['device', 'core', 'platform']);
    expect(bridge.isLoaded).toBe(false);
  });

  it('propagates native shutdown failure after cleanup and retries the retained owner', () => {
    const calls: string[] = [];
    let shouldFail = true;
    const bridge = new CommonsModule();
    const module = {
      _rac_shutdown: vi.fn(() => {
        calls.push('core');
        if (shouldFail) throw new Error('forced native shutdown failure');
      }),
    } as unknown as CoreCommonsModule;
    const internals = bridge as unknown as {
      _module: CoreCommonsModule;
      _loaded: boolean;
      _deviceRegistrationAdapter: { cleanup(): void };
      _platformAdapter: { cleanup(): void };
    };
    internals._module = module;
    internals._loaded = true;
    internals._deviceRegistrationAdapter = {
      cleanup: () => calls.push('device'),
    };
    internals._platformAdapter = {
      cleanup: () => calls.push('platform'),
    };

    expect(() => bridge.shutdown()).toThrow('forced native shutdown failure');
    expect(calls).toEqual(['device', 'core', 'platform']);
    expect(bridge.isLoaded).toBe(false);

    shouldFail = false;
    expect(() => bridge.shutdown()).not.toThrow();
    expect(calls).toEqual(['device', 'core', 'platform', 'core']);
  });

  it('releases the browser device adapter copied credentials', () => {
    const source = readFileSync(
      new URL('../../../src/Adapters/DeviceRegistrationAdapter.ts', import.meta.url),
      'utf8',
    );
    expect(source).toContain("this.configuredBaseURL = '';");
    expect(source).toContain("this.configuredApiKey = '';");
  });
});
