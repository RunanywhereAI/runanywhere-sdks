import { describe, expect, it, afterEach } from 'vitest';

import { ModelRegistryAdapter } from '../Adapters/ModelRegistryAdapter';
import { SolutionAdapter } from '../Adapters/SolutionAdapter';
import {
  clearRunanywhereModule,
  setRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from './EmscriptenModule';

function fakeModule(): EmscriptenRunanywhereModule {
  const heap = new ArrayBuffer(1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  let nextPtr = 8;
  return {
    HEAPU8: heapU8,
    HEAP32: new Int32Array(heap),
    HEAPU32: heapU32,
    addFunction: () => 1,
    removeFunction: () => undefined,
    _malloc(size: number): number {
      const ptr = nextPtr;
      nextPtr += Math.max(size, 4);
      return ptr;
    },
    _free: () => undefined,
    UTF8ToString: (ptr: number) => {
      let end = ptr;
      while (heapU8[end] !== 0) end += 1;
      return new TextDecoder().decode(heapU8.subarray(ptr, end));
    },
    stringToUTF8(str: string, ptr: number, maxBytesToWrite: number): number {
      const bytes = new TextEncoder().encode(str);
      heapU8.set(bytes.subarray(0, maxBytesToWrite - 1), ptr);
      heapU8[ptr + Math.min(bytes.length, maxBytesToWrite - 1)] = 0;
      return bytes.length;
    },
    lengthBytesUTF8: (str: string) => new TextEncoder().encode(str).length,
    _rac_voice_agent_set_proto_callback: () => 0,
    _rac_llm_set_stream_proto_callback: () => 0,
    _rac_llm_unset_stream_proto_callback: () => 0,
    _rac_llm_extract_thinking: () => 0,
    _rac_llm_strip_thinking: () => 0,
    _rac_llm_split_thinking_tokens: () => 0,
    _rac_solution_create_from_proto: (_bytesPtr, _bytesLen, outHandlePtr) => {
      heapU32[outHandlePtr >>> 2] = 123;
      return 0;
    },
    _rac_solution_create_from_yaml: (_yamlPtr, outHandlePtr) => {
      heapU32[outHandlePtr >>> 2] = 456;
      return 0;
    },
    _rac_solution_start: () => 0,
    _rac_solution_stop: () => 0,
    _rac_solution_cancel: () => 0,
    _rac_solution_feed: () => 0,
    _rac_solution_close_input: () => 0,
    _rac_solution_destroy: () => undefined,
  };
}

describe('Emscripten module singleton wiring', () => {
  afterEach(() => {
    clearRunanywhereModule();
    ModelRegistryAdapter.clearDefaultModule();
  });

  it('allows SolutionAdapter to use the singleton module', () => {
    setRunanywhereModule(fakeModule());
    const handle = SolutionAdapter.run({ yaml: 'name: test' });
    expect(handle.isAlive).toBe(true);
    handle.destroy();
    expect(handle.isAlive).toBe(false);
  });

  it('clears ModelRegistryAdapter default module', () => {
    ModelRegistryAdapter.setDefaultModule({
      _rac_get_model_registry: () => 1,
      _rac_model_registry_refresh: () => 0,
    });
    expect(ModelRegistryAdapter.tryDefault()).not.toBeNull();
    ModelRegistryAdapter.clearDefaultModule();
    expect(ModelRegistryAdapter.tryDefault()).toBeNull();
  });
});
