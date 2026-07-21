import { afterEach, describe, expect, it, vi } from 'vitest';
import { CurrentModelResult, ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  VocoderRequest as WireVocoderRequest,
  VocoderResult as WireVocoderResult,
  type VocoderRequest as ProtoVocoderRequest,
} from '@runanywhere/proto-ts/vocoder';
import { ModalityProtoAdapter } from '../../../src/Adapters/ModalityProtoAdapter';
import { VocoderProtoAdapter } from '../../../src/Adapters/VocoderProtoAdapter';
import type { ModalityProtoModule } from '../../../src/Adapters/ProtoAdapterTypes';
import { vocode, type VocoderRequest } from '../../../src/Public/Extensions/RunAnywhere+Vocoder';
import { WebModelLifecycle } from '../../../src/Public/Extensions/RunAnywhere+ModelLifecycle';
import { RunAnywhere } from '../../../src/Public/RunAnywhere';

describe('Vocoder lifecycle bridge and public validation', () => {
  afterEach(() => {
    ModalityProtoAdapter.clearDefaultModule();
    vi.restoreAllMocks();
  });

  it('encodes little-endian mels and decodes the lifecycle waveform', async () => {
    const harness = fakeVocoderModule();
    ModalityProtoAdapter.registerModuleCapabilities(['vocoder'], harness.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
    vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
      CurrentModelResult.create({
        found: true,
        modelId: 'bigvgan-v2-22khz',
        category: ModelCategory.MODEL_CATEGORY_VOCODER,
      }),
    );
    vi.spyOn(RunAnywhere, 'ensureServicesReady').mockResolvedValue();

    const request = validRequest();
    const result = await RunAnywhere.vocode(request);

    expect(harness.requests).toHaveLength(1);
    expect(harness.requests[0]).toMatchObject({
      batchSize: 1,
      melBinCount: 80,
      frameCount: 2,
    });
    expect(new DataView(
      harness.requests[0]!.melSpectrogramF32Le.buffer,
      harness.requests[0]!.melSpectrogramF32Le.byteOffset,
    ).getFloat32(4, true)).toBeCloseTo(-0.25);
    expect(result).toMatchObject({
      batchSize: 1,
      channelCount: 1,
      sampleCount: 512,
      sampleRateHz: 22_050,
      hopLength: 256,
      modelId: 'bigvgan-v2-22khz',
    });
    expect(result.samples).toBeInstanceOf(Float32Array);
    expect(result.samples).toHaveLength(512);
    expect(result.samples[0]).toBeCloseTo(0.25);
    expect(result.samples[511]).toBeCloseTo(-0.5);
    expect(harness.ccallCalls).toEqual([{
      functionName: 'rac_vocoder_vocode_lifecycle_proto',
      returnType: 'number',
      argumentTypes: ['number', 'number', 'number'],
      argumentCount: 3,
      async: true,
    }]);
  });

  it('rejects a malformed or non-finite mel tensor before entering WASM', async () => {
    const harness = fakeVocoderModule();
    ModalityProtoAdapter.registerModuleCapabilities(['vocoder'], harness.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);

    await expect(vocode({
      melSpectrogram: new Float32Array(159),
      batchSize: 1,
      melBinCount: 80,
      frameCount: 2,
    })).rejects.toMatchObject({ fieldPath: 'VocoderRequest.melSpectrogram' });

    const nonFinite = validRequest();
    nonFinite.melSpectrogram[7] = Number.NaN;
    await expect(vocode(nonFinite)).rejects.toMatchObject({
      fieldPath: 'VocoderRequest.melSpectrogram[7]',
    });

    const float32Overflow = validRequest();
    await expect(vocode({
      ...float32Overflow,
      melSpectrogram: [1e40, ...float32Overflow.melSpectrogram.slice(1)],
    })).rejects.toMatchObject({
      fieldPath: 'VocoderRequest.melSpectrogram[0]',
    });
    expect(harness.calls).toBe(0);
  });

  it('preserves a typed native status and message from a post-dispatch failure', async () => {
    const harness = fakeVocoderModule();
    ModalityProtoAdapter.registerModuleCapabilities(['vocoder'], harness.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
    vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
      CurrentModelResult.create({
        found: true,
        modelId: 'bigvgan-v2-22khz',
        category: ModelCategory.MODEL_CATEGORY_VOCODER,
      }),
    );
    vi.spyOn(RunAnywhere, 'ensureServicesReady').mockResolvedValue();
    harness.failNext(-252, 'backend returned an invalid vocoder result');

    await expect(RunAnywhere.vocode(validRequest())).rejects.toMatchObject({
      name: 'SDKException',
      cAbiCode: -252,
      message: 'backend returned an invalid vocoder result',
    });
    expect(harness.calls).toBe(1);
    expect(harness.requests).toHaveLength(1);
  });

  it('requires a lifecycle-owned vocoder model', async () => {
    const harness = fakeVocoderModule();
    ModalityProtoAdapter.registerModuleCapabilities(['vocoder'], harness.module);
    vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
    vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
      CurrentModelResult.create({ found: false }),
    );

    await expect(vocode(validRequest())).rejects.toMatchObject({ cAbiCode: -116 });
    expect(harness.calls).toBe(0);
  });

  it('exposes and checks the lifecycle proto export', () => {
    const harness = fakeVocoderModule();
    expect(new VocoderProtoAdapter(harness.module).supportsLifecycleProtoVocoder()).toBe(true);
  });
});

interface FakeVocoderHarness {
  module: ModalityProtoModule;
  requests: ProtoVocoderRequest[];
  ccallCalls: Array<{
    functionName: string;
    returnType: string | null;
    argumentTypes: string[];
    argumentCount: number;
    async: boolean;
  }>;
  readonly calls: number;
  failNext(status: number, message: string, returnCode?: number): void;
}

function validRequest(): VocoderRequest & { melSpectrogram: Float32Array } {
  const melSpectrogram = new Float32Array(160);
  melSpectrogram[0] = 0.5;
  melSpectrogram[1] = -0.25;
  return { melSpectrogram, batchSize: 1, melBinCount: 80, frameCount: 2 };
}

function encodeFloat32LE(values: Float32Array): Uint8Array {
  const bytes = new Uint8Array(values.length * 4);
  const view = new DataView(bytes.buffer);
  values.forEach((value, index) => view.setFloat32(index * 4, value, true));
  return bytes;
}

function fakeVocoderModule(): FakeVocoderHarness {
  const memory = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(memory);
  const heap32 = new Int32Array(memory);
  const heapU32 = new Uint32Array(memory);
  const requests: ProtoVocoderRequest[] = [];
  const ccallCalls: FakeVocoderHarness['ccallCalls'] = [];
  let nextAllocation = 1_024;
  let calls = 0;
  let nextFailure: { status: number; message: string; returnCode: number } | null = null;

  const allocate = (size: number): number => {
    const pointer = nextAllocation;
    nextAllocation += (Math.max(size, 1) + 7) & ~7;
    if (nextAllocation >= memory.byteLength) throw new Error('fake vocoder WASM heap exhausted');
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
  const writeFailure = (outResult: number, status: number, message: string): void => {
    const messageBytes = new TextEncoder().encode(message);
    const messagePointer = allocate(messageBytes.byteLength + 1);
    heapU8.set(messageBytes, messagePointer);
    heapU8[messagePointer + messageBytes.byteLength] = 0;
    heap32[(outResult + 8) >>> 2] = status;
    heapU32[(outResult + 12) >>> 2] = messagePointer;
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
    UTF8ToString: (pointer: number) => {
      let end = pointer;
      while (heapU8[end] !== 0) end += 1;
      return new TextDecoder().decode(heapU8.subarray(pointer, end));
    },
    ccall(functionName, returnType, argumentTypes, arguments_, options): unknown {
      ccallCalls.push({
        functionName,
        returnType,
        argumentTypes,
        argumentCount: arguments_.length,
        async: options?.async === true,
      });
      if (functionName !== 'rac_vocoder_vocode_lifecycle_proto') {
        throw new Error(`unexpected ccall: ${functionName}`);
      }
      return module._rac_vocoder_vocode_lifecycle_proto!(
        Number(arguments_[0]),
        Number(arguments_[1]),
        Number(arguments_[2]),
      );
    },
    _rac_vocoder_vocode_lifecycle_proto: (requestPointer, requestSize, outResult) => {
      calls += 1;
      requests.push(WireVocoderRequest.decode(
        heapU8.slice(requestPointer, requestPointer + requestSize),
      ));
      if (nextFailure) {
        const failure = nextFailure;
        nextFailure = null;
        writeFailure(outResult, failure.status, failure.message);
        return failure.returnCode;
      }
      const samples = new Float32Array(512);
      samples[0] = 0.25;
      samples[511] = -0.5;
      writeResult(outResult, WireVocoderResult.encode(WireVocoderResult.create({
        samplesF32Le: encodeFloat32LE(samples),
        batchSize: 1,
        channelCount: 1,
        sampleCount: 512,
        sampleRateHz: 22_050,
        hopLength: 256,
        processingTimeMs: 7,
        modelId: 'bigvgan-v2-22khz',
      })).finish());
      return 0;
    },
  };

  return {
    module,
    requests,
    ccallCalls,
    get calls() { return calls; },
    failNext(status, message, returnCode = status) {
      nextFailure = { status, message, returnCode };
    },
  };
}
