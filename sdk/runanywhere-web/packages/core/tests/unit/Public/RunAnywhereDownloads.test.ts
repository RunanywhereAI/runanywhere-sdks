import { afterEach, describe, expect, it, vi } from 'vitest';
import { __testing__ } from '../../../src/Public/RunAnywhere';
import { Downloads } from '../../../src/Public/Extensions/RunAnywhere+Downloads';

describe('browser download safeguards', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('fails before start when storage quota cannot fit the plan', async () => {
    vi.stubGlobal('navigator', {
      storage: {
        estimate: vi.fn().mockResolvedValue({ usage: 900, quota: 1_000 }),
      },
    });
    await expect(__testing__.assertBrowserStorageQuota(
      'large-model',
      { files: [{ expectedBytes: 200 }] } as never,
      0,
    )).rejects.toThrow('Insufficient browser storage');
  });

  it('retries transient progress polling failures with the same task', async () => {
    const poll = vi.spyOn(Downloads, 'poll')
      .mockImplementationOnce(() => { throw new Error('temporary poll error'); })
      .mockReturnValueOnce({ state: 1 } as never);

    await expect(__testing__.pollDownloadWithRetry('model', 'task', 1)).resolves.toMatchObject({
      state: 1,
    });
    expect(poll).toHaveBeenCalledTimes(2);
  });
});
