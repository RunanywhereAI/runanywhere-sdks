import { afterEach, describe, expect, it, vi } from 'vitest';

import { AudioCapture } from '../../../src/Infrastructure/AudioCapture';

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

describe('AudioCapture pending start lifecycle', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('stops a stream granted after capture was stopped', async () => {
    const permission = deferred<MediaStream>();
    const stopTrack = vi.fn();
    vi.stubGlobal('navigator', {
      mediaDevices: {
        getUserMedia: vi.fn(() => permission.promise),
      },
    });
    const capture = new AudioCapture();

    const starting = capture.start();
    capture.stop();
    permission.resolve({
      getTracks: () => [{ stop: stopTrack }],
    } as unknown as MediaStream);
    await starting;

    expect(stopTrack).toHaveBeenCalledOnce();
    expect(capture.isCapturing).toBe(false);
  });
});
