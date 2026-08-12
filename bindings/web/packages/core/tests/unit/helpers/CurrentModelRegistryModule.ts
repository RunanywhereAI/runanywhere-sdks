import type { ModelRegistryModule } from '../../../src/Adapters/ModelRegistryAdapter.js';

interface TestWasmMemoryModule {
  HEAPU8: Uint8Array;
  _malloc(size: number): number;
  _free(pointer: number): void;
  lengthBytesUTF8?: (value: string) => number;
  stringToUTF8?: (
    value: string,
    pointer: number,
    maxBytesToWrite: number,
  ) => void;
}

type CurrentRegistryExports = Pick<ModelRegistryModule,
  | '_rac_get_model_registry'
  | '_rac_model_registry_refresh_proto'
  | '_rac_model_registry_register_proto'
  | '_rac_model_registry_update_proto'
  | '_rac_model_registry_update_download_status'
  | '_rac_model_registry_get_proto'
  | '_rac_model_registry_list_proto'
  | '_rac_model_registry_query_proto'
  | '_rac_model_registry_list_downloaded_proto'
  | '_rac_model_registry_remove_proto'
  | '_rac_model_registry_import_proto'
  | '_rac_model_registry_proto_free'
>;

/**
 * Adds the mandatory current model-registry ABI to a focused WASM test fake.
 *
 * These exports intentionally model an empty registry; they are not a legacy
 * compatibility surface. Feature tests that register a backend module must
 * expose the same current ABI as production artifacts even when the registry
 * itself is outside the behavior under test.
 */
export function installCurrentModelRegistryExports<T extends object>(
  module: T,
): T & ModelRegistryModule {
  const memory = module as Partial<TestWasmMemoryModule>;
  if (
    !(memory.HEAPU8 instanceof Uint8Array)
    || typeof memory._malloc !== 'function'
    || typeof memory._free !== 'function'
  ) {
    throw new TypeError('Current model-registry test module requires WASM heap allocators');
  }

  const encoder = new TextEncoder();
  const clearOutput = (bytesPointer: number, sizePointer: number): void => {
    const heap = new DataView(
      memory.HEAPU8!.buffer,
      memory.HEAPU8!.byteOffset,
      memory.HEAPU8!.byteLength,
    );
    heap.setUint32(bytesPointer, 0, true);
    heap.setUint32(sizePointer, 0, true);
  };

  memory.lengthBytesUTF8 ??= (value: string): number => encoder.encode(value).byteLength;
  memory.stringToUTF8 ??= (
    value: string,
    pointer: number,
    maxBytesToWrite: number,
  ): void => {
    const bytes = encoder.encode(value);
    const written = Math.min(bytes.byteLength, Math.max(0, maxBytesToWrite - 1));
    memory.HEAPU8!.set(bytes.subarray(0, written), pointer);
    if (maxBytesToWrite > 0) memory.HEAPU8![pointer + written] = 0;
  };

  const registryExports: CurrentRegistryExports = {
    _rac_get_model_registry: () => 1,
    _rac_model_registry_refresh_proto(
      _handle,
      _requestBytes,
      _requestSize,
      outputBytes,
      outputSize,
    ): number {
      clearOutput(outputBytes, outputSize);
      return 0;
    },
    _rac_model_registry_register_proto: () => 0,
    _rac_model_registry_update_proto: () => 0,
    _rac_model_registry_update_download_status: () => 0,
    _rac_model_registry_get_proto(_handle, _modelId, outputBytes, outputSize): number {
      clearOutput(outputBytes, outputSize);
      return 0;
    },
    _rac_model_registry_list_proto(_handle, outputBytes, outputSize): number {
      clearOutput(outputBytes, outputSize);
      return 0;
    },
    _rac_model_registry_query_proto(
      _handle,
      _queryBytes,
      _querySize,
      outputBytes,
      outputSize,
    ): number {
      clearOutput(outputBytes, outputSize);
      return 0;
    },
    _rac_model_registry_list_downloaded_proto(_handle, outputBytes, outputSize): number {
      clearOutput(outputBytes, outputSize);
      return 0;
    },
    _rac_model_registry_remove_proto: () => 0,
    _rac_model_registry_import_proto(_handle, _requestBytes, _requestSize, output): number {
      memory.HEAPU8!.fill(0, output, output + 16);
      return 0;
    },
    _rac_model_registry_proto_free: () => undefined,
  };

  return Object.assign(module, memory, registryExports) as T & ModelRegistryModule;
}
