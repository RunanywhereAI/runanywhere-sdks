import { describe, expect, it } from 'vitest';
import {
  getStoredHfToken,
  setHfToken,
} from '../../../../src/Public/Extensions/RunAnywhere+HuggingFace';

describe('setHfToken', () => {
  it('holds the token in memory for the session and clears it', () => {
    setHfToken('hf_test_token');
    expect(getStoredHfToken()).toBe('hf_test_token');

    setHfToken(null);
    expect(getStoredHfToken()).toBeNull();
  });
});
