import { afterEach, describe, expect, it } from 'vitest';
import {
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoraAdapterDownloadCompletedResult,
  type LoraAdapterCatalogEntry as ProtoLoraAdapterCatalogEntry,
  type LoraAdapterCatalogGetRequest as ProtoLoraAdapterCatalogGetRequest,
  type LoraAdapterCatalogListRequest as ProtoLoraAdapterCatalogListRequest,
  type LoraAdapterCatalogQuery as ProtoLoraAdapterCatalogQuery,
  type LoraAdapterDownloadCompletedRequest as ProtoLoraAdapterDownloadCompletedRequest,
} from '@runanywhere/proto-ts/lora_options';
import { ProtoErrorCode } from '../../../../src/Foundation/SDKException';
import { ModalityProtoAdapter, type ModalityProtoModule } from '../../../../src/Adapters/ModalityProtoAdapter';
import { clearRunanywhereModule } from '../../../../src/runtime/EmscriptenModule';
import { LoRA } from '../../../../src/Public/Extensions/RunAnywhere+LoRA';

const PROTO_BUFFER_SIZE = 16;
const OFF_DATA = 0;
const OFF_SIZE = 4;
const OFF_STATUS = 8;
const OFF_ERROR = 12;
const LORA_REGISTRY_HANDLE = 77;

interface CapturedCatalogCalls {
  register?: {
    registry: number;
    entry: ProtoLoraAdapterCatalogEntry;
  };
  list?: {
    registry: number;
    request: ProtoLoraAdapterCatalogListRequest;
  };
  query?: {
    registry: number;
    query: ProtoLoraAdapterCatalogQuery;
  };
  get?: {
    registry: number;
    request: ProtoLoraAdapterCatalogGetRequest;
  };
  markDownloadCompleted?: {
    registry: number;
    request: ProtoLoraAdapterDownloadCompletedRequest;
  };
}

describe('LoRA catalog proto facade', () => {
  afterEach(() => {
    clearRunanywhereModule();
    ModalityProtoAdapter.clearDefaultModule();
  });

  it('routes catalog list/query/get/download-completion through generated proto bytes', async () => {
    const captured: CapturedCatalogCalls = {};
    ModalityProtoAdapter.setDefaultModule(makeLoRACatalogModule(captured));
    const entry = catalogEntry();

    await expect(LoRA.catalog.register(entry)).resolves.toMatchObject({
      id: 'style',
      name: 'Style',
    });

    await expect(LoRA.catalog.list({
      query: { modelId: 'base-model', tags: [] },
      includeCounts: true,
    })).resolves.toMatchObject({
      success: true,
      totalCount: 1,
      filteredCount: 1,
      downloadedCount: 0,
      entries: [expect.objectContaining({ id: 'style' })],
    });

    await expect(LoRA.catalog.query({
      modelId: 'base-model',
      downloadedOnly: true,
      tags: ['style'],
    })).resolves.toMatchObject({
      success: true,
      entries: [expect.objectContaining({ id: 'style' })],
    });

    await expect(LoRA.catalog.get({ adapterId: 'style' })).resolves.toMatchObject({
      found: true,
      entry: expect.objectContaining({ id: 'style' }),
    });

    await expect(LoRA.catalog.markDownloadCompleted({
      adapterId: 'style',
      localPath: 'opfs://runanywhere/lora/style.gguf',
      sizeBytes: 12,
      imported: false,
      statusMessage: 'download completed',
    })).resolves.toMatchObject({
      success: true,
      persisted: true,
      entry: expect.objectContaining({ id: 'style' }),
    });

    expect(captured.register).toMatchObject({
      registry: LORA_REGISTRY_HANDLE,
      entry: { id: 'style' },
    });
    expect(captured.list).toMatchObject({
      registry: LORA_REGISTRY_HANDLE,
      request: { includeCounts: true, query: { modelId: 'base-model' } },
    });
    expect(captured.query).toMatchObject({
      registry: LORA_REGISTRY_HANDLE,
      query: { modelId: 'base-model', downloadedOnly: true, tags: ['style'] },
    });
    expect(captured.get).toMatchObject({
      registry: LORA_REGISTRY_HANDLE,
      request: { adapterId: 'style' },
    });
    expect(captured.markDownloadCompleted).toMatchObject({
      registry: LORA_REGISTRY_HANDLE,
      request: {
        adapterId: 'style',
        localPath: 'opfs://runanywhere/lora/style.gguf',
      },
    });
  });

  it('reports typed unavailable when catalog exports are missing', async () => {
    ModalityProtoAdapter.setDefaultModule(makeBaseProtoModule());

    expect(LoRA.catalog.supportsNative()).toBe(false);
    expect(LoRA.catalog.missingExports()).toEqual(expect.arrayContaining([
      '_rac_get_lora_registry',
      '_rac_lora_register_proto',
      '_rac_lora_catalog_list_proto',
      '_rac_lora_catalog_query_proto',
      '_rac_lora_catalog_get_proto',
      '_rac_lora_catalog_mark_download_completed_proto',
    ]));

    await expect(LoRA.catalog.list()).rejects.toMatchObject({
      // `.code` is the positive proto ErrorCode; the signed C-ABI value is `.cAbiCode`.
      code: ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE,
    });
  });
});

function catalogEntry(): ProtoLoraAdapterCatalogEntry {
  return {
    id: 'style',
    name: 'Style',
    description: 'Style adapter',
    url: 'https://example.test/style.gguf',
    filename: 'style.gguf',
    compatibleModels: ['base-model'],
    sizeBytes: 12,
    author: undefined,
    defaultScale: 0.75,
    checksumSha256: undefined,
    license: undefined,
    tags: ['style'],
    metadata: {},
    localPath: undefined,
    isDownloaded: undefined,
    downloadedAtUnixMs: undefined,
    isImported: undefined,
    statusMessage: undefined,
  };
}

function makeLoRACatalogModule(captured: CapturedCatalogCalls): ModalityProtoModule {
  const module = makeBaseProtoModule();

  module._rac_get_lora_registry = () => LORA_REGISTRY_HANDLE;
  module._rac_lora_register_proto = (
    registry: number,
    entryPtr: number,
    entrySize: number,
    outEntry: number,
  ) => {
    const entry = LoraAdapterCatalogEntry.decode(readBytes(module, entryPtr, entrySize));
    captured.register = { registry, entry };
    writeResult(module, outEntry, LoraAdapterCatalogEntry.encode({
      ...entry,
      statusMessage: 'registered by wasm',
    }).finish());
    return 0;
  };
  module._rac_lora_catalog_list_proto = (
    registry: number,
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ) => {
    const request = LoraAdapterCatalogListRequest.decode(readBytes(module, requestPtr, requestSize));
    captured.list = { registry, request };
    writeResult(module, outResult, LoraAdapterCatalogListResult.encode({
      success: true,
      entries: [catalogEntry()],
      errorMessage: '',
      totalCount: 1,
      filteredCount: 1,
      downloadedCount: 0,
    }).finish());
    return 0;
  };
  module._rac_lora_catalog_query_proto = (
    registry: number,
    queryPtr: number,
    querySize: number,
    outResult: number,
  ) => {
    const query = LoraAdapterCatalogQuery.decode(readBytes(module, queryPtr, querySize));
    captured.query = { registry, query };
    writeResult(module, outResult, LoraAdapterCatalogListResult.encode({
      success: true,
      entries: [catalogEntry()],
      errorMessage: '',
      totalCount: 1,
      filteredCount: 1,
      downloadedCount: 0,
    }).finish());
    return 0;
  };
  module._rac_lora_catalog_get_proto = (
    registry: number,
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ) => {
    const request = LoraAdapterCatalogGetRequest.decode(readBytes(module, requestPtr, requestSize));
    captured.get = { registry, request };
    writeResult(module, outResult, LoraAdapterCatalogGetResult.encode({
      found: true,
      entry: catalogEntry(),
      errorMessage: '',
    }).finish());
    return 0;
  };
  module._rac_lora_catalog_mark_download_completed_proto = (
    registry: number,
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ) => {
    const request = LoraAdapterDownloadCompletedRequest.decode(
      readBytes(module, requestPtr, requestSize),
    );
    captured.markDownloadCompleted = { registry, request };
    writeResult(module, outResult, LoraAdapterDownloadCompletedResult.encode({
      success: true,
      entry: {
        ...catalogEntry(),
        localPath: request.localPath,
        isDownloaded: true,
        downloadedAtUnixMs: request.completedAtUnixMs ?? 1,
        isImported: request.imported,
        statusMessage: request.statusMessage,
      },
      errorMessage: '',
      persisted: true,
    }).finish());
    return 0;
  };

  return module;
}

function makeBaseProtoModule(): ModalityProtoModule {
  const heap = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  const heap32 = new Int32Array(heap);
  let nextPtr = 256;

  return {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc(size: number): number {
      const alignedSize = Math.max(4, (size + 3) & ~3);
      const ptr = nextPtr;
      nextPtr += alignedSize;
      return ptr;
    },
    _free: () => undefined,
    _rac_proto_buffer_init(bufferPtr: number): void {
      heapU32[(bufferPtr + OFF_DATA) >>> 2] = 0;
      heapU32[(bufferPtr + OFF_SIZE) >>> 2] = 0;
      heap32[(bufferPtr + OFF_STATUS) >>> 2] = 0;
      heapU32[(bufferPtr + OFF_ERROR) >>> 2] = 0;
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => PROTO_BUFFER_SIZE,
    _rac_wasm_offsetof_proto_buffer_data: () => OFF_DATA,
    _rac_wasm_offsetof_proto_buffer_size: () => OFF_SIZE,
    _rac_wasm_offsetof_proto_buffer_status: () => OFF_STATUS,
    _rac_wasm_offsetof_proto_buffer_error_message: () => OFF_ERROR,
  };
}

function readBytes(module: ModalityProtoModule, ptr: number, size: number): Uint8Array {
  return module.HEAPU8!.slice(ptr, ptr + size);
}

function writeResult(module: ModalityProtoModule, outResult: number, resultBytes: Uint8Array): void {
  const resultPtr = module._malloc!(resultBytes.byteLength);
  module.HEAPU8!.set(resultBytes, resultPtr);
  module.HEAPU32![(outResult + OFF_DATA) >>> 2] = resultPtr;
  module.HEAPU32![(outResult + OFF_SIZE) >>> 2] = resultBytes.byteLength;
  module.HEAP32![(outResult + OFF_STATUS) >>> 2] = 0;
}
