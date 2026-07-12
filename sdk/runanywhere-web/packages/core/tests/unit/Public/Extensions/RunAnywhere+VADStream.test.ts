import { afterEach, describe, expect, it } from 'vitest';
import {
  VADOptions,
  VADResult,
  VADStreamEvent,
  VADStreamEventKind,
} from '@runanywhere/proto-ts/vad_options';
import type { ModalityProtoModule } from '../../../../src/Adapters/ProtoAdapterTypes';
import { VADProtoAdapter } from '../../../../src/Adapters/VADProtoAdapter';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { installCurrentModelRegistryExports } from '../../helpers/CurrentModelRegistryModule.js';

interface VADStreamCounters {
  componentCreates: number;
  componentLoads: number;
  componentConfigures: number;
  componentInitializes: number;
  componentStarts: number;
  componentStops: number;
  componentDestroys: number;
  callbackSets: number;
  callbackUnsets: number;
  callbackRemovals: number;
  quiesces: number;
  sessionStarts: number;
  sessionFeeds: number;
  sessionStops: number;
  sessionCancels: number;
  fedByteLengths: number[];
}

interface FakeVADModule extends EmscriptenRunanywhereModule, ModalityProtoModule {
  _rac_backend_onnx_register(): number;
  _rac_backend_sherpa_register(): number;
  _rac_vad_component_create(outHandlePtr: number): number;
  _rac_vad_component_load_model(
    handle: number,
    modelPathPtr: number,
    modelIdPtr: number,
    modelNamePtr: number,
  ): number;
  _rac_vad_component_initialize(handle: number): number;
  _rac_vad_component_start(handle: number): number;
  _rac_vad_component_stop(handle: number): number;
  _rac_vad_component_destroy(handle: number): void;
}

interface FakeVADHarness {
  module: FakeVADModule;
  counters: VADStreamCounters;
}

const COMPONENT_HANDLE = 77;
const SESSION_ID = 9n;

function createCounters(): VADStreamCounters {
  return {
    componentCreates: 0,
    componentLoads: 0,
    componentConfigures: 0,
    componentInitializes: 0,
    componentStarts: 0,
    componentStops: 0,
    componentDestroys: 0,
    callbackSets: 0,
    callbackUnsets: 0,
    callbackRemovals: 0,
    quiesces: 0,
    sessionStarts: 0,
    sessionFeeds: 0,
    sessionStops: 0,
    sessionCancels: 0,
    fedByteLengths: [],
  };
}

function fakeVADModule(): FakeVADHarness {
  const counters = createCounters();
  const heap = new ArrayBuffer(128 * 1024);
  const heapU8 = new Uint8Array(heap);
  const heapU32 = new Uint32Array(heap);
  const callbacks = new Map<number, (...args: number[]) => void | number>();
  let nextAllocation = 1_024;
  let nextCallback = 1;
  let streamCallbackPtr = 0;

  const utf8ToString = (ptr: number): string => {
    let end = ptr;
    while (heapU8[end] !== 0) end += 1;
    return new TextDecoder().decode(heapU8.subarray(ptr, end));
  };

  const module: FakeVADModule = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: new Int32Array(heap),
    _malloc(size: number): number {
      const ptr = nextAllocation;
      nextAllocation += Math.max(size, 8);
      return ptr;
    },
    _free: () => undefined,
    addFunction(callback: (...args: number[]) => void | number): number {
      const ptr = nextCallback;
      nextCallback += 1;
      callbacks.set(ptr, callback);
      return ptr;
    },
    removeFunction(ptr: number): void {
      counters.callbackRemovals += 1;
      callbacks.delete(ptr);
    },
    UTF8ToString: utf8ToString,
    lengthBytesUTF8: (value: string) => new TextEncoder().encode(value).length,
    stringToUTF8(value: string, ptr: number, maxBytesToWrite: number): number {
      const bytes = new TextEncoder().encode(value);
      const written = Math.min(bytes.length, maxBytesToWrite - 1);
      heapU8.set(bytes.subarray(0, written), ptr);
      heapU8[ptr + written] = 0;
      return written;
    },
    _rac_proto_buffer_init: () => undefined,
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_voice_agent_set_proto_callback: () => 0,
    _rac_llm_set_stream_proto_callback: () => 0,
    _rac_llm_unset_stream_proto_callback: () => 0,
    _rac_backend_onnx_register: () => 0,
    _rac_backend_sherpa_register: () => 0,
    _rac_vad_component_create(outHandlePtr: number): number {
      counters.componentCreates += 1;
      heapU32[outHandlePtr >>> 2] = COMPONENT_HANDLE;
      return 0;
    },
    _rac_vad_component_load_model(
      handle: number,
      modelPathPtr: number,
      _modelIdPtr: number,
      _modelNamePtr: number,
    ): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      expect(utf8ToString(modelPathPtr)).toBe('/models/silero_vad.onnx');
      counters.componentLoads += 1;
      return 0;
    },
    _rac_vad_component_configure_proto: () => {
      counters.componentConfigures += 1;
      return 0;
    },
    _rac_vad_component_process_proto: () => 0,
    _rac_vad_component_get_statistics_proto: () => 0,
    _rac_vad_component_set_activity_proto_callback: () => 0,
    _rac_vad_component_initialize(handle: number): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      counters.componentInitializes += 1;
      return 0;
    },
    _rac_vad_component_start(handle: number): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      counters.componentStarts += 1;
      return 0;
    },
    _rac_vad_component_stop(handle: number): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      counters.componentStops += 1;
      return 0;
    },
    _rac_vad_component_destroy(handle: number): void {
      expect(handle).toBe(COMPONENT_HANDLE);
      counters.componentDestroys += 1;
    },
    _rac_vad_set_stream_proto_callback(handle, callbackPtr): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      streamCallbackPtr = callbackPtr;
      counters.callbackSets += 1;
      return 0;
    },
    _rac_vad_unset_stream_proto_callback(handle): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      streamCallbackPtr = 0;
      counters.callbackUnsets += 1;
      return 0;
    },
    _rac_vad_proto_quiesce(): void {
      counters.quiesces += 1;
    },
    _rac_vad_stream_start_proto(handle, _optionsPtr, _optionsSize, outSessionIdPtr): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      heapU32[outSessionIdPtr >>> 2] = Number(SESSION_ID & 0xffff_ffffn);
      heapU32[(outSessionIdPtr >>> 2) + 1] = 0;
      counters.sessionStarts += 1;
      return 0;
    },
    _rac_vad_stream_feed_audio_proto(sessionId: bigint, _audioPtr, audioSize): number {
      expect(sessionId).toBe(SESSION_ID);
      counters.sessionFeeds += 1;
      counters.fedByteLengths.push(audioSize);

      const result = VADResult.fromPartial({
        isSpeech: counters.sessionFeeds < 3,
        confidence: counters.sessionFeeds < 3 ? 1 : 0,
        energy: counters.sessionFeeds / 10,
        durationMs: counters.sessionFeeds * 10,
      });
      const event = VADStreamEvent.encode(VADStreamEvent.fromPartial({
        seq: counters.sessionFeeds,
        kind: VADStreamEventKind.VAD_STREAM_EVENT_KIND_FRAME,
        result,
      })).finish();
      const eventPtr = 96 * 1024;
      heapU8.set(event, eventPtr);
      callbacks.get(streamCallbackPtr)?.(eventPtr, event.length, 0);
      return 0;
    },
    _rac_vad_stream_stop_proto(sessionId: bigint): number {
      expect(sessionId).toBe(SESSION_ID);
      counters.sessionStops += 1;
      return 0;
    },
    _rac_vad_stream_cancel_proto(sessionId: bigint): number {
      expect(sessionId).toBe(SESSION_ID);
      counters.sessionCancels += 1;
      return 0;
    },
  };

  installCurrentModelRegistryExports(module);

  return { module, counters };
}

async function* chunks(count: number): AsyncIterable<Float32Array> {
  for (let index = 0; index < count; index += 1) {
    yield new Float32Array([0, 0.25, -0.25, 1]);
  }
}

function install(module: FakeVADModule): void {
  registerWasmModule(['vad'], module, ['onnx', 'sherpa']);
}

afterEach(() => {
  clearRunanywhereModule();
});

describe('persistent Web VAD streaming', () => {
  it('preserves one native session across every chunk', async () => {
    const { module, counters } = fakeVADModule();
    install(module);
    const adapter = new VADProtoAdapter(module);

    const results: VADResult[] = [];
    for await (const result of adapter.stream(
      COMPONENT_HANDLE,
      chunks(3),
      VADOptions.create(),
    )) {
      results.push(result);
    }

    expect(results.map((result) => result.isSpeech)).toEqual([true, true, false]);
    expect(results.map((result) => result.durationMs)).toEqual([10, 20, 30]);
    expect(counters).toMatchObject({
      componentCreates: 0,
      componentLoads: 0,
      componentConfigures: 0,
      componentInitializes: 0,
      componentStarts: 0,
      componentStops: 0,
      componentDestroys: 0,
      callbackSets: 1,
      callbackUnsets: 1,
      callbackRemovals: 1,
      quiesces: 1,
      sessionStarts: 1,
      sessionFeeds: 3,
      sessionStops: 1,
      sessionCancels: 0,
      fedByteLengths: [8, 8, 8],
    });
  });

  it('cancels and tears down exactly once when the consumer exits early', async () => {
    const { module, counters } = fakeVADModule();
    install(module);
    const adapter = new VADProtoAdapter(module);

    for await (const _result of adapter.stream(
      COMPONENT_HANDLE,
      chunks(3),
      VADOptions.create(),
    )) {
      break;
    }

    expect(counters).toMatchObject({
      componentLoads: 0,
      componentDestroys: 0,
      callbackSets: 1,
      callbackUnsets: 1,
      callbackRemovals: 1,
      quiesces: 1,
      sessionStarts: 1,
      sessionFeeds: 1,
      sessionStops: 0,
      sessionCancels: 1,
    });
  });
});
