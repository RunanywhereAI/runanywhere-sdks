import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  ModelRegistryAdapter,
  type ModelRegistryModule,
} from '../../../src/Adapters/ModelRegistryAdapter';

interface DownloadStatusCall {
  readonly modelId: string;
  readonly localPath: string | null;
}

interface FakeRegistryModule {
  readonly module: ModelRegistryModule;
  readonly calls: DownloadStatusCall[];
  readonly liveAllocations: ReadonlySet<number>;
}

function createRegistryModule(handle: number): FakeRegistryModule {
  const memory = new ArrayBuffer(16 * 1024);
  const heapU8 = new Uint8Array(memory);
  const heapU32 = new Uint32Array(memory);
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const calls: DownloadStatusCall[] = [];
  const liveAllocations = new Set<number>();
  let nextPtr = 256;

  const malloc = (size: number): number => {
    const ptr = nextPtr;
    nextPtr += Math.max(8, (size + 7) & ~7);
    liveAllocations.add(ptr);
    return ptr;
  };
  const readString = (ptr: number): string => {
    let end = ptr;
    while (end < heapU8.length && heapU8[end] !== 0) end += 1;
    return decoder.decode(heapU8.subarray(ptr, end));
  };

  const module: ModelRegistryModule = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    _malloc: malloc,
    _free: (ptr) => {
      if (!liveAllocations.delete(ptr)) {
        throw new Error(`Double or foreign free at ${ptr}`);
      }
    },
    lengthBytesUTF8: (value) => encoder.encode(value).length,
    stringToUTF8: (value, ptr, maxBytes) => {
      const bytes = encoder.encode(value).subarray(0, Math.max(0, maxBytes - 1));
      heapU8.set(bytes, ptr);
      heapU8[ptr + bytes.length] = 0;
    },
    _rac_get_model_registry: () => handle,
    _rac_model_registry_register_proto: () => 0,
    _rac_model_registry_update_proto: () => 0,
    _rac_model_registry_update_download_status: (_registry, modelIdPtr, localPathPtr) => {
      calls.push({
        modelId: readString(modelIdPtr),
        localPath: localPathPtr === 0 ? null : readString(localPathPtr),
      });
      return 0;
    },
    _rac_model_registry_get_proto: () => 0,
    _rac_model_registry_list_proto: () => 0,
    _rac_model_registry_query_proto: () => 0,
    _rac_model_registry_list_downloaded_proto: () => 0,
    _rac_model_registry_remove_proto: () => 0,
    _rac_model_registry_proto_free: () => undefined,
  };

  return { module, calls, liveAllocations };
}

describe('ModelRegistryAdapter download status', () => {
  beforeEach(() => ModelRegistryAdapter.clearDefaultModule());
  afterEach(() => ModelRegistryAdapter.clearDefaultModule());

  it('broadcasts path updates and explicit clears to every registered WASM registry', () => {
    const commons = createRegistryModule(101);
    const llama = createRegistryModule(202);
    const onnx = createRegistryModule(303);
    ModelRegistryAdapter.setDefaultModule(commons.module);
    ModelRegistryAdapter.setDefaultModule(llama.module);
    ModelRegistryAdapter.setDefaultModule(onnx.module);

    const registry = ModelRegistryAdapter.tryDefault();
    expect(registry).not.toBeNull();
    expect(registry!.updateDownloadStatus('silero-vad', '/opfs/models/silero-vad')).toBe(true);
    expect(registry!.updateDownloadStatus('silero-vad', null)).toBe(true);

    for (const target of [commons, llama, onnx]) {
      expect(target.calls).toEqual([
        { modelId: 'silero-vad', localPath: '/opfs/models/silero-vad' },
        { modelId: 'silero-vad', localPath: null },
      ]);
      expect(target.liveAllocations.size).toBe(0);
    }
  });

  it('does not disable unrelated proto registry operations when the status ABI is absent', () => {
    const legacy = createRegistryModule(404);
    delete legacy.module._rac_model_registry_update_download_status;
    ModelRegistryAdapter.setDefaultModule(legacy.module);

    const registry = ModelRegistryAdapter.tryDefault();
    expect(registry).not.toBeNull();
    expect(registry!.supportsProtoRegistry()).toBe(true);
    expect(registry!.updateDownloadStatus('silero-vad', null)).toBe(false);
    expect(legacy.calls).toEqual([]);
    expect(legacy.liveAllocations.size).toBe(0);
  });
});
