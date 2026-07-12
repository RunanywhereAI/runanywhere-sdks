import { afterEach, describe, expect, it } from 'vitest';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import {
  STTAudioEncoding,
  STTOutput,
  STTPartialResult,
  STTStreamEvent,
  STTStreamEventKind,
  STTTranscriptionRequest,
  type STTTranscriptionRequest as ProtoSTTTranscriptionRequest,
} from '@runanywhere/proto-ts/stt_options';
import type { ModalityProtoModule } from '../../../../src/Adapters/ProtoAdapterTypes';
import { RunAnywhere } from '../../../../src/Public/RunAnywhere';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { installCurrentModelRegistryExports } from '../../helpers/CurrentModelRegistryModule.js';

interface STTLifecycleCounters {
  lifecycleBatchCalls: number;
  lifecycleStreamCalls: number;
  componentCreates: number;
  componentLoads: number;
  componentTranscribes: number;
  componentStreamTranscribes: number;
  componentDestroys: number;
}

interface FakeSTTModule extends ModalityProtoModule {
  _rac_backend_onnx_register(): number;
  _rac_backend_sherpa_register(): number;
  _rac_stt_component_create(outHandlePtr: number): number;
  _rac_stt_component_load_model(
    handle: number,
    modelPathPtr: number,
    modelIdPtr: number,
    modelNamePtr: number,
  ): number;
  _rac_stt_component_destroy(handle: number): void;
}

interface FakeSTTHarness {
  module: FakeSTTModule;
  counters: STTLifecycleCounters;
  requests: ProtoSTTTranscriptionRequest[];
  currentLifecycleModelId(): string | null;
}

afterEach(() => {
  clearRunanywhereModule();
});

describe('lifecycle-owned Web STT', () => {
  it('batch transcription never replaces or destroys the lifecycle model', async () => {
    const harness = fakeSTTModule();
    install(harness.module);

    const result = await RunAnywhere.transcribe(new Float32Array([0, 0.5, -0.5]));

    expect(result.text).toBe('lifecycle transcript');
    expect(harness.currentLifecycleModelId()).toBe('sherpa-lifecycle-stt');
    expect(harness.counters).toMatchObject({
      lifecycleBatchCalls: 1,
      componentCreates: 0,
      componentLoads: 0,
      componentTranscribes: 0,
      componentDestroys: 0,
    });
    expect(harness.requests).toHaveLength(1);
    expect(harness.requests[0]?.audio).toMatchObject({
      encoding: STTAudioEncoding.STT_AUDIO_ENCODING_PCM_S16_LE,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM_S16LE,
      sampleRate: 16_000,
      channels: 1,
      bitsPerSample: 16,
    });
    expect(Array.from(harness.requests[0]?.audio?.audioData ?? [])).toEqual([
      0, 0, 0, 64, 1, 192,
    ]);
  });

  it('streaming uses lifecycle envelopes without temporary component ownership', async () => {
    const harness = fakeSTTModule();
    install(harness.module);

    const partials: STTPartialResult[] = [];
    for await (const partial of RunAnywhere.transcribeStream(new Uint8Array([1, 2, 3, 4]))) {
      partials.push(partial);
    }

    expect(partials.map((partial) => [partial.text, partial.isFinal])).toEqual([
      ['life', false],
      ['lifecycle stream', true],
    ]);
    expect(harness.currentLifecycleModelId()).toBe('sherpa-lifecycle-stt');
    expect(harness.counters).toMatchObject({
      lifecycleStreamCalls: 1,
      componentCreates: 0,
      componentLoads: 0,
      componentStreamTranscribes: 0,
      componentDestroys: 0,
    });
  });

});

function install(module: FakeSTTModule): void {
  registerWasmModule(
    ['stt'],
    module as unknown as EmscriptenRunanywhereModule,
    ['onnx', 'sherpa'],
  );
}

function fakeSTTModule(): FakeSTTHarness {
  const heap = new ArrayBuffer(256 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heap32 = new Int32Array(heap);
  const heapU32 = new Uint32Array(heap);
  const callbacks = new Map<number, (...args: number[]) => number | void>();
  const requests: ProtoSTTTranscriptionRequest[] = [];
  const counters: STTLifecycleCounters = {
    lifecycleBatchCalls: 0,
    lifecycleStreamCalls: 0,
    componentCreates: 0,
    componentLoads: 0,
    componentTranscribes: 0,
    componentStreamTranscribes: 0,
    componentDestroys: 0,
  };
  let nextAllocation = 1_024;
  let nextCallback = 1;
  let currentLifecycleModelId: string | null = 'sherpa-lifecycle-stt';

  const allocate = (size: number): number => {
    const pointer = nextAllocation;
    nextAllocation += (Math.max(size, 1) + 7) & ~7;
    if (nextAllocation >= heap.byteLength) throw new Error('fake STT WASM heap exhausted');
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

  const emit = (callbackPtr: number, event: STTStreamEvent): void => {
    const bytes = STTStreamEvent.encode(event).finish();
    const pointer = allocate(bytes.byteLength);
    heapU8.set(bytes, pointer);
    const callback = callbacks.get(callbackPtr);
    if (!callback) throw new Error('missing fake STT stream callback');
    callback(pointer, bytes.byteLength, 0);
  };

  const module: FakeSTTModule = {
    HEAPU8: heapU8,
    HEAP32: heap32,
    HEAPU32: heapU32,
    _malloc: allocate,
    _free: () => undefined,
    addFunction(callback: (...args: number[]) => number | void, _signature: string): number {
      const pointer = nextCallback;
      nextCallback += 1;
      callbacks.set(pointer, callback);
      return pointer;
    },
    removeFunction(pointer: number): void {
      callbacks.delete(pointer);
    },
    UTF8ToString: () => '',
    stringToUTF8: () => 0,
    lengthBytesUTF8: (value: string) => new TextEncoder().encode(value).byteLength,
    getValue: (pointer: number) => heap32[pointer >>> 2] ?? 0,
    setValue: (pointer: number, value: number) => {
      heap32[pointer >>> 2] = value;
    },
    _rac_voice_agent_set_proto_callback: () => 0,
    _rac_llm_set_stream_proto_callback: () => 0,
    _rac_llm_unset_stream_proto_callback: () => 0,
    _rac_backend_onnx_register: () => 0,
    _rac_backend_sherpa_register: () => 0,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_proto_buffer_init: (bufferPointer: number) => {
      heapU32.fill(0, bufferPointer >>> 2, (bufferPointer >>> 2) + 4);
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_stt_transcribe_lifecycle_proto(requestPtr, requestSize, outResult): number {
      counters.lifecycleBatchCalls += 1;
      requests.push(STTTranscriptionRequest.decode(
        heapU8.slice(requestPtr, requestPtr + requestSize),
      ));
      writeResult(
        outResult,
        STTOutput.encode(STTOutput.create({ text: 'lifecycle transcript' })).finish(),
      );
      return 0;
    },
    _rac_stt_transcribe_stream_lifecycle_proto(
      requestPtr,
      requestSize,
      callbackPtr,
    ): number {
      counters.lifecycleStreamCalls += 1;
      const request = STTTranscriptionRequest.decode(
        heapU8.slice(requestPtr, requestPtr + requestSize),
      );
      requests.push(request);
      emit(callbackPtr, STTStreamEvent.create({
        seq: 1,
        requestId: 'stream-request',
        kind: STTStreamEventKind.STT_STREAM_EVENT_KIND_STARTED,
      }));
      emit(callbackPtr, STTStreamEvent.create({
        seq: 2,
        requestId: 'stream-request',
        kind: STTStreamEventKind.STT_STREAM_EVENT_KIND_PARTIAL,
        partial: STTPartialResult.create({ text: 'life', isFinal: false }),
      }));
      emit(callbackPtr, STTStreamEvent.create({
        seq: 3,
        requestId: 'stream-request',
        kind: STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL,
        partial: STTPartialResult.create({ text: 'lifecycle stream', isFinal: true }),
        finalOutput: STTOutput.create({ text: 'lifecycle stream' }),
      }));
      return 0;
    },
    _rac_stt_component_create(outHandlePtr: number): number {
      counters.componentCreates += 1;
      heapU32[outHandlePtr >>> 2] = 77;
      return 0;
    },
    _rac_stt_component_load_model(): number {
      counters.componentLoads += 1;
      currentLifecycleModelId = 'temporary-component-stt';
      return 0;
    },
    _rac_stt_component_transcribe_proto(): number {
      counters.componentTranscribes += 1;
      return 0;
    },
    _rac_stt_component_transcribe_stream_proto(): number {
      counters.componentStreamTranscribes += 1;
      return 0;
    },
    _rac_stt_component_destroy(): void {
      counters.componentDestroys += 1;
      currentLifecycleModelId = null;
    },
  };

  installCurrentModelRegistryExports(module);

  return {
    module,
    counters,
    requests,
    currentLifecycleModelId: () => currentLifecycleModelId,
  };
}
