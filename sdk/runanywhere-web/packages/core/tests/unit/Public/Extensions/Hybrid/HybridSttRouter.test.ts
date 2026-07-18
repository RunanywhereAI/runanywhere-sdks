import { afterEach, describe, expect, it } from 'vitest';

import {
  Cloud,
  HybridSttRouter,
  offlineSherpa,
  onlineCloud,
} from '../../../../../src/index';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../../src/runtime/EmscriptenModule';

interface HybridHarness {
  module: EmscriptenRunanywhereModule;
  calls: {
    cloudRegisters: number;
    engineNames: string[];
    createdServices: string[];
    destroyedServices: number[];
  };
}

afterEach(() => {
  Cloud.clear();
  Cloud.unregister();
  clearRunanywhereModule();
});

describe('HybridSttRouter', () => {
  it('creates and pairs the offline Sherpa service through the exported router ABI', async () => {
    const harness = fakeHybridModule();
    registerWasmModule(['stt'], harness.module, ['onnx', 'sherpa']);

    expect(Cloud.registerBackend()).toBe(true);
    Cloud.register({
      id: 'cloud-stt',
      provider: 'sarvam',
      model: 'saaras:v2.5',
      apiKey: 'test-key',
    });

    const router = await HybridSttRouter.create();
    router.setPair(offlineSherpa('local-whisper'), onlineCloud('cloud-stt'));
    router.close();

    expect(HybridSttRouter.isSupported()).toBe(true);
    expect(harness.calls.cloudRegisters).toBe(1);
    expect(harness.calls.engineNames).toEqual(['sherpa', 'cloud']);
    expect(harness.calls.createdServices).toEqual(['sherpa', 'cloud']);
    expect(harness.calls.destroyedServices).toEqual([101, 102]);
  });

  it('reports unsupported when the loaded WASM omits a required router export', async () => {
    const harness = fakeHybridModule();
    delete (harness.module as EmscriptenRunanywhereModule & {
      _rac_stt_hybrid_router_create_service?: unknown;
    })._rac_stt_hybrid_router_create_service;
    registerWasmModule(['stt'], harness.module, ['onnx', 'sherpa']);

    expect(HybridSttRouter.isSupported()).toBe(false);
    await expect(HybridSttRouter.create()).rejects.toThrow(
      'Backend not available for: hybrid.stt',
    );
  });
});

function fakeHybridModule(): HybridHarness {
  const heap = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  const calls: HybridHarness['calls'] = {
    cloudRegisters: 0,
    engineNames: [],
    createdServices: [],
    destroyedServices: [],
  };
  let nextAllocation = 1024;
  let nextService = 101;

  const allocate = (size: number): number => {
    const pointer = nextAllocation;
    nextAllocation += (Math.max(size, 1) + 7) & ~7;
    if (nextAllocation >= heap.byteLength) throw new Error('fake hybrid WASM heap exhausted');
    return pointer;
  };
  const readCString = (pointer: number): string => {
    let end = pointer;
    while (heapU8[end] !== 0) end += 1;
    return new TextDecoder().decode(heapU8.subarray(pointer, end));
  };

  const module = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: new Int32Array(heap),
    _malloc: allocate,
    _free: () => undefined,
    lengthBytesUTF8: (value: string) => new TextEncoder().encode(value).byteLength,
    stringToUTF8: (value: string, pointer: number, maxBytes: number) => {
      const bytes = new TextEncoder().encode(value);
      heapU8.set(bytes.subarray(0, maxBytes - 1), pointer);
      heapU8[pointer + Math.min(bytes.byteLength, maxBytes - 1)] = 0;
    },
    _rac_stt_hybrid_router_create: (outHandlePtr: number) => {
      heapU32[outHandlePtr >>> 2] = 77;
      return 0;
    },
    _rac_stt_hybrid_router_destroy: () => undefined,
    _rac_stt_hybrid_router_cancel: () => 0,
    _rac_stt_hybrid_router_set_offline_service_proto: () => 0,
    _rac_stt_hybrid_router_set_online_service_proto: () => 0,
    _rac_stt_hybrid_router_set_policy_proto: () => 0,
    _rac_stt_hybrid_router_transcribe_proto: () => 0,
    _rac_stt_hybrid_router_proto_buffer_free: () => undefined,
    _rac_plugin_find_for_engine: (_primitive: number, engineNamePtr: number) => {
      const engineName = readCString(engineNamePtr);
      calls.engineNames.push(engineName);
      return engineName === 'sherpa' || engineName === 'cloud' ? 1 : 0;
    },
    _rac_stt_hybrid_router_create_service: (engineNamePtr: number) => {
      calls.createdServices.push(readCString(engineNamePtr));
      return nextService++;
    },
    _rac_stt_hybrid_router_destroy_service: (servicePtr: number) => {
      calls.destroyedServices.push(servicePtr);
    },
    _rac_backend_cloud_register: () => {
      calls.cloudRegisters += 1;
      return 0;
    },
    _rac_backend_cloud_unregister: () => 0,
    // registerWasmModule installs the default model-registry adapter whenever
    // an STT module is registered; the hybrid router test itself does not use
    // these exports, but the module contract validates their presence.
    _rac_get_model_registry: () => 1,
    _rac_model_registry_refresh_proto: () => 0,
    _rac_model_registry_register_proto: () => 0,
    _rac_model_registry_update_proto: () => 0,
    _rac_model_registry_update_download_status: () => 0,
    _rac_model_registry_get_proto: () => 0,
    _rac_model_registry_list_proto: () => 0,
    _rac_model_registry_query_proto: () => 0,
    _rac_model_registry_list_downloaded_proto: () => 0,
    _rac_model_registry_remove_proto: () => 0,
    _rac_model_registry_import_proto: () => 0,
    _rac_model_registry_proto_free: () => undefined,
  } as unknown as EmscriptenRunanywhereModule;

  return { module, calls };
}
