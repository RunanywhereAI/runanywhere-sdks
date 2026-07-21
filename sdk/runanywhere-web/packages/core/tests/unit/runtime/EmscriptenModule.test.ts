import { afterEach, describe, expect, it, vi } from 'vitest';
import { SolutionConfig } from '@runanywhere/proto-ts/solutions';

import { ModelRegistryAdapter } from '../../../src/Adapters/ModelRegistryAdapter';
import { ModelLifecycleAdapter } from '../../../src/Adapters/ModelLifecycleAdapter';
import { SolutionAdapter } from '../../../src/Adapters/SolutionAdapter';
import {
  clearRunanywhereModule,
  getModuleForCapability,
  getModuleForFramework,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
  unregisterWasmModule,
} from '../../../src/runtime/EmscriptenModule';

interface SolutionCallCounters {
  creates: number;
  starts: number;
  destroys: number;
}

function fakeModule(counters?: SolutionCallCounters): EmscriptenRunanywhereModule {
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
    _rac_proto_buffer_init: () => undefined,
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
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
    _rac_solution_create_from_proto: (_bytesPtr, _bytesLen, outHandlePtr) => {
      if (counters) counters.creates += 1;
      heapU32[outHandlePtr >>> 2] = 123;
      return 0;
    },
    _rac_solution_create_from_yaml: (_yamlPtr, outHandlePtr) => {
      if (counters) counters.creates += 1;
      heapU32[outHandlePtr >>> 2] = 456;
      return 0;
    },
    _rac_solution_start: () => {
      if (counters) counters.starts += 1;
      return 0;
    },
    _rac_solution_stop: () => 0,
    _rac_solution_cancel: () => 0,
    _rac_solution_feed: () => 0,
    _rac_solution_close_input: () => 0,
    _rac_solution_destroy: () => {
      if (counters) counters.destroys += 1;
    },
  };
}

describe('Emscripten module capability wiring', () => {
  afterEach(() => {
    clearRunanywhereModule();
    ModelRegistryAdapter.clearDefaultModule();
  });

  it('allows SolutionAdapter to use the registered commons module', () => {
    registerWasmModule(['commons'], fakeModule());
    const handle = SolutionAdapter.run({ yaml: 'name: test' });
    expect(handle.isAlive).toBe(true);
    handle.destroy();
    expect(handle.isAlive).toBe(false);
  });

  it('pins every RAG solution input form to the registered RAG module', () => {
    const commonsCalls: SolutionCallCounters = { creates: 0, starts: 0, destroys: 0 };
    const ragCalls: SolutionCallCounters = { creates: 0, starts: 0, destroys: 0 };
    const commonsModule = fakeModule(commonsCalls);
    const ragModule = fakeModule(ragCalls);
    ragModule._rac_rag_session_create_proto = () => 0;
    ragModule._rac_rag_query_proto = () => 0;

    registerWasmModule(['commons'], commonsModule);
    // Registry replay is unrelated to this routing contract and the minimal
    // fake modules intentionally omit model-registry proto exports.
    ModelRegistryAdapter.clearDefaultModule();
    registerWasmModule(['rag'], ragModule, ['onnx']);

    const ragHandle = SolutionAdapter.run({ yaml: 'rag:\n  embed_model_id: minilm' });
    ragHandle.start();
    ragHandle.destroy();

    const ragConfig = SolutionConfig.fromPartial({ rag: { embedModelId: 'minilm' } });
    const typedHandle = SolutionAdapter.run({ config: ragConfig });
    typedHandle.start();
    typedHandle.destroy();

    const bytesHandle = SolutionAdapter.run({
      configBytes: SolutionConfig.encode(ragConfig).finish(),
    });
    bytesHandle.start();
    bytesHandle.destroy();

    expect(ragCalls).toEqual({ creates: 3, starts: 3, destroys: 3 });
    expect(commonsCalls).toEqual({ creates: 0, starts: 0, destroys: 0 });

    const voiceHandle = SolutionAdapter.run({ yaml: 'voice_agent:\n  llm_model_id: qwen' });
    voiceHandle.start();
    voiceHandle.destroy();

    expect(commonsCalls).toEqual({ creates: 1, starts: 1, destroys: 1 });
    expect(ragCalls).toEqual({ creates: 3, starts: 3, destroys: 3 });
  });

  it('fails every RAG input form honestly when no module has RAG exports', () => {
    registerWasmModule(['commons'], fakeModule());
    expect(() => SolutionAdapter.run({ yaml: 'rag:\n  embed_model_id: minilm' }))
      .toThrow(/Backend not available for: RAG solution YAML/);
    const ragConfig = SolutionConfig.fromPartial({ rag: { embedModelId: 'minilm' } });
    expect(() => SolutionAdapter.run({ config: ragConfig }))
      .toThrow(/Backend not available for: RAG solution config/);
    expect(() => SolutionAdapter.run({
      configBytes: SolutionConfig.encode(ragConfig).finish(),
    })).toThrow(/Backend not available for: RAG solution config/);
  });

  it('clears ModelRegistryAdapter default module', () => {
    ModelRegistryAdapter.setDefaultModule(fakeModule());
    expect(ModelRegistryAdapter.tryDefault()).not.toBeNull();
    ModelRegistryAdapter.clearDefaultModule();
    expect(ModelRegistryAdapter.tryDefault()).toBeNull();
  });

  it('re-elects live registry and lifecycle adapters after backend teardown', () => {
    const commons = fakeModule();
    const backendA = fakeModule();
    const backendB = fakeModule();
    const resetCommons = vi.fn();
    const resetA = vi.fn();
    const resetB = vi.fn();
    commons._rac_model_lifecycle_reset = resetCommons;
    backendA._rac_model_lifecycle_reset = resetA;
    backendB._rac_model_lifecycle_reset = resetB;

    registerWasmModule(['commons'], commons);
    registerWasmModule(['llm'], backendA, ['llamacpp']);
    registerWasmModule(['stt'], backendB, ['sherpa']);

    unregisterWasmModule(backendB);

    expect(ModelRegistryAdapter.tryDefault()).not.toBeNull();
    expect(ModelLifecycleAdapter.tryDefault()?.reset()).toBe(true);
    expect(resetA).toHaveBeenCalledOnce();
    expect(resetB).not.toHaveBeenCalled();

    unregisterWasmModule(backendA);

    expect(ModelRegistryAdapter.tryDefault()).not.toBeNull();
    expect(ModelLifecycleAdapter.tryDefault()?.reset()).toBe(true);
    expect(resetCommons).toHaveBeenCalledOnce();
    expect(resetA).toHaveBeenCalledOnce();
    expect(resetB).not.toHaveBeenCalled();
  });

  it('restores the surviving owner of a shared capability after teardown', () => {
    const onnx = fakeModule();
    const llama = fakeModule();

    registerWasmModule(['embedding'], onnx, ['onnx']);
    registerWasmModule(['embedding'], llama, ['llamacpp']);
    expect(getModuleForCapability('embedding')).toBe(llama);

    unregisterWasmModule(llama);
    expect(getModuleForCapability('embedding')).toBe(onnx);
    expect(getModuleForFramework('onnx')).toBe(onnx);
    expect(getModuleForFramework('llamacpp')).toBeNull();

    unregisterWasmModule(onnx);
    expect(getModuleForCapability('embedding')).toBeNull();
    expect(getModuleForFramework('onnx')).toBeNull();
  });
});
