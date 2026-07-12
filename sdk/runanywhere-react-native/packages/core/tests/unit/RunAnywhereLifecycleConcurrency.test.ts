const mockNative = {
  initialize: jest.fn<Promise<boolean>, [string]>(),
  completeServicesInitialization: jest.fn<Promise<ArrayBuffer>, []>(),
  retryHTTPSetupProto: jest.fn<Promise<ArrayBuffer>, []>(),
  destroy: jest.fn<Promise<void>, []>(),
};

jest.mock('react-native', () => ({
  Platform: { OS: 'ios' },
  PermissionsAndroid: {
    PERMISSIONS: {},
    RESULTS: {},
    check: jest.fn(),
    request: jest.fn(),
  },
}));

jest.mock('../../src/native', () => ({
  isNativeModuleAvailable: jest.fn(() => true),
  requireNativeModule: jest.fn(() => mockNative),
}));

jest.mock('../../src/native/NitroModulesGlobalInit', () => ({
  initializeNitroModulesGlobally: jest.fn(() => Promise.resolve()),
}));

import { SdkInitResult } from '@runanywhere/proto-ts/sdk_init';
import { RunAnywhere } from '../../src/Public/RunAnywhere';

function phase2Payload(
  httpConfigured: boolean = true,
  httpApplicable: boolean = true
): ArrayBuffer {
  const bytes = SdkInitResult.encode(
    SdkInitResult.create({
      success: true,
      hasCompletedHttpSetup: httpConfigured,
      httpConfigured,
      httpApplicable,
    })
  ).finish();
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength
  ) as ArrayBuffer;
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
  reject: (error: unknown) => void;
} {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

async function flushMicrotasks(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

describe('RunAnywhere lifecycle serialization', () => {
  beforeEach(async () => {
    mockNative.initialize.mockReset().mockResolvedValue(true);
    mockNative.completeServicesInitialization
      .mockReset()
      .mockResolvedValue(phase2Payload());
    mockNative.retryHTTPSetupProto
      .mockReset()
      .mockResolvedValue(phase2Payload());
    mockNative.destroy.mockReset().mockResolvedValue();
    await RunAnywhere.reset();
    jest.clearAllMocks();
    jest.spyOn(console, 'debug').mockImplementation(() => undefined);
    jest.spyOn(console, 'info').mockImplementation(() => undefined);
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
  });

  afterEach(async () => {
    mockNative.destroy.mockResolvedValue();
    await RunAnywhere.reset();
    jest.restoreAllMocks();
  });

  test('reset invalidates and joins an in-flight Phase 1 before destroy', async () => {
    const phase1 = deferred<boolean>();
    mockNative.initialize.mockReturnValueOnce(phase1.promise);

    const initialization = RunAnywhere.initialize();
    await flushMicrotasks();
    expect(mockNative.initialize).toHaveBeenCalledTimes(1);

    const reset = RunAnywhere.reset();
    expect(RunAnywhere.isInitialized).toBe(false);
    expect(mockNative.destroy).not.toHaveBeenCalled();

    phase1.resolve(true);
    await expect(initialization).rejects.toThrow(/SDK lifetime ended/);
    await reset;

    expect(mockNative.completeServicesInitialization).not.toHaveBeenCalled();
    expect(mockNative.destroy).toHaveBeenCalledTimes(1);
    expect(RunAnywhere.isInitialized).toBe(false);
  });

  test('concurrent resets join and initialize waits for native destroy', async () => {
    await RunAnywhere.initialize();
    await RunAnywhere.completeServicesInitialization();

    const destroy = deferred<void>();
    mockNative.destroy.mockReturnValueOnce(destroy.promise);

    const firstReset = RunAnywhere.reset();
    await flushMicrotasks();
    expect(mockNative.destroy).toHaveBeenCalledTimes(1);

    const secondReset = RunAnywhere.reset();
    expect(secondReset).toBe(firstReset);

    const reinitialize = RunAnywhere.initialize();
    await flushMicrotasks();
    expect(mockNative.initialize).toHaveBeenCalledTimes(1);

    destroy.resolve();
    await Promise.all([firstReset, secondReset, reinitialize]);

    expect(mockNative.destroy).toHaveBeenCalledTimes(1);
    expect(mockNative.initialize).toHaveBeenCalledTimes(2);
    expect(RunAnywhere.isInitialized).toBe(true);
  });

  test('reset awaits Phase 2 and blocks its stale state completion', async () => {
    const phase2 = deferred<ArrayBuffer>();
    mockNative.completeServicesInitialization.mockReturnValueOnce(
      phase2.promise
    );

    await RunAnywhere.initialize();
    await flushMicrotasks();
    expect(mockNative.completeServicesInitialization).toHaveBeenCalledTimes(1);

    const services = RunAnywhere.completeServicesInitialization();
    const reset = RunAnywhere.reset();
    expect(mockNative.destroy).not.toHaveBeenCalled();

    phase2.resolve(phase2Payload());
    await expect(services).rejects.toThrow(/SDK lifetime ended/);
    await reset;

    expect(mockNative.destroy).toHaveBeenCalledTimes(1);
    expect(RunAnywhere.isInitialized).toBe(false);
    expect(RunAnywhere.areServicesReady).toBe(false);
  });

  test('reset joins HTTP recovery and blocks its stale state completion', async () => {
    mockNative.completeServicesInitialization.mockResolvedValueOnce(
      phase2Payload(false, true)
    );
    const retryResult = deferred<ArrayBuffer>();
    mockNative.retryHTTPSetupProto.mockReturnValueOnce(retryResult.promise);

    await RunAnywhere.initialize();
    await RunAnywhere.completeServicesInitialization();

    const { ensureServicesReady } = await import(
      '../../src/Foundation/Initialization/ServicesReadyGuard'
    );
    const retry = ensureServicesReady();
    await flushMicrotasks();
    expect(mockNative.retryHTTPSetupProto).toHaveBeenCalledTimes(1);

    const reset = RunAnywhere.reset();
    expect(RunAnywhere.isInitialized).toBe(false);
    expect(mockNative.destroy).not.toHaveBeenCalled();

    retryResult.resolve(phase2Payload());
    await expect(retry).rejects.toThrow(/SDK lifetime ended/);
    await reset;

    expect(mockNative.destroy).toHaveBeenCalledTimes(1);
    expect(RunAnywhere.isInitialized).toBe(false);
    expect(RunAnywhere.areServicesReady).toBe(false);
  });

  test('failed native destroy keeps initialization closed until reset retries', async () => {
    await RunAnywhere.initialize();
    await RunAnywhere.completeServicesInitialization();

    mockNative.destroy.mockRejectedValueOnce(new Error('destroy failed'));
    const reset = RunAnywhere.reset();
    expect(RunAnywhere.isInitialized).toBe(false);
    await expect(reset).rejects.toThrow('destroy failed');

    await expect(RunAnywhere.initialize()).rejects.toThrow(
      /teardown did not complete/
    );
    expect(mockNative.initialize).toHaveBeenCalledTimes(1);

    mockNative.destroy.mockResolvedValueOnce();
    await RunAnywhere.reset();
    await RunAnywhere.initialize();

    expect(mockNative.destroy).toHaveBeenCalledTimes(2);
    expect(mockNative.initialize).toHaveBeenCalledTimes(2);
    expect(RunAnywhere.isInitialized).toBe(true);
  });
});
