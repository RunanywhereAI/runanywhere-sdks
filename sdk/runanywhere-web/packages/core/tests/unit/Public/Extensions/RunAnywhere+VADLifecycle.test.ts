import { afterEach, describe, expect, it, vi } from 'vitest';
import { CurrentModelResult } from '@runanywhere/proto-ts/model_types';
import {
  VADAudioEncoding,
  VADConfiguration,
  VADProcessRequest,
  VADResult,
  VADServiceState,
} from '@runanywhere/proto-ts/vad_options';
import type { ModalityProtoModule } from '../../../../src/Adapters/ProtoAdapterTypes';
import { VAD } from '../../../../src/Public/Extensions/RunAnywhere+VAD';
import { WebModelLifecycle } from '../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { installCurrentModelRegistryExports } from '../../helpers/CurrentModelRegistryModule.js';

interface LifecycleCounters {
  componentCreates: number;
  componentLoads: number;
  componentDestroys: number;
  lifecycleConfigures: number;
  lifecycleStarts: number;
  lifecycleProcesses: number;
  lifecycleStops: number;
  lifecycleResets: number;
  calls: string[];
  configurations: VADConfiguration[];
  requests: VADProcessRequest[];
}

type FakeModule = EmscriptenRunanywhereModule & ModalityProtoModule;

function installLoadedLifecycleModel(): void {
  vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
  vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
    CurrentModelResult.fromPartial({
      found: true,
      modelId: 'silero-vad',
      resolvedPath: '/models/silero_vad.onnx',
    }),
  );
}

function fakeLifecycleModule(): { module: FakeModule; counters: LifecycleCounters } {
  const heap = new ArrayBuffer(512 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  const heap32 = new Int32Array(heap);
  let nextAllocation = 1_024;
  let nextResult = 256 * 1024;

  const counters: LifecycleCounters = {
    componentCreates: 0,
    componentLoads: 0,
    componentDestroys: 0,
    lifecycleConfigures: 0,
    lifecycleStarts: 0,
    lifecycleProcesses: 0,
    lifecycleStops: 0,
    lifecycleResets: 0,
    calls: [],
    configurations: [],
    requests: [],
  };

  const writeResult = (outResult: number, bytes: Uint8Array): number => {
    const dataPtr = nextResult;
    nextResult += Math.max(8, (bytes.length + 7) & ~7);
    heapU8.set(bytes, dataPtr);
    heapU32[outResult >>> 2] = dataPtr;
    heapU32[(outResult >>> 2) + 1] = bytes.length;
    heap32[(outResult >>> 2) + 2] = 0;
    heapU32[(outResult >>> 2) + 3] = 0;
    return 0;
  };

  const readyState = (): Uint8Array => VADServiceState.encode(
    VADServiceState.fromPartial({
      isReady: true,
      currentModel: 'silero-vad',
      sampleRate: 16_000,
      frameLengthMs: 32,
    }),
  ).finish();

  const partial = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc(size: number): number {
      const ptr = nextAllocation;
      nextAllocation += Math.max(8, (size + 7) & ~7);
      return ptr;
    },
    _free: () => undefined,
    addFunction: () => 1,
    removeFunction: () => undefined,
    UTF8ToString: () => '',
    stringToUTF8: () => 0,
    lengthBytesUTF8: (value: string) => new TextEncoder().encode(value).length,
    _rac_proto_buffer_init(outResult: number): void {
      heapU32.fill(0, outResult >>> 2, (outResult >>> 2) + 4);
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_voice_agent_set_proto_callback: () => 0,
    _rac_llm_set_stream_proto_callback: () => 0,
    _rac_llm_unset_stream_proto_callback: () => 0,
    _rac_vad_component_create: () => {
      counters.componentCreates += 1;
      return 0;
    },
    _rac_vad_component_load_model: () => {
      counters.componentLoads += 1;
      return 0;
    },
    _rac_vad_component_destroy: () => {
      counters.componentDestroys += 1;
    },
    _rac_vad_configure_lifecycle_proto(
      requestPtr: number,
      requestSize: number,
      outResult: number,
    ): number {
      counters.lifecycleConfigures += 1;
      counters.calls.push('configure');
      counters.configurations.push(
        VADConfiguration.decode(heapU8.slice(requestPtr, requestPtr + requestSize)),
      );
      return writeResult(outResult, readyState());
    },
    _rac_vad_start_lifecycle_proto(outResult: number): number {
      counters.lifecycleStarts += 1;
      counters.calls.push('start');
      return writeResult(outResult, readyState());
    },
    _rac_vad_process_lifecycle_proto(
      requestPtr: number,
      requestSize: number,
      outResult: number,
    ): number {
      counters.lifecycleProcesses += 1;
      counters.calls.push('process');
      const request = VADProcessRequest.decode(
        heapU8.slice(requestPtr, requestPtr + requestSize),
      );
      counters.requests.push(request);
      return writeResult(
        outResult,
        VADResult.encode(VADResult.fromPartial({
          isSpeech: counters.lifecycleProcesses % 2 === 1,
          confidence: 0.9,
          durationMs: 32,
        })).finish(),
      );
    },
    _rac_vad_stop_lifecycle_proto(outResult: number): number {
      counters.lifecycleStops += 1;
      counters.calls.push('stop');
      return writeResult(outResult, readyState());
    },
    _rac_vad_reset_lifecycle_proto(outResult: number): number {
      counters.lifecycleResets += 1;
      counters.calls.push('reset');
      return writeResult(outResult, readyState());
    },
  };

  const module = installCurrentModelRegistryExports(partial) as unknown as FakeModule;
  return { module, counters };
}

async function* chunks(count: number): AsyncIterable<Float32Array> {
  for (let index = 0; index < count; index += 1) {
    yield new Float32Array([index / 10, -0.25, 0.5]);
  }
}

afterEach(() => {
  clearRunanywhereModule();
  vi.restoreAllMocks();
});

describe('canonical lifecycle VAD facade', () => {
  it('processes one-shot audio without creating or destroying a second detector', async () => {
    installLoadedLifecycleModel();
    const { module, counters } = fakeLifecycleModule();
    registerWasmModule(['vad'], module, ['onnx', 'sherpa']);

    const samples = new Float32Array([0.25, -0.5, 1]);
    const result = await VAD.detectVoiceAuto(samples, {
      threshold: 0.2,
      config: { sampleRate: 16_000 },
    });

    expect(result.isSpeech).toBe(true);
    expect(counters.calls).toEqual(['configure', 'process']);
    expect(counters).toMatchObject({
      componentCreates: 0,
      componentLoads: 0,
      componentDestroys: 0,
      lifecycleConfigures: 1,
      lifecycleProcesses: 1,
    });
    expect(counters.configurations[0]?.sampleRate).toBe(16_000);
    expect(counters.configurations[0]?.threshold).toBeCloseTo(0.2);
    const request = counters.requests[0];
    expect(request?.audio).toMatchObject({
      encoding: VADAudioEncoding.VAD_AUDIO_ENCODING_PCM_F32_LE,
      sampleRate: 16_000,
      channels: 1,
    });
    expect(request?.options?.threshold).toBe(0);
    const audioBytes = request?.audio?.audioData;
    expect(audioBytes).toBeDefined();
    const view = new DataView(
      audioBytes!.buffer,
      audioBytes!.byteOffset,
      audioBytes!.byteLength,
    );
    expect(view.getFloat32(0, true)).toBeCloseTo(samples[0]!);
    expect(view.getFloat32(4, true)).toBeCloseTo(samples[1]!);
  });

  it('uses one canonical service for every stream frame and pairs teardown', async () => {
    installLoadedLifecycleModel();
    const { module, counters } = fakeLifecycleModule();
    registerWasmModule(['vad'], module, ['onnx', 'sherpa']);

    const results: VADResult[] = [];
    for await (const result of VAD.streamVoiceAuto(chunks(3), { threshold: 0.15 })) {
      results.push(result);
    }

    expect(results.map((result) => result.isSpeech)).toEqual([true, false, true]);
    expect(counters.calls).toEqual([
      'configure',
      'start',
      'process',
      'process',
      'process',
      'stop',
      'reset',
    ]);
    expect(counters.requests).toHaveLength(3);
    expect(counters.requests.every((request) => request.options?.threshold === 0)).toBe(true);
    expect(counters).toMatchObject({
      componentCreates: 0,
      componentLoads: 0,
      componentDestroys: 0,
      lifecycleStarts: 1,
      lifecycleStops: 1,
      lifecycleResets: 1,
    });
  });

  it('stops and resets the lifecycle service when a consumer exits early', async () => {
    installLoadedLifecycleModel();
    const { module, counters } = fakeLifecycleModule();
    registerWasmModule(['vad'], module, ['onnx', 'sherpa']);

    for await (const _result of VAD.streamVoiceAuto(chunks(3))) {
      break;
    }

    expect(counters.calls).toEqual(['configure', 'start', 'process', 'stop', 'reset']);
    expect(counters.lifecycleProcesses).toBe(1);
    expect(counters.componentDestroys).toBe(0);
  });
});
