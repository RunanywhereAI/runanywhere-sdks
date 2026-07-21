import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  CurrentModelRequest,
  CurrentModelResult,
  InferenceFramework,
  ModelCategory,
  ModelInfo,
  ModelUnloadRequest,
  ModelUnloadResult,
  type ModelInfo as ProtoModelInfo,
  type CurrentModelRequest as ProtoCurrentModelRequest,
  type ModelUnloadRequest as ProtoModelUnloadRequest,
} from '@runanywhere/proto-ts/model_types';
import { ModelRegistry } from '../../../../src/Public/Extensions/RunAnywhere+ModelRegistry';
import { WebModelLifecycle } from '../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle';
import { Embeddings } from '../../../../src/Public/Extensions/RunAnywhere+Embeddings';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';

interface LoadedModelSeed {
  id: string;
  category: ModelCategory;
}

interface FakeLifecycleOptions {
  throwOnUnload?: boolean;
  throwOnReset?: boolean;
}

interface FakeLifecycleRuntime {
  module: EmscriptenRunanywhereModule;
  unloadRequests: ProtoModelUnloadRequest[];
  loadedModelIds(): string[];
  resetCalls(): number;
}

afterEach(() => {
  clearRunanywhereModule();
  vi.restoreAllMocks();
});

describe('WebModelLifecycle multi-WASM routing', () => {
  it('routes framework-scoped current-model queries to the owning WASM', () => {
    const llama = fakeLifecycleRuntime([
      { id: 'llama-embed', category: ModelCategory.MODEL_CATEGORY_EMBEDDING },
    ]);
    const onnx = fakeLifecycleRuntime([
      { id: 'onnx-embed', category: ModelCategory.MODEL_CATEGORY_EMBEDDING },
    ]);
    registerBackends(llama.module, onnx.module);

    expect(WebModelLifecycle.currentModel({
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      includeModelMetadata: false,
    })?.modelId).toBe('llama-embed');
    expect(WebModelLifecycle.currentModel({
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
      includeModelMetadata: false,
    })?.modelId).toBe('onnx-embed');
  });

  it('routes model-id unloads to the framework owner while sibling models stay loaded', async () => {
    const llama = fakeLifecycleRuntime([
      { id: 'llama-chat', category: ModelCategory.MODEL_CATEGORY_LANGUAGE },
    ]);
    const onnx = fakeLifecycleRuntime([
      { id: 'sherpa-stt', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION },
    ]);
    registerBackends(llama.module, onnx.module);
    installRegistrySnapshots([
      modelSnapshot(
        'llama-chat',
        ModelCategory.MODEL_CATEGORY_LANGUAGE,
        InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      ),
      modelSnapshot(
        'sherpa-stt',
        ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
      ),
    ]);

    await expect(WebModelLifecycle.unloadModelAsync({
      modelId: 'llama-chat',
      unloadAll: false,
    })).resolves.toMatchObject({
      success: true,
      unloadedModelIds: ['llama-chat'],
    });

    expect(llama.unloadRequests).toHaveLength(1);
    expect(onnx.unloadRequests).toHaveLength(0);
    expect(llama.loadedModelIds()).toEqual([]);
    expect(onnx.loadedModelIds()).toEqual(['sherpa-stt']);

    await expect(WebModelLifecycle.unloadModelAsync({
      modelId: 'sherpa-stt',
      unloadAll: false,
    })).resolves.toMatchObject({
      success: true,
      unloadedModelIds: ['sherpa-stt'],
    });
    expect(onnx.unloadRequests).toHaveLength(1);
    expect(onnx.loadedModelIds()).toEqual([]);
  });

  it('fans an unscoped unload-all across modules and returns one deterministic result', async () => {
    const llama = fakeLifecycleRuntime([
      { id: 'z-llama', category: ModelCategory.MODEL_CATEGORY_LANGUAGE },
    ]);
    const onnx = fakeLifecycleRuntime([
      { id: 'a-stt', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION },
      { id: 'm-tts', category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS },
    ]);
    // Reverse registration demonstrates that aggregation does not expose
    // backend registration order through the public result.
    registerBackends(llama.module, onnx.module, true);
    vi.spyOn(ModelRegistry, 'getModel').mockReturnValue(null);

    const result = await WebModelLifecycle.unloadModelAsync({
      modelId: '',
      unloadAll: true,
    });

    expect(result).toEqual({
      success: true,
      unloadedModelIds: ['a-stt', 'm-tts', 'z-llama'],
      errorMessage: '',
      unloadedAtUnixMs: 1,
      warnings: [],
    });
    expect(llama.unloadRequests).toHaveLength(1);
    expect(onnx.unloadRequests).toHaveLength(1);
    expect(llama.loadedModelIds()).toEqual([]);
    expect(onnx.loadedModelIds()).toEqual([]);
  });

  it('unloads embeddings across modules without tearing down other modalities', async () => {
    const llama = fakeLifecycleRuntime([
      { id: 'llama-embed', category: ModelCategory.MODEL_CATEGORY_EMBEDDING },
      { id: 'llama-chat', category: ModelCategory.MODEL_CATEGORY_LANGUAGE },
    ]);
    const onnx = fakeLifecycleRuntime([
      { id: 'onnx-embed', category: ModelCategory.MODEL_CATEGORY_EMBEDDING },
      { id: 'sherpa-stt', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION },
    ]);
    registerBackends(llama.module, onnx.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);

    await expect(Embeddings.unload()).resolves.toBeUndefined();

    expect(llama.unloadRequests).toHaveLength(1);
    expect(onnx.unloadRequests).toHaveLength(1);
    expect(llama.unloadRequests[0]).toMatchObject({
      modelId: '',
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      unloadAll: false,
    });
    expect(onnx.unloadRequests[0]).toMatchObject({
      modelId: '',
      category: ModelCategory.MODEL_CATEGORY_EMBEDDING,
      unloadAll: false,
    });
    expect(llama.loadedModelIds()).toEqual(['llama-chat']);
    expect(onnx.loadedModelIds()).toEqual(['sherpa-stt']);
  });

  it('fans unknown-model unloads and reset across every initialized module', () => {
    const llama = fakeLifecycleRuntime([
      { id: 'llama-chat', category: ModelCategory.MODEL_CATEGORY_LANGUAGE },
    ]);
    const onnx = fakeLifecycleRuntime([
      { id: 'sherpa-stt', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION },
    ]);
    registerBackends(llama.module, onnx.module);
    vi.spyOn(ModelRegistry, 'getModel').mockReturnValue(null);

    const missing = WebModelLifecycle.unloadModel({
      modelId: 'not-registered',
      unloadAll: false,
    });
    expect(missing).toMatchObject({ success: false, unloadedModelIds: [] });
    expect(llama.unloadRequests).toHaveLength(1);
    expect(onnx.unloadRequests).toHaveLength(1);

    expect(WebModelLifecycle.reset()).toBe(true);
    expect(llama.resetCalls()).toBe(1);
    expect(onnx.resetCalls()).toBe(1);
    expect(llama.loadedModelIds()).toEqual([]);
    expect(onnx.loadedModelIds()).toEqual([]);
  });

  it('continues fan-out cleanup after one module throws', () => {
    const llama = fakeLifecycleRuntime(
      [{ id: 'llama-chat', category: ModelCategory.MODEL_CATEGORY_LANGUAGE }],
      { throwOnUnload: true, throwOnReset: true },
    );
    const onnx = fakeLifecycleRuntime([
      { id: 'sherpa-stt', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION },
    ]);
    registerBackends(llama.module, onnx.module);
    vi.spyOn(ModelRegistry, 'getModel').mockReturnValue(null);

    expect(() => WebModelLifecycle.unloadAllModels()).toThrow('forced unload failure');
    expect(onnx.unloadRequests).toHaveLength(1);
    expect(onnx.loadedModelIds()).toEqual([]);

    expect(WebModelLifecycle.reset()).toBe(false);
    expect(llama.resetCalls()).toBe(1);
    expect(onnx.resetCalls()).toBe(1);
  });
});

function registerBackends(
  llama: EmscriptenRunanywhereModule,
  onnx: EmscriptenRunanywhereModule,
  reverse = false,
): void {
  const registrations = reverse
    ? [
        { capabilities: ['voice-agent'] as const, module: onnx, frameworks: ['onnx', 'sherpa'] },
        { capabilities: ['tool-calling'] as const, module: llama, frameworks: ['llamacpp'] },
      ]
    : [
        { capabilities: ['tool-calling'] as const, module: llama, frameworks: ['llamacpp'] },
        { capabilities: ['voice-agent'] as const, module: onnx, frameworks: ['onnx', 'sherpa'] },
      ];
  for (const registration of registrations) {
    registerWasmModule(
      registration.capabilities,
      registration.module,
      registration.frameworks,
    );
  }
}

function installRegistrySnapshots(models: readonly ProtoModelInfo[]): void {
  const byId = new Map(models.map((model) => [model.id, model]));
  vi.spyOn(ModelRegistry, 'getModel').mockImplementation((modelId) => byId.get(modelId) ?? null);
}

function modelSnapshot(
  id: string,
  category: ModelCategory,
  framework: InferenceFramework,
): ProtoModelInfo {
  return ModelInfo.create({ id, name: id, category, framework });
}

function fakeLifecycleRuntime(
  initialModels: readonly LoadedModelSeed[],
  options: FakeLifecycleOptions = {},
): FakeLifecycleRuntime {
  const memory = new ArrayBuffer(1024 * 1024);
  const heapU8 = new Uint8Array(memory);
  const heap32 = new Int32Array(memory);
  const heapU32 = new Uint32Array(memory);
  const loaded = new Map(initialModels.map((model) => [model.id, model.category]));
  const unloadRequests: ProtoModelUnloadRequest[] = [];
  let nextPointer = 64;
  let resetCount = 0;

  const allocate = (size: number): number => {
    const pointer = nextPointer;
    nextPointer += (Math.max(size, 1) + 7) & ~7;
    if (nextPointer >= memory.byteLength) throw new Error('fake WASM heap exhausted');
    return pointer;
  };

  const module: EmscriptenRunanywhereModule = {
    HEAPU8: heapU8,
    HEAP32: heap32,
    HEAPU32: heapU32,
    addFunction: () => 1,
    removeFunction: () => undefined,
    _malloc: allocate,
    _free: () => undefined,
    UTF8ToString: (pointer) => {
      let end = pointer;
      while (heapU8[end] !== 0) end += 1;
      return new TextDecoder().decode(heapU8.subarray(pointer, end));
    },
    stringToUTF8: (value, pointer, maxBytesToWrite) => {
      const bytes = new TextEncoder().encode(value);
      const written = Math.min(bytes.length, Math.max(0, maxBytesToWrite - 1));
      heapU8.set(bytes.subarray(0, written), pointer);
      heapU8[pointer + written] = 0;
      return written;
    },
    lengthBytesUTF8: (value) => new TextEncoder().encode(value).length,
    getValue: (pointer) => heap32[pointer >>> 2] ?? 0,
    setValue: (pointer, value) => {
      heap32[pointer >>> 2] = value;
    },
    _rac_voice_agent_set_proto_callback: () => 0,
    _rac_llm_set_stream_proto_callback: () => 0,
    _rac_llm_unset_stream_proto_callback: () => 0,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_proto_buffer_init: (bufferPointer) => {
      heapU32.fill(0, bufferPointer >>> 2, (bufferPointer >>> 2) + 4);
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_model_lifecycle_current_model_proto: (requestPointer, requestSize, outResult) => {
      const request: ProtoCurrentModelRequest = CurrentModelRequest.decode(
        heapU8.slice(requestPointer, requestPointer + requestSize),
      );
      const match = Array.from(loaded).find(([, category]) => (
        request.category === undefined || request.category === category
      ));
      const resultBytes = CurrentModelResult.encode(CurrentModelResult.create({
        modelId: match?.[0] ?? '',
        found: Boolean(match),
        errorMessage: '',
        category: match?.[1] ?? ModelCategory.MODEL_CATEGORY_UNSPECIFIED,
        framework: request.framework ?? InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
        resolvedPath: '',
        resolvedArtifacts: [],
      })).finish();
      const dataPointer = allocate(resultBytes.length);
      heapU8.set(resultBytes, dataPointer);
      heapU32[outResult >>> 2] = dataPointer;
      heapU32[(outResult + 4) >>> 2] = resultBytes.length;
      heap32[(outResult + 8) >>> 2] = 0;
      heapU32[(outResult + 12) >>> 2] = 0;
      return 0;
    },
    _rac_model_lifecycle_unload_proto: (requestPointer, requestSize, outResult) => {
      if (options.throwOnUnload) throw new Error('forced unload failure');
      const request = ModelUnloadRequest.decode(
        heapU8.slice(requestPointer, requestPointer + requestSize),
      );
      unloadRequests.push(request);
      const unloadedModelIds: string[] = [];
      for (const [modelId, category] of loaded) {
        if (
          request.unloadAll
          || (request.modelId.length > 0 && request.modelId === modelId)
          || (request.category !== undefined && request.category === category)
        ) {
          loaded.delete(modelId);
          unloadedModelIds.push(modelId);
        }
      }
      unloadedModelIds.sort((left, right) => left.localeCompare(right));
      const resultBytes = ModelUnloadResult.encode(ModelUnloadResult.create({
        success: unloadedModelIds.length > 0,
        unloadedModelIds,
        errorMessage: unloadedModelIds.length > 0
          ? ''
          : 'no loaded model matched unload request',
        unloadedAtUnixMs: 1,
        warnings: [],
      })).finish();
      const dataPointer = allocate(resultBytes.length);
      heapU8.set(resultBytes, dataPointer);
      heapU32[outResult >>> 2] = dataPointer;
      heapU32[(outResult + 4) >>> 2] = resultBytes.length;
      heap32[(outResult + 8) >>> 2] = 0;
      heapU32[(outResult + 12) >>> 2] = 0;
      return 0;
    },
    _rac_model_lifecycle_reset: () => {
      resetCount += 1;
      if (options.throwOnReset) throw new Error('forced reset failure');
      loaded.clear();
    },
  };

  return {
    module,
    unloadRequests,
    loadedModelIds: () => Array.from(loaded.keys()).sort((left, right) => left.localeCompare(right)),
    resetCalls: () => resetCount,
  };
}
