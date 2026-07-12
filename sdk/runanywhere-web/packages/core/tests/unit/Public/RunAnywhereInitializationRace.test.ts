import { afterEach, describe, expect, it, vi } from 'vitest';

import { CommonsModule } from '../../../src/runtime/CommonsModule';
import { StorageAdapter } from '../../../src/Adapters/StorageAdapter';
import { RunAnywhere } from '../../../src/Public/RunAnywhere';

describe('RunAnywhere initialization lifetime', () => {
  const values = new Map<string, string>();

  vi.stubGlobal('localStorage', {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  });

  afterEach(async () => {
    await RunAnywhere.shutdown();
    vi.restoreAllMocks();
    values.clear();
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
    expect(RunAnywhere.isInitialized).toBe(false);
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

    const secondShutdown = RunAnywhere.shutdown();
    expect(RunAnywhere.isInitialized).toBe(false);
    await secondShutdown;
  });

  it('fails initialization when the canonical device identity cannot persist', async () => {
    vi.spyOn(CommonsModule.shared, 'ensureLoaded').mockResolvedValue(undefined);
    vi.spyOn(localStorage, 'setItem').mockImplementation(() => {
      throw new Error('quota denied');
    });

    await expect(RunAnywhere.initialize()).rejects.toMatchObject({
      proto: {
        code: expect.any(Number),
        message: expect.stringContaining('Failed to persist browser device identity'),
      },
    });
    expect(RunAnywhere.isInitialized).toBe(false);
  });

  it('rolls back native state before reinitializing with a new configuration', async () => {
    const configurations: Array<{ apiKey?: string; baseURL?: string }> = [];
    vi.spyOn(CommonsModule.prototype, 'ensureLoaded').mockImplementation((configuration) => {
      configurations.push(configuration);
      return Promise.resolve();
    });
    const nativeShutdown = vi.spyOn(CommonsModule.prototype, 'shutdown');
    let rejectPersistence = true;
    vi.spyOn(localStorage, 'setItem').mockImplementation((key: string, value: string) => {
      if (rejectPersistence) throw new Error('quota denied');
      values.set(key, value);
    });

    await expect(RunAnywhere.initialize({
      apiKey: 'first-key',
      baseURL: 'https://first.example',
    })).rejects.toMatchObject({
      proto: { message: expect.stringContaining('Failed to persist browser device identity') },
    });
    expect(nativeShutdown).toHaveBeenCalledOnce();
    expect(RunAnywhere.isInitialized).toBe(false);

    rejectPersistence = false;
    await RunAnywhere.initialize({
      apiKey: 'second-key',
      baseURL: 'https://second.example',
    });

    expect(configurations).toHaveLength(2);
    expect(configurations[0]).toMatchObject({
      apiKey: 'first-key',
      baseURL: 'https://first.example',
    });
    expect(configurations[1]).toMatchObject({
      apiKey: 'second-key',
      baseURL: 'https://second.example',
    });
    expect(RunAnywhere.isInitialized).toBe(true);
  });

  it('rejects new services work while shared shutdown is draining', async () => {
    vi.spyOn(CommonsModule.shared, 'ensureLoaded').mockResolvedValue(undefined);
    let releaseStorage!: () => void;
    vi.spyOn(StorageAdapter, 'prepareForShutdown').mockReturnValueOnce(
      new Promise<void>((resolve) => {
        releaseStorage = resolve;
      }),
    );

    await RunAnywhere.initialize();
    const shutdown = RunAnywhere.shutdown();

    await expect(RunAnywhere.completeServicesInitialization()).rejects.toMatchObject({
      proto: { message: expect.stringContaining('shutdown is in progress') },
    });
    releaseStorage();
    await shutdown;
  });

  it('requires a successful native shutdown retry before reinitialization', async () => {
    // A successful shutdown intentionally releases the singleton. Mock the
    // loader contract on the prototype so the fresh lifetime receives the
    // same test seam instead of attempting to boot real worker-backed WASM.
    vi.spyOn(CommonsModule.prototype, 'ensureLoaded').mockResolvedValue(undefined);

    await RunAnywhere.initialize();
    const nativeShutdown = vi.fn()
      .mockImplementationOnce(() => { throw new Error('forced native shutdown failure'); })
      .mockImplementation(() => undefined);
    const bridge = CommonsModule.shared as unknown as {
      _module: { _rac_shutdown(): void };
      _loaded: boolean;
    };
    bridge._module = { _rac_shutdown: nativeShutdown };
    bridge._loaded = true;

    await expect(RunAnywhere.shutdown()).rejects.toThrow('forced native shutdown failure');
    await expect(RunAnywhere.initialize()).rejects.toMatchObject({
      proto: { message: expect.stringContaining('shutdown did not complete') },
    });

    await RunAnywhere.shutdown();
    await expect(RunAnywhere.initialize()).resolves.toBeUndefined();
    expect(nativeShutdown).toHaveBeenCalledTimes(2);
  });

  it('fails initialization when the stored device identity is malformed', async () => {
    vi.spyOn(CommonsModule.shared, 'ensureLoaded').mockResolvedValue(undefined);
    values.set(
      'rac_sdk_plaintext_com.runanywhere.sdk.device.uuid',
      'not-a-canonical-uuid',
    );

    await expect(RunAnywhere.initialize()).rejects.toMatchObject({
      proto: {
        code: expect.any(Number),
        message: expect.stringContaining('stored device identity is not a canonical UUID'),
      },
    });
    expect(RunAnywhere.isInitialized).toBe(false);
  });
});
