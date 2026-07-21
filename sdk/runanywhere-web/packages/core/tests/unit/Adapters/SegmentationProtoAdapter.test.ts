import { afterEach, describe, expect, it, vi } from 'vitest';
import { CurrentModelResult, ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  SegmentationPixelFormat,
  SegmentationRequest,
  SegmentationResult,
  type SegmentationRequest as ProtoSegmentationRequest,
} from '@runanywhere/proto-ts/segmentation';
import { SegmentationProtoAdapter } from '../../../src/Adapters/SegmentationProtoAdapter';
import type { ModalityProtoModule } from '../../../src/Adapters/ProtoAdapterTypes';
import { ModalityProtoAdapter } from '../../../src/Adapters/ModalityProtoAdapter';
import { segment } from '../../../src/Public/Extensions/RunAnywhere+Segmentation';
import { WebModelLifecycle } from '../../../src/Public/Extensions/RunAnywhere+ModelLifecycle';
import { RunAnywhere } from '../../../src/Public/RunAnywhere';

describe('Segmentation lifecycle bridge and public validation', () => {
  afterEach(() => {
    ModalityProtoAdapter.clearDefaultModule();
    vi.restoreAllMocks();
  });

  it('encodes the request and decodes the lifecycle-owned result', async () => {
    const harness = fakeSegmentationModule();
    const adapter = new SegmentationProtoAdapter(harness.module);
    const request = validRequest();

    expect(adapter.supportsLifecycleProtoSegmentation()).toBe(true);
    await expect(adapter.segmentLifecycle(request)).resolves.toMatchObject({
      width: 2,
      height: 1,
      modelId: 'segformer-b0',
      classSummaries: [{ classId: 7, pixelCount: 2 }],
    });
    expect(harness.requests).toEqual([request]);
    expect(harness.calls).toBe(1);
    expect(harness.ccallCalls).toEqual([{
      functionName: 'rac_segmentation_segment_lifecycle_proto',
      returnType: 'number',
      argumentTypes: ['number', 'number', 'number'],
      argumentCount: 3,
      async: true,
    }]);
  });

  it('runs the already-loaded segmentation model through the capability slot', async () => {
    const harness = fakeSegmentationModule();
    ModalityProtoAdapter.registerModuleCapabilities(['segmentation'], harness.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
    const servicesReady = vi.spyOn(RunAnywhere, 'ensureServicesReady').mockResolvedValue();
    vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
      CurrentModelResult.create({
        found: true,
        modelId: 'segformer-b0',
        category: ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
      }),
    );

    const result = await RunAnywhere.segment(validRequest());

    expect(servicesReady).toHaveBeenCalledOnce();
    expect(result.classMaskU16Le).toEqual(new Uint8Array([7, 0, 7, 0]));
    expect(result.diagnosticRgba).toHaveLength(8);
    expect(harness.calls).toBe(1);
  });

  it('rejects malformed image bytes before entering WASM', async () => {
    const harness = fakeSegmentationModule();
    ModalityProtoAdapter.registerModuleCapabilities(['segmentation'], harness.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);

    await expect(segment(SegmentationRequest.create({
      image: {
        data: new Uint8Array(5),
        width: 2,
        height: 1,
        pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
      },
    }))).rejects.toMatchObject({
      fieldPath: 'SegmentationRequest.image.data',
    });
    expect(harness.calls).toBe(0);
  });

  it('requires a model already loaded in the semantic-segmentation category', async () => {
    const harness = fakeSegmentationModule();
    ModalityProtoAdapter.registerModuleCapabilities(['segmentation'], harness.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
    vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
      CurrentModelResult.create({ found: false }),
    );

    await expect(segment(validRequest())).rejects.toMatchObject({ cAbiCode: -116 });
    expect(harness.calls).toBe(0);
  });
});

interface FakeSegmentationHarness {
  module: ModalityProtoModule;
  requests: ProtoSegmentationRequest[];
  ccallCalls: Array<{
    functionName: string;
    returnType: string | null;
    argumentTypes: string[];
    argumentCount: number;
    async: boolean;
  }>;
  readonly calls: number;
}

function validRequest(): ProtoSegmentationRequest {
  return SegmentationRequest.create({
    image: {
      data: new Uint8Array([1, 2, 3, 4, 5, 6]),
      width: 2,
      height: 1,
      pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
    },
    options: { includeDiagnosticRgba: true },
  });
}

function fakeSegmentationModule(): FakeSegmentationHarness {
  const memory = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(memory);
  const heap32 = new Int32Array(memory);
  const heapU32 = new Uint32Array(memory);
  const requests: ProtoSegmentationRequest[] = [];
  const ccallCalls: FakeSegmentationHarness['ccallCalls'] = [];
  let nextAllocation = 1_024;
  let calls = 0;

  const allocate = (size: number): number => {
    const pointer = nextAllocation;
    nextAllocation += (Math.max(size, 1) + 7) & ~7;
    if (nextAllocation >= memory.byteLength) {
      throw new Error('fake segmentation WASM heap exhausted');
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
      if (functionName !== 'rac_segmentation_segment_lifecycle_proto') {
        throw new Error(`unexpected ccall: ${functionName}`);
      }
      return module._rac_segmentation_segment_lifecycle_proto!(
        Number(arguments_[0]),
        Number(arguments_[1]),
        Number(arguments_[2]),
      );
    },
    _rac_segmentation_segment_lifecycle_proto: (
      requestPointer,
      requestSize,
      outResult,
    ) => {
      calls += 1;
      const request = SegmentationRequest.decode(
        heapU8.slice(requestPointer, requestPointer + requestSize),
      );
      requests.push(request);
      writeResult(
        outResult,
        SegmentationResult.encode(SegmentationResult.create({
          width: 2,
          height: 1,
          classMaskU16Le: new Uint8Array([7, 0, 7, 0]),
          diagnosticRgba: new Uint8Array([1, 2, 3, 255, 1, 2, 3, 255]),
          classSummaries: [{ classId: 7, pixelCount: 2, fraction: 1, label: 'road' }],
          processingTimeMs: 2,
          modelId: 'segformer-b0',
        })).finish(),
      );
      return 0;
    },
  };

  return {
    module,
    requests,
    ccallCalls,
    get calls() {
      return calls;
    },
  };
}
