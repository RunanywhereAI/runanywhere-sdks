import { afterEach, describe, expect, it, vi } from 'vitest';

const runtimeState = vi.hoisted(() => ({
  module: null as Record<string, unknown> | null,
}));
const registrationState = vi.hoisted(() => ({
  waitForPendingRegistration: vi.fn(),
}));

vi.mock('../../../src/runtime/EmscriptenModule', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>();
  const clearActual = actual.clearRunanywhereModule as () => void;
  return {
    ...actual,
    tryRunanywhereModule: () => runtimeState.module,
    getAllRegisteredModules: () => [],
    clearRunanywhereModule: () => {
      runtimeState.module = null;
      clearActual();
    },
  };
});

vi.mock('../../../src/Adapters/DeviceRegistrationAdapter', () => ({
  DeviceRegistrationAdapter: {
    install: vi.fn(),
    waitForPendingRegistration: registrationState.waitForPendingRegistration,
  },
}));

vi.mock('../../../src/runtime/ProtoWasm', () => ({
  ProtoWasmBridge: class {
    withHeapBytes<T>(bytes: Uint8Array, callback: (ptr: number, size: number) => T): T {
      return callback(8, bytes.length);
    }

    callResultProto<T>(
      _messageType: unknown,
      callback: (outResult: number) => number,
    ): T {
      callback(16);
      return {
        success: true,
        hasCompletedHttpSetup: true,
      } as T;
    }
  },
}));

import { RunAnywhere } from '../../../src/Public/RunAnywhere';

function fakeSdkModule() {
  const heap = new ArrayBuffer(256);
  return {
    HEAPU8: new Uint8Array(heap),
    HEAP32: new Int32Array(heap),
    HEAPU32: new Uint32Array(heap),
    _malloc: vi.fn(() => 32),
    _free: vi.fn(),
    UTF8ToString: vi.fn(() => ''),
    stringToUTF8: vi.fn(() => 0),
    lengthBytesUTF8: vi.fn((value: string) => value.length),
    addFunction: vi.fn(() => 1),
    removeFunction: vi.fn(),
    _rac_sdk_init_phase1_proto: vi.fn(() => 0),
    _rac_sdk_init_phase2_proto: vi.fn(() => 0),
    _rac_device_manager_register_if_needed: vi.fn(() => 0),
  };
}

describe('RunAnywhere services lifecycle', () => {
  afterEach(async () => {
    registrationState.waitForPendingRegistration.mockReset();
    runtimeState.module = null;
    await RunAnywhere.shutdown();
  });

  it('does not let registration completion from a shut-down lifetime mutate a reinitialize', async () => {
    let releaseRegistration!: (pending: boolean) => void;
    registrationState.waitForPendingRegistration.mockReturnValueOnce(
      new Promise<boolean>((resolve) => { releaseRegistration = resolve; }),
    );
    const oldModule = fakeSdkModule();
    runtimeState.module = oldModule;

    const oldServices = RunAnywhere.completeServicesInitialization();
    await vi.waitFor(() => {
      expect(registrationState.waitForPendingRegistration).toHaveBeenCalledOnce();
    });

    await RunAnywhere.shutdown();
    releaseRegistration(true);
    await oldServices;

    expect(oldModule._rac_device_manager_register_if_needed).not.toHaveBeenCalled();
    expect(RunAnywhere.areServicesReady).toBe(false);

    const newModule = fakeSdkModule();
    runtimeState.module = newModule;
    registrationState.waitForPendingRegistration.mockResolvedValueOnce(false);
    await RunAnywhere.completeServicesInitialization();

    expect(newModule._rac_sdk_init_phase2_proto).toHaveBeenCalledOnce();
    expect(RunAnywhere.areServicesReady).toBe(true);
  });
});
