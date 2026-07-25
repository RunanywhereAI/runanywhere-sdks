import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import {
  DeviceRegistrationAdapter,
  type DeviceRegistrationModule,
} from '../../../src/Adapters/DeviceRegistrationAdapter';

type Trampoline = (...args: number[]) => number | bigint | void;

const CALLBACK = {
  size: 24,
  getInfo: 0,
  getId: 4,
  isRegistered: 8,
  setRegistered: 12,
  httpPost: 16,
  userData: 20,
} as const;

const INFO = {
  size: 96,
  deviceId: 0,
  deviceModel: 4,
  deviceName: 8,
  platform: 12,
  osVersion: 16,
  formFactor: 20,
  architecture: 24,
  chipName: 28,
  totalMemory: 32,
  availableMemory: 40,
  hasNeuralEngine: 48,
  neuralEngineCores: 52,
  gpuFamily: 56,
  batteryLevel: 64,
  batteryState: 72,
  isLowPowerMode: 76,
  coreCount: 80,
  performanceCores: 84,
  efficiencyCores: 88,
  deviceFingerprint: 92,
} as const;

const RESPONSE = {
  size: 16,
  result: 0,
  statusCode: 4,
  responseBody: 8,
  errorMessage: 12,
} as const;

class MemoryStorage implements Storage {
  private readonly values = new Map<string, string>();

  get length(): number { return this.values.size; }
  clear(): void { this.values.clear(); }
  getItem(key: string): string | null { return this.values.get(key) ?? null; }
  key(index: number): string | null { return Array.from(this.values.keys())[index] ?? null; }
  removeItem(key: string): void { this.values.delete(key); }
  setItem(key: string, value: string): void { this.values.set(key, value); }
  entries(): Array<[string, string]> { return Array.from(this.values.entries()); }
}

interface FakeModuleHandle {
  module: DeviceRegistrationModule;
  callbacksPtr: number;
  trampolines: Map<number, Trampoline>;
  nativeRegistered: boolean;
  lifecycle: string[];
  freedPointers: number[];
  allocateString(value: string): number;
  readString(ptr: number): string;
  readI32(ptr: number): number;
  readI64(ptr: number): number;
  setNativeRegistered(value: boolean): void;
}

function createFakeModule(): FakeModuleHandle {
  const memory = new ArrayBuffer(1 << 20);
  const heap = new Uint8Array(memory);
  const view = new DataView(memory);
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const trampolines = new Map<number, Trampoline>();
  const lifecycle: string[] = [];
  const freedPointers: number[] = [];
  let nextPtr = 512;
  let nextTrampoline = 10_000;
  let callbacksPtr = 0;
  let nativeRegistered = false;

  const allocate = (size: number): number => {
    const ptr = nextPtr;
    nextPtr += Math.max(8, (size + 7) & ~7);
    return ptr;
  };
  const writeString = (value: string): number => {
    const bytes = encoder.encode(value);
    const ptr = allocate(bytes.length + 1);
    heap.set(bytes, ptr);
    heap[ptr + bytes.length] = 0;
    return ptr;
  };
  const readString = (ptr: number): string => {
    let end = ptr;
    while (end < heap.length && heap[end] !== 0) end += 1;
    return decoder.decode(heap.subarray(ptr, end));
  };
  const deviceIdPtr = writeString('web-device-id');
  const accessTokenPtr = writeString('test-access-token');

  const moduleShape: Partial<DeviceRegistrationModule> = {
    HEAPU8: heap,
    _malloc: allocate,
    _free(ptr: number): void {
      lifecycle.push(`free:${ptr}`);
      freedPointers.push(ptr);
    },
    addFunction(fn: Trampoline): number {
      const ptr = nextTrampoline++;
      trampolines.set(ptr, fn);
      return ptr;
    },
    removeFunction(ptr: number): void {
      lifecycle.push(`remove:${ptr}`);
      trampolines.delete(ptr);
    },
    setValue(ptr: number, value: number | bigint, type: string): void {
      const numeric = Number(value);
      if (type === 'i8') view.setInt8(ptr, numeric);
      else if (type === 'double') view.setFloat64(ptr, numeric, true);
      else view.setInt32(ptr, numeric, true);
    },
    getValue(ptr: number, type: string): number {
      if (type === 'i8') return view.getInt8(ptr);
      if (type === 'double') return view.getFloat64(ptr, true);
      return view.getInt32(ptr, true);
    },
    UTF8ToString: readString,
    stringToUTF8(value: string, ptr: number, maxBytes: number): number {
      const bytes = encoder.encode(value).subarray(0, Math.max(0, maxBytes - 1));
      heap.set(bytes, ptr);
      heap[ptr + bytes.length] = 0;
      return bytes.length;
    },
    lengthBytesUTF8(value: string): number { return encoder.encode(value).length; },

    _rac_device_manager_set_callbacks(ptr: number): number {
      callbacksPtr = ptr;
      lifecycle.push('register');
      return 0;
    },
    _rac_device_manager_clear_callbacks(): void { lifecycle.push('clear'); },
    _rac_state_get_device_id: () => deviceIdPtr,
    _rac_state_is_device_registered: () => nativeRegistered ? 1 : 0,
    _rac_state_set_device_registered(value: number): void { nativeRegistered = value !== 0; },
    _rac_auth_get_access_token: () => accessTokenPtr,

    _rac_wasm_sizeof_device_callbacks: () => CALLBACK.size,
    _rac_wasm_offsetof_device_callbacks_get_device_info: () => CALLBACK.getInfo,
    _rac_wasm_offsetof_device_callbacks_get_device_id: () => CALLBACK.getId,
    _rac_wasm_offsetof_device_callbacks_is_registered: () => CALLBACK.isRegistered,
    _rac_wasm_offsetof_device_callbacks_set_registered: () => CALLBACK.setRegistered,
    _rac_wasm_offsetof_device_callbacks_http_post: () => CALLBACK.httpPost,
    _rac_wasm_offsetof_device_callbacks_user_data: () => CALLBACK.userData,

    _rac_wasm_sizeof_device_registration_info: () => INFO.size,
    _rac_wasm_offsetof_device_registration_info_device_id: () => INFO.deviceId,
    _rac_wasm_offsetof_device_registration_info_device_model: () => INFO.deviceModel,
    _rac_wasm_offsetof_device_registration_info_device_name: () => INFO.deviceName,
    _rac_wasm_offsetof_device_registration_info_platform: () => INFO.platform,
    _rac_wasm_offsetof_device_registration_info_os_version: () => INFO.osVersion,
    _rac_wasm_offsetof_device_registration_info_form_factor: () => INFO.formFactor,
    _rac_wasm_offsetof_device_registration_info_architecture: () => INFO.architecture,
    _rac_wasm_offsetof_device_registration_info_chip_name: () => INFO.chipName,
    _rac_wasm_offsetof_device_registration_info_total_memory: () => INFO.totalMemory,
    _rac_wasm_offsetof_device_registration_info_available_memory: () => INFO.availableMemory,
    _rac_wasm_offsetof_device_registration_info_has_neural_engine: () => INFO.hasNeuralEngine,
    _rac_wasm_offsetof_device_registration_info_neural_engine_cores: () => INFO.neuralEngineCores,
    _rac_wasm_offsetof_device_registration_info_gpu_family: () => INFO.gpuFamily,
    _rac_wasm_offsetof_device_registration_info_battery_level: () => INFO.batteryLevel,
    _rac_wasm_offsetof_device_registration_info_battery_state: () => INFO.batteryState,
    _rac_wasm_offsetof_device_registration_info_is_low_power_mode: () => INFO.isLowPowerMode,
    _rac_wasm_offsetof_device_registration_info_core_count: () => INFO.coreCount,
    _rac_wasm_offsetof_device_registration_info_performance_cores: () => INFO.performanceCores,
    _rac_wasm_offsetof_device_registration_info_efficiency_cores: () => INFO.efficiencyCores,
    _rac_wasm_offsetof_device_registration_info_device_fingerprint: () => INFO.deviceFingerprint,

    _rac_wasm_sizeof_device_http_response: () => RESPONSE.size,
    _rac_wasm_offsetof_device_http_response_result: () => RESPONSE.result,
    _rac_wasm_offsetof_device_http_response_status_code: () => RESPONSE.statusCode,
    _rac_wasm_offsetof_device_http_response_response_body: () => RESPONSE.responseBody,
    _rac_wasm_offsetof_device_http_response_error_message: () => RESPONSE.errorMessage,
  };

  const handle: FakeModuleHandle = {
    module: moduleShape as DeviceRegistrationModule,
    get callbacksPtr() { return callbacksPtr; },
    trampolines,
    get nativeRegistered() { return nativeRegistered; },
    lifecycle,
    freedPointers,
    allocateString: writeString,
    readString,
    readI32: (ptr) => view.getInt32(ptr, true),
    readI64: (ptr) => view.getUint32(ptr, true) + view.getUint32(ptr + 4, true) * 0x100000000,
    setNativeRegistered: (value) => { nativeRegistered = value; },
  };
  return handle;
}

function callback(handle: FakeModuleHandle, offset: number): Trampoline {
  const ptr = handle.readI32(handle.callbacksPtr + offset);
  const fn = handle.trampolines.get(ptr);
  if (!fn) throw new Error(`Missing callback at table index ${ptr}`);
  return fn;
}

describe('DeviceRegistrationAdapter', () => {
  let storage: MemoryStorage;
  let fetchStub: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    storage = new MemoryStorage();
    fetchStub = vi.fn(async () => ({ ok: true, status: 201 }) as Response);
    vi.stubGlobal('localStorage', storage);
    vi.stubGlobal('navigator', {
      userAgent: 'Test Browser',
      platform: 'Test OS',
      hardwareConcurrency: 8,
      deviceMemory: 8,
      userAgentData: { mobile: false, platform: 'Test OS' },
      gpu: {},
    });
    vi.stubGlobal('document', { title: 'RunAnywhere Test' });
    vi.stubGlobal('performance', {
      memory: { usedJSHeapSize: 1_000, jsHeapSizeLimit: 2_000 },
    });
    vi.stubGlobal('fetch', fetchStub);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('marshals browser metadata through compiler-provided offsets', () => {
    const handle = createFakeModule();
    const adapter = DeviceRegistrationAdapter.install(handle.module, {
      baseURL: 'https://relay.test/control',
      apiKey: 'test-api-key',
      environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
      sdkVersion: '0.19.13',
    });
    const infoPtr = handle.allocateString(' '.repeat(INFO.size));

    callback(handle, CALLBACK.getInfo)(infoPtr, 0);

    expect(handle.readString(handle.readI32(infoPtr + INFO.platform))).toBe('web');
    expect(handle.readString(handle.readI32(infoPtr + INFO.architecture))).toBe('unknown');
    expect(handle.readString(handle.readI32(infoPtr + INFO.osVersion))).toBe('Test OS');
    expect(handle.readI64(infoPtr + INFO.totalMemory)).toBe(8 * 1024 * 1024 * 1024);
    expect(handle.readI64(infoPtr + INFO.availableMemory)).toBeLessThanOrEqual(
      handle.readI64(infoPtr + INFO.totalMemory),
    );
    expect(handle.readI32(infoPtr + INFO.coreCount)).toBe(8);
    expect(handle.readI32(infoPtr + INFO.performanceCores)).toBe(0);
    expect(handle.readI32(infoPtr + INFO.efficiencyCores)).toBe(0);
    expect(callback(handle, CALLBACK.getId)(0)).toBeGreaterThan(0);
    adapter.cleanup();
  });

  it('keeps registration runtime-local across restarts and credential changes', () => {
    const firstConfig = {
      baseURL: 'https://relay.test/control',
      apiKey: 'first-test-api-key',
      environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
      sdkVersion: '0.19.13',
    } as const;
    storage.setItem(
      'rac_sdk_plaintext_device_registered_legacy-host-scope',
      '1',
    );
    const first = createFakeModule();
    const firstAdapter = DeviceRegistrationAdapter.install(first.module, firstConfig);
    expect(storage.entries()).toHaveLength(0);
    callback(first, CALLBACK.setRegistered)(1, 0);
    expect(first.nativeRegistered).toBe(true);
    expect(callback(first, CALLBACK.isRegistered)(0)).toBe(1);
    expect(storage.entries()).toHaveLength(0);
    firstAdapter.cleanup();

    // A fresh runtime must register again even with the same credential.
    const restarted = createFakeModule();
    const restartedAdapter = DeviceRegistrationAdapter.install(
      restarted.module,
      firstConfig,
    );
    expect(restarted.nativeRegistered).toBe(false);
    expect(callback(restarted, CALLBACK.isRegistered)(0)).toBe(0);
    restartedAdapter.cleanup();

    // A new organization/client credential on the same endpoint must never
    // inherit the prior credential's successful registration bit.
    const switchedCredential = createFakeModule();
    const switchedAdapter = DeviceRegistrationAdapter.install(switchedCredential.module, {
      ...firstConfig,
      apiKey: 'second-test-api-key',
    });
    expect(switchedCredential.nativeRegistered).toBe(false);
    expect(callback(switchedCredential, CALLBACK.isRegistered)(0)).toBe(0);
    expect(JSON.stringify(storage.entries())).not.toContain(firstConfig.apiKey);
    switchedAdapter.cleanup();
  });

  it('posts production registration asynchronously with auth and a bounded timeout', async () => {
    const handle = createFakeModule();
    const adapter = DeviceRegistrationAdapter.install(handle.module, {
      baseURL: 'https://relay.test/control',
      apiKey: 'test-api-key',
      environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
      sdkVersion: '0.19.13',
    });
    const endpointPtr = handle.allocateString('/api/v1/devices/register');
    const bodyPtr = handle.allocateString('{"device_id":"web-device-id"}');
    const responsePtr = handle.allocateString(' '.repeat(RESPONSE.size));

    const firstResult = callback(handle, CALLBACK.httpPost)(endpointPtr, bodyPtr, 1, responsePtr, 0);

    expect(firstResult).toBe(-100);
    expect(await DeviceRegistrationAdapter.waitForPendingRegistration(handle.module)).toBe(true);
    const retryBodyPtr = handle.allocateString(
      '{"device_id":"web-device-id","last_seen_at_ms":2}',
    );
    const result = callback(handle, CALLBACK.httpPost)(
      endpointPtr,
      retryBodyPtr,
      1,
      responsePtr,
      0,
    );
    expect(result).toBe(0);
    expect(handle.readI32(responsePtr + RESPONSE.result)).toBe(0);
    expect(handle.readI32(responsePtr + RESPONSE.statusCode)).toBe(201);
    expect(fetchStub).toHaveBeenCalledOnce();
    expect(fetchStub.mock.calls[0][0]).toBe('https://relay.test/control/api/v1/devices/register');
    const request = fetchStub.mock.calls[0][1] as RequestInit;
    const headers = new Headers(request.headers);
    expect(request.method).toBe('POST');
    expect(request.body).toBe('{"device_id":"web-device-id"}');
    expect(headers.get('apikey')).toBe('test-api-key');
    expect(headers.get('authorization')).toBe('Bearer test-access-token');
    adapter.cleanup();
  });

  it('distinguishes HTTP rejection, development registration, and missing configuration', async () => {
    const prod = createFakeModule();
    const prodAdapter = DeviceRegistrationAdapter.install(prod.module, {
      baseURL: 'https://relay.test',
      apiKey: 'test-api-key',
      environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
      sdkVersion: '0.19.13',
    });
    const prodEndpoint = prod.allocateString('/api/v1/devices/register');
    const prodBody = prod.allocateString('{}');
    const prodResponse = prod.allocateString(' '.repeat(RESPONSE.size));
    fetchStub.mockResolvedValueOnce({ ok: false, status: 403 } as Response);
    expect(callback(prod, CALLBACK.httpPost)(prodEndpoint, prodBody, 1, prodResponse, 0)).toBe(-100);
    await DeviceRegistrationAdapter.waitForPendingRegistration(prod.module);
    expect(callback(prod, CALLBACK.httpPost)(prodEndpoint, prodBody, 1, prodResponse, 0)).toBe(-157);
    const errorPtr = prod.readI32(prodResponse + RESPONSE.errorMessage);
    expect(prod.readString(errorPtr)).toBe('Device registration request was rejected.');
    prodAdapter.cleanup();

    fetchStub.mockClear();
    fetchStub.mockResolvedValueOnce({ ok: true, status: 204 } as Response);
    // Every environment (including development/keyless) registers through the
    // backend endpoint using the effective base URL + API key from commons
    // state. The device-registration URL is used as-is, with no query rewrite
    // and no extra request-preference header.
    const dev = createFakeModule();
    const devAdapter = DeviceRegistrationAdapter.install(dev.module, {
      baseURL: 'https://development.invalid',
      apiKey: 'test-development-key',
      environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
      sdkVersion: '0.19.13',
    });
    const devEndpoint = dev.allocateString('/api/v1/devices/register');
    const devBody = dev.allocateString('{}');
    const devResponse = dev.allocateString(' '.repeat(RESPONSE.size));
    expect(callback(dev, CALLBACK.httpPost)(devEndpoint, devBody, 1, devResponse, 0)).toBe(-100);
    await DeviceRegistrationAdapter.waitForPendingRegistration(dev.module);
    expect(callback(dev, CALLBACK.httpPost)(devEndpoint, devBody, 1, devResponse, 0)).toBe(0);
    expect(fetchStub.mock.calls[0][0]).toBe('https://development.invalid/api/v1/devices/register');
    const devHeaders = new Headers((fetchStub.mock.calls[0][1] as RequestInit).headers);
    expect(devHeaders.get('apikey')).toBe('test-development-key');
    expect(devHeaders.get('authorization')).toBe('Bearer test-access-token');
    expect(devHeaders.get('prefer')).toBeNull();
    devAdapter.cleanup();

    fetchStub.mockClear();
    const noConfig = createFakeModule();
    const noConfigAdapter = DeviceRegistrationAdapter.install(noConfig.module, {
      environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
      sdkVersion: '0.19.13',
    });
    const noConfigEndpoint = noConfig.allocateString('/api/v1/devices/register');
    const noConfigBody = noConfig.allocateString('{}');
    const noConfigResponse = noConfig.allocateString(' '.repeat(RESPONSE.size));
    expect(callback(noConfig, CALLBACK.httpPost)(
      noConfigEndpoint,
      noConfigBody,
      0,
      noConfigResponse,
      0,
    )).toBe(-103);
    expect(noConfig.readI32(noConfigResponse + RESPONSE.result)).toBe(-103);
    expect(noConfig.readI32(noConfigResponse + RESPONSE.statusCode)).toBe(0);
    expect(fetchStub).not.toHaveBeenCalled();
    noConfigAdapter.cleanup();
  });

  it('never combines a partial override with the embedded credential pair', () => {
    for (const configuration of [
      { baseURL: 'https://attacker.invalid' },
      { apiKey: 'configured-key-without-origin' },
    ]) {
      const handle = createFakeModule();
      const adapter = DeviceRegistrationAdapter.install(handle.module, {
        ...configuration,
        environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
        sdkVersion: '0.19.13',
      });
      const endpoint = handle.allocateString('/api/v1/devices/register');
      const body = handle.allocateString('{}');
      const response = handle.allocateString(' '.repeat(RESPONSE.size));

      expect(callback(handle, CALLBACK.httpPost)(endpoint, body, 0, response, 0)).toBe(-103);
      expect(fetchStub).not.toHaveBeenCalled();
      adapter.cleanup();
    }
  });

  it('turns an aborted registration fetch into a timeout failure', async () => {
    fetchStub.mockImplementationOnce((_url: string, init: RequestInit) => (
      new Promise((_resolve, reject) => {
        init.signal?.addEventListener('abort', () => {
          reject(new DOMException('aborted', 'AbortError'));
        }, { once: true });
      })
    ));
    const handle = createFakeModule();
    const adapter = DeviceRegistrationAdapter.install(handle.module, {
      baseURL: 'https://relay.test',
      apiKey: 'test-api-key',
      environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
      sdkVersion: '0.19.13',
      requestTimeoutMs: 1,
    });
    const endpoint = handle.allocateString('/api/v1/devices/register');
    const body = handle.allocateString('{}');
    const response = handle.allocateString(' '.repeat(RESPONSE.size));

    expect(callback(handle, CALLBACK.httpPost)(endpoint, body, 1, response, 0)).toBe(-100);
    await DeviceRegistrationAdapter.waitForPendingRegistration(handle.module);
    expect(callback(handle, CALLBACK.httpPost)(endpoint, body, 1, response, 0)).toBe(-151);
    const errorPtr = handle.readI32(response + RESPONSE.errorMessage);
    expect(handle.readString(errorPtr)).toBe('Device registration request timed out.');
    adapter.cleanup();
  });

  it('clears native callbacks before releasing function pointers and memory', () => {
    const handle = createFakeModule();
    const adapter = DeviceRegistrationAdapter.install(handle.module, {
      baseURL: 'https://relay.test',
      apiKey: 'test-api-key',
      environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
      sdkVersion: '0.19.13',
    });
    adapter.cleanup();

    const clearIndex = handle.lifecycle.indexOf('clear');
    const firstRemoval = handle.lifecycle.findIndex((entry) => entry.startsWith('remove:'));
    const firstFree = handle.lifecycle.findIndex((entry) => entry.startsWith('free:'));
    expect(clearIndex).toBeGreaterThanOrEqual(0);
    expect(firstRemoval).toBeGreaterThan(clearIndex);
    expect(firstFree).toBeGreaterThan(clearIndex);
  });
});
