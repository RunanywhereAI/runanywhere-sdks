import { afterEach, describe, expect, it, vi } from 'vitest';
import { DownloadFailureReason } from '@runanywhere/proto-ts/download_service';
import { __testing__ } from '../../../src/Public/SDKCore';
import { Downloads } from '../../../src/Public/Extensions/RunAnywhere+Downloads';
import { ensureDownloadStorageReady } from '../../../src/Infrastructure/BrowserStorage';
import { ProtoErrorCode } from '../../../src/Foundation/SDKException';

describe('browser download safeguards', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('reports insufficient storage via commons-backed readiness when quota is too small', async () => {
    vi.stubGlobal('navigator', {
      storage: {
        estimate: vi.fn().mockResolvedValue({ usage: 900, quota: 1_000 }),
        persist: vi.fn().mockResolvedValue(false),
        persisted: vi.fn().mockResolvedValue(false),
      },
    });
    const readiness = await ensureDownloadStorageReady({ requiredBytes: 200 });
    expect(readiness.availableBytes).toBe(100);
    expect(readiness.sufficient).toBe(false);
  });

  it('reads free space from navigator.storage.estimate for the download planner', async () => {
    vi.stubGlobal('navigator', {
      storage: {
        estimate: vi.fn().mockResolvedValue({ usage: 386_000_000, quota: 72_000_000_000 }),
      },
    });
    await expect(__testing__.resolveBrowserAvailableStorageBytes()).resolves.toBe(
      72_000_000_000 - 386_000_000,
    );
  });

  it('surfaces storage plan failures as STORAGE_ERROR, not backend-unavailable', () => {
    expect(() => __testing__.throwDownloadFailure(
      'downloadModel',
      'Not enough storage to download this model: it needs about 2.5 GB but only 2.0 GB is free on the device.',
      DownloadFailureReason.DOWNLOAD_FAILURE_REASON_INSUFFICIENT_STORAGE,
    )).toThrow(/Not enough storage/);

    try {
      __testing__.throwDownloadFailure(
        'downloadModel',
        'Not enough storage to download this model',
        DownloadFailureReason.DOWNLOAD_FAILURE_REASON_INSUFFICIENT_STORAGE,
      );
    } catch (err) {
      expect(err).toMatchObject({
        code: ProtoErrorCode.ERROR_CODE_STORAGE_ERROR,
        message: expect.stringContaining('Not enough storage'),
      });
    }
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
