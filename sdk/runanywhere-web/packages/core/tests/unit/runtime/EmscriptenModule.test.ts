import { describe, expect, it, afterEach } from 'vitest';
import { SolutionConfig } from '@runanywhere/proto-ts/solutions';

import { ModelRegistryAdapter } from '../../../src/Adapters/ModelRegistryAdapter';
import { SolutionAdapter } from '../../../src/Adapters/SolutionAdapter';
import {
  clearRunanywhereModule,
  registerWasmModule,
  setRunanywhereModule,
  type EmscriptenRunanywhereModule,
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

  it('pins every RAG solution input form to the registered RAG module', () => {
    const commonsCalls: SolutionCallCounters = { creates: 0, starts: 0, destroys: 0 };
    const ragCalls: SolutionCallCounters = { creates: 0, starts: 0, destroys: 0 };
    const commonsModule = fakeModule(commonsCalls);
    const ragModule = fakeModule(ragCalls);
    ragModule._rac_rag_session_create_proto = () => 0;
    ragModule._rac_rag_query_proto = () => 0;

    setRunanywhereModule(commonsModule);
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
    setRunanywhereModule(fakeModule());
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
    ModelRegistryAdapter.setDefaultModule({
      _rac_get_model_registry: () => 1,
      _rac_model_registry_refresh_proto: () => 0,
    });
    expect(ModelRegistryAdapter.tryDefault()).not.toBeNull();
    ModelRegistryAdapter.clearDefaultModule();
    expect(ModelRegistryAdapter.tryDefault()).toBeNull();
  });
});
