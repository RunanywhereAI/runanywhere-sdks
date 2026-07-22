import { afterEach, describe, expect, it } from 'vitest';
import {
  EmbeddingsRequest,
  EmbeddingsResult,
  type EmbeddingsRequest as ProtoEmbeddingsRequest,
} from '@runanywhere/proto-ts/embeddings_options';
import { InferenceFramework } from '@runanywhere/proto-ts/model_types';
import { EmbeddingsProtoAdapter } from '../../../src/Adapters/EmbeddingsProtoAdapter';
import type { ModalityProtoModule } from '../../../src/Adapters/ProtoAdapterTypes';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../src/runtime/EmscriptenModule.js';

describe('EmbeddingsProtoAdapter lifecycle routing', () => {
  afterEach(() => {
    clearRunanywhereModule();
  });

  it('uses the handle-less lifecycle ABI instead of treating zero as a handle', async () => {
    const harness = fakeEmbeddingsModule();
    const adapter = new EmbeddingsProtoAdapter(harness.module);
    const request = EmbeddingsRequest.create({
      texts: ['Project Meridian'],
      requestId: 'embed-request',
      modelId: 'all-minilm-l6-v2',
      metadata: {},
    });

    expect(adapter.supportsProtoEmbeddings()).toBe(true);
    expect(adapter.supportsLifecycleProtoEmbeddings()).toBe(true);
    await expect(adapter.embedBatchLifecycle(request)).resolves.toMatchObject({
      dimension: 2,
      modelId: 'all-minilm-l6-v2',
      requestId: 'embed-request',
      vectors: [{
        values: [0.25, 0.75],
        text: 'Project Meridian',
        dimension: 2,
        inputIndex: 0,
      }],
    });
    expect(harness.lifecycleCalls).toBe(1);
    expect(harness.handleCalls).toBe(0);
    expect(harness.requests).toEqual([request]);
    expect(harness.ccallCalls).toEqual([{
      functionName: 'rac_embeddings_embed_batch_lifecycle_proto',
      returnType: 'number',
      argumentTypes: ['number', 'number', 'number'],
      argumentCount: 3,
      async: true,
    }]);
  });

  it('routes llama.cpp and ONNX embeddings by model framework', async () => {
    const llama = fakeEmbeddingsModule();
    const onnx = fakeEmbeddingsModule();
    registerWasmModule(
      [],
      llama.module as unknown as EmscriptenRunanywhereModule,
      ['llamacpp'],
    );
    registerWasmModule(
      [],
      onnx.module as unknown as EmscriptenRunanywhereModule,
      ['onnx'],
    );

    const llamaAdapter = EmbeddingsProtoAdapter.tryDefaultForFramework(
      InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    );
    const onnxAdapter = EmbeddingsProtoAdapter.tryDefaultForFramework(
      InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    );
    expect(llamaAdapter).not.toBeNull();
    expect(onnxAdapter).not.toBeNull();

    await llamaAdapter!.embedBatchLifecycle(EmbeddingsRequest.create({
      texts: ['NVIDIA embedding'],
      modelId: 'nemotron-3-embed-1b-q4_k_m',
      metadata: {},
    }));
    expect(llama.lifecycleCalls).toBe(1);
    expect(onnx.lifecycleCalls).toBe(0);

    await onnxAdapter!.embedBatchLifecycle(EmbeddingsRequest.create({
      texts: ['ONNX embedding'],
      modelId: 'all-minilm-l6-v2',
      metadata: {},
    }));
    expect(llama.lifecycleCalls).toBe(1);
    expect(onnx.lifecycleCalls).toBe(1);
  });
});

interface FakeEmbeddingsHarness {
  module: ModalityProtoModule;
  requests: ProtoEmbeddingsRequest[];
  ccallCalls: Array<{
    functionName: string;
    returnType: string | null;
    argumentTypes: string[];
    argumentCount: number;
    async: boolean;
  }>;
  readonly lifecycleCalls: number;
  readonly handleCalls: number;
}

function fakeEmbeddingsModule(): FakeEmbeddingsHarness {
  const heap = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heap32 = new Int32Array(heap);
  const heapU32 = new Uint32Array(heap);
  const requests: ProtoEmbeddingsRequest[] = [];
  const ccallCalls: FakeEmbeddingsHarness['ccallCalls'] = [];
  let nextAllocation = 1_024;
  let lifecycleCalls = 0;
  let handleCalls = 0;

  const allocate = (size: number): number => {
    const pointer = nextAllocation;
    nextAllocation += (Math.max(size, 1) + 7) & ~7;
    if (nextAllocation >= heap.byteLength) {
      throw new Error('fake embeddings WASM heap exhausted');
    }
    return pointer;
  };

  const writeResult = (outResult: number, bytes: Uint8Array): void => {
    const dataPointer = allocate(bytes.byteLength);
    heapU8.set(bytes, dataPointer);
    heapU32[outResult >>> 2] = dataPointer;
    heapU32[(outResult + 4) >>> 2] = bytes.byteLength;
    heap32[(outResult + 8) >>> 2] = 0;
    heapU32[(outResult + 12) >>> 2] = 0;
  };

  const module: ModalityProtoModule = {
    HEAPU8: heapU8,
    HEAP32: heap32,
    HEAPU32: heapU32,
    _malloc: allocate,
    _free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_proto_buffer_init: (bufferPointer: number) => {
      heapU32.fill(0, bufferPointer >>> 2, (bufferPointer >>> 2) + 4);
    },
    _rac_proto_buffer_free: () => undefined,
    ccall(functionName, returnType, argumentTypes, arguments_, options): unknown {
      ccallCalls.push({
        functionName,
        returnType,
        argumentTypes,
        argumentCount: arguments_.length,
        async: options?.async === true,
      });
      if (functionName !== 'rac_embeddings_embed_batch_lifecycle_proto') {
        throw new Error(`unexpected ccall: ${functionName}`);
      }
      return module._rac_embeddings_embed_batch_lifecycle_proto!(
        Number(arguments_[0]),
        Number(arguments_[1]),
        Number(arguments_[2]),
      );
    },
    _rac_embeddings_embed_batch_proto: () => {
      handleCalls += 1;
      return -1;
    },
    _rac_embeddings_embed_batch_lifecycle_proto: (
      requestPointer,
      requestSize,
      outResult,
    ) => {
      lifecycleCalls += 1;
      const request = EmbeddingsRequest.decode(
        heapU8.slice(requestPointer, requestPointer + requestSize),
      );
      requests.push(request);
      writeResult(
        outResult,
        EmbeddingsResult.encode(EmbeddingsResult.create({
          vectors: [{
            values: [0.25, 0.75],
            norm: Math.sqrt(0.625),
            text: request.texts[0],
            dimension: 2,
            inputIndex: 0,
            metadata: {},
          }],
          dimension: 2,
          processingTimeMs: 3,
          tokensUsed: 2,
          modelId: request.modelId,
          errorCode: 0,
          requestId: request.requestId,
        })).finish(),
      );
      return 0;
    },
  };

  return {
    module,
    requests,
    ccallCalls,
    get lifecycleCalls() {
      return lifecycleCalls;
    },
    get handleCalls() {
      return handleCalls;
    },
  };
}
