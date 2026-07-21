import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  getStoredHfToken,
  setHfToken,
} from '../../../../src/Public/Extensions/RunAnywhere+HuggingFace';

describe('setHfToken', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('persists and clears the browser fallback when native export is absent', () => {
    const values = new Map<string, string>();
    vi.stubGlobal('localStorage', {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => values.set(key, value),
      removeItem: (key: string) => values.delete(key),
    });

    setHfToken('hf_test_token');
    expect(getStoredHfToken()).toBe('hf_test_token');

    setHfToken(null);
    expect(getStoredHfToken()).toBeNull();
  });
});
