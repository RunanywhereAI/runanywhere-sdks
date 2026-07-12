import { afterEach, describe, expect, it, vi } from 'vitest';

import { CommonsModule } from '../../../src/runtime/CommonsModule';
import { RunAnywhere } from '../../../src/Public/RunAnywhere';

describe('RunAnywhere initialization lifetime', () => {
  afterEach(async () => {
    await RunAnywhere.shutdown();
    vi.restoreAllMocks();
  });

  it('joins and discards initialization invalidated by shutdown', async () => {
    let releaseLoad!: () => void;
    const pendingLoad = new Promise<void>((resolve) => {
      releaseLoad = resolve;
    });
    const ensureLoaded = vi
      .spyOn(CommonsModule.shared, 'ensureLoaded')
      .mockImplementationOnce(() => pendingLoad)
      .mockResolvedValue(undefined);
    const nativeShutdown = vi
      .spyOn(CommonsModule.shared, 'shutdown')
      .mockImplementation(() => undefined);
    const publish = vi.spyOn(RunAnywhere.events, 'publish');

    const initialization = RunAnywhere.initialize();
    await vi.waitFor(() => expect(ensureLoaded).toHaveBeenCalledOnce());

    const shutdown = RunAnywhere.shutdown();
    releaseLoad();

    await expect(initialization).rejects.toMatchObject({
      proto: {
        message: expect.stringContaining('SDK lifetime ended'),
      },
    });
    await shutdown;

    expect(RunAnywhere.isInitialized).toBe(false);
    expect(nativeShutdown).toHaveBeenCalledOnce();
    expect(publish.mock.calls.some(([name]) => name === 'sdk.initialized')).toBe(false);

    await RunAnywhere.initialize();
    expect(RunAnywhere.isInitialized).toBe(true);
    expect(ensureLoaded).toHaveBeenCalledTimes(2);
  });
});
