import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  ModelInfo as ModelInfoCodec,
  ModelInfoList as ModelInfoListCodec,
  ModelRegistryRefreshRequest as RefreshRequestCodec,
  ModelRegistryStatus,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import { RAC_ERROR_NOT_FOUND } from '../../../src/Foundation/RACErrors';
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
  readonly refreshRequests: Uint8Array[];
  readonly registerRequests: Uint8Array[];
  readonly liveAllocations: ReadonlySet<number>;
  setListModels(models: ModelInfo[]): void;
  setExistingModel(model: ModelInfo): void;
  failList(resultCode: number): void;
}

function createRegistryModule(handle: number): FakeRegistryModule {
  const memory = new ArrayBuffer(16 * 1024);
  const heapU8 = new Uint8Array(memory);
  const heapU32 = new Uint32Array(memory);
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const calls: DownloadStatusCall[] = [];
  const refreshRequests: Uint8Array[] = [];
  const registerRequests: Uint8Array[] = [];
  const liveAllocations = new Set<number>();
  const registryModels = new Map<string, ModelInfo>();
  let listedModels: ModelInfo[] = [];
  let listResult = 0;
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
  const writeProtoResult = (bytes: Uint8Array, outBytesPtr: number, outSizePtr: number): void => {
    const resultPtr = malloc(bytes.byteLength);
    heapU8.set(bytes, resultPtr);
    heapU32[outBytesPtr >>> 2] = resultPtr;
    heapU32[outSizePtr >>> 2] = bytes.byteLength;
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
    _rac_model_registry_refresh_proto: (_registry, requestPtr, requestSize) => {
      refreshRequests.push(heapU8.slice(requestPtr, requestPtr + requestSize));
      return 0;
    },
    _rac_model_registry_register_proto: (_registry, protoPtr, protoSize) => {
      const request = ModelInfoCodec.decode(heapU8.slice(protoPtr, protoPtr + protoSize));
      registerRequests.push(heapU8.slice(protoPtr, protoPtr + protoSize));
      registryModels.set(request.id, request);
      return 0;
    },
    _rac_model_registry_update_proto: () => 0,
    _rac_model_registry_update_download_status: (_registry, modelIdPtr, localPathPtr) => {
      calls.push({
        modelId: readString(modelIdPtr),
        localPath: localPathPtr === 0 ? null : readString(localPathPtr),
      });
      return 0;
    },
    _rac_model_registry_get_proto: (_registry, modelIdPtr, outBytesPtr, outSizePtr) => {
      const model = registryModels.get(readString(modelIdPtr));
      if (!model) return RAC_ERROR_NOT_FOUND;
      writeProtoResult(ModelInfoCodec.encode(model).finish(), outBytesPtr, outSizePtr);
      return 0;
    },
    _rac_model_registry_list_proto: (_registry, outBytesPtr, outSizePtr) => {
      if (listResult !== 0) return listResult;
      const listBytes = ModelInfoListCodec.encode({ models: listedModels }).finish();
      writeProtoResult(listBytes, outBytesPtr, outSizePtr);
      return 0;
    },
    _rac_model_registry_query_proto: () => 0,
    _rac_model_registry_list_downloaded_proto: () => 0,
    _rac_model_registry_remove_proto: () => 0,
    _rac_model_registry_import_proto: () => 0,
    _rac_model_registry_proto_free: (ptr) => {
      if (ptr) module._free?.(ptr);
    },
  };

  return {
    module,
    calls,
    refreshRequests,
    registerRequests,
    liveAllocations,
    setListModels: (models) => { listedModels = models; },
    setExistingModel: (model) => { registryModels.set(model.id, model); },
    failList: (resultCode) => { listResult = resultCode; },
  };
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

  it('rejects an outdated artifact that omits a required registry export', () => {
    const incomplete = createRegistryModule(404);
    delete (incomplete.module as Partial<ModelRegistryModule>)
      ._rac_model_registry_update_download_status;

    expect(() => ModelRegistryAdapter.setDefaultModule(incomplete.module))
      .toThrow(/missing required model-registry exports.*update_download_status/);
    expect(ModelRegistryAdapter.tryDefault()).toBeNull();
  });
});

describe('ModelRegistryAdapter refresh', () => {
  beforeEach(() => ModelRegistryAdapter.clearDefaultModule());
  afterEach(() => ModelRegistryAdapter.clearDefaultModule());

  it('rescans every live registry and fetches the remote catalog only once', () => {
    const commons = createRegistryModule(101);
    const llama = createRegistryModule(202);
    const onnx = createRegistryModule(303);
    ModelRegistryAdapter.setDefaultModule(commons.module);
    ModelRegistryAdapter.setDefaultModule(llama.module);
    ModelRegistryAdapter.setDefaultModule(onnx.module);

    const registry = ModelRegistryAdapter.tryDefault();
    expect(registry).not.toBeNull();
    expect(registry!.refresh({ includeRemoteCatalog: true })).toBe(true);

    for (const target of [commons, llama, onnx]) {
      expect(target.refreshRequests).toHaveLength(1);
      const request = RefreshRequestCodec.decode(target.refreshRequests[0]);
      expect(request.rescanLocal).toBe(true);
      expect(request.includeDownloadedState).toBe(true);
      expect(request.includeRemoteCatalog).toBe(target === onnx);
    }
  });

  it('fails when the remote refresh cannot list its primary catalog', () => {
    const commons = createRegistryModule(101);
    const llama = createRegistryModule(202);
    ModelRegistryAdapter.setDefaultModule(commons.module);
    ModelRegistryAdapter.setDefaultModule(llama.module);
    llama.failList(RAC_ERROR_NOT_FOUND);

    const registry = ModelRegistryAdapter.tryDefault();
    expect(registry).not.toBeNull();
    expect(registry!.refresh({ includeRemoteCatalog: true })).toBe(false);
    expect(commons.refreshRequests).toHaveLength(1);
  });

  it('preserves sibling download state when replaying remote catalog rows', () => {
    const commons = createRegistryModule(101);
    const llama = createRegistryModule(202);
    ModelRegistryAdapter.setDefaultModule(commons.module);
    ModelRegistryAdapter.setDefaultModule(llama.module);

    const catalogModel = ModelInfoCodec.fromPartial({
      id: 'llama-model',
      name: 'Updated catalog name',
    });
    const downloadedModel = ModelInfoCodec.fromPartial({
      id: 'llama-model',
      name: 'Old catalog name',
      localPath: '/opfs/models/llama-model.gguf',
      checksumSha256: 'abc123',
      registryStatus: ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED,
      isAvailable: true,
    });
    llama.setListModels([catalogModel]);
    commons.setExistingModel(downloadedModel);

    const registry = ModelRegistryAdapter.tryDefault();
    expect(registry).not.toBeNull();
    expect(registry!.refresh({ includeRemoteCatalog: true, rescanLocal: false })).toBe(true);

    expect(commons.registerRequests).toHaveLength(1);
    const synced = ModelInfoCodec.decode(commons.registerRequests[0]);
    expect(synced.name).toBe('Updated catalog name');
    expect(synced.localPath).toBe('/opfs/models/llama-model.gguf');
    expect(synced.checksumSha256).toBe('abc123');
    expect(synced.registryStatus).toBe(ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED);
    expect(synced.isAvailable).toBe(true);
  });
});
