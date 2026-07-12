import { afterEach, describe, expect, it, vi } from 'vitest';
import { CurrentModelResult } from '@runanywhere/proto-ts/model_types';
import {
  TTSOptions,
  TTSOutput,
  TTSServiceState,
  TTSStreamEvent,
  TTSStreamEventKind,
  TTSSynthesisRequest,
  TTSVoiceList,
  type TTSSynthesisRequest as ProtoTTSSynthesisRequest,
} from '@runanywhere/proto-ts/tts_options';
import { TTSProtoAdapter } from '../../../../src/Adapters/TTSProtoAdapter';
import type { ModalityProtoModule } from '../../../../src/Adapters/ProtoAdapterTypes';
import { flatFacade } from '../../../../src/Public/Extensions/RunAnywhere+FlatFacade';
import {
  synthesize,
  TTS,
} from '../../../../src/Public/Extensions/RunAnywhere+TTS';
import { WebModelLifecycle } from '../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle';
import {
  clearRunanywhereModule,
  registerWasmModule,
  type EmscriptenRunanywhereModule,
} from '../../../../src/runtime/EmscriptenModule';
import { installCurrentModelRegistryExports } from '../../helpers/CurrentModelRegistryModule.js';

interface TTSCallCounters {
  lifecycleSyntheses: number;
  lifecycleStreams: number;
  lifecycleStops: number;
  lifecycleVoiceLists: number;
  componentCreates: number;
  componentLoads: number;
  componentSyntheses: number;
  componentStops: number;
  componentDestroys: number;
  callbackRemovals: number;
}

interface FakeTTSModule extends EmscriptenRunanywhereModule, ModalityProtoModule {
  _rac_backend_onnx_register(): number;
  _rac_backend_sherpa_register(): number;
  _rac_tts_component_create(outHandlePtr: number): number;
  _rac_tts_component_load_voice(
    handle: number,
    voicePathPtr: number,
    voiceIdPtr: number,
    voiceNamePtr: number,
  ): number;
  _rac_tts_component_stop(handle: number): number;
  _rac_tts_component_destroy(handle: number): void;
}

interface FakeTTSHarness {
  module: FakeTTSModule;
  counters: TTSCallCounters;
  lifecycleRequests: ProtoTTSSynthesisRequest[];
  componentTexts: string[];
  setStreamFailure(enabled: boolean): void;
}

const COMPONENT_HANDLE = 73;

afterEach(() => {
  clearRunanywhereModule();
  vi.restoreAllMocks();
});

describe('lifecycle-owned Web TTS', () => {
  it('synthesizes through the canonical lifecycle model without replacing it', async () => {
    const harness = fakeTTSModule();
    install(harness.module);
    mockCurrentLifecycleVoice('piper-en-us');

    const output = await synthesize('Keep this voice loaded.', {
      voiceId: 'speaker-2',
      speakingRate: 1.1,
    });

    expect(new TextDecoder().decode(output.audioData)).toBe('lifecycle-audio');
    expect(harness.lifecycleRequests).toHaveLength(1);
    expect(harness.lifecycleRequests[0]).toMatchObject({
      text: 'Keep this voice loaded.',
      options: {
        voice: 'speaker-2',
      },
    });
    expect(harness.lifecycleRequests[0]?.options?.speakingRate).toBeCloseTo(1.1);
    expect(harness.counters).toMatchObject({
      lifecycleSyntheses: 1,
      componentCreates: 0,
      componentLoads: 0,
      componentSyntheses: 0,
      componentDestroys: 0,
    });

    expect(WebModelLifecycle.currentModel({})).toMatchObject({
      modelId: 'piper-en-us',
    });
  });

  it('requires a lifecycle-owned voice', async () => {
    const harness = fakeTTSModule();
    install(harness.module);
    mockNoLifecycleVoice();

    await expect(synthesize('No loaded voice.')).rejects.toMatchObject({
      message: expect.stringContaining('No TTS voice is loaded'),
    });
    expect(harness.counters).toMatchObject({
      lifecycleSyntheses: 0,
      componentCreates: 0,
      componentLoads: 0,
      componentSyntheses: 0,
      componentDestroys: 0,
    });
  });

  it('decodes lifecycle stream envelopes into audio and terminal error outputs', async () => {
    const harness = fakeTTSModule();
    const adapter = new TTSProtoAdapter(harness.module);

    const successful = await collect(adapter.synthesizeLifecycleStream(
      'Stream this.',
      ttsOptionsForTest(),
    ));
    expect(successful).toHaveLength(1);
    expect(new TextDecoder().decode(successful[0]!.audioData)).toBe('stream-audio');

    harness.setStreamFailure(true);
    const failed = await collect(adapter.synthesizeLifecycleStream(
      'Fail this.',
      ttsOptionsForTest(),
    ));
    expect(failed).toHaveLength(1);
    expect(failed[0]).toMatchObject({
      isFinal: true,
      errorCode: -42,
      errorMessage: 'forced lifecycle stream failure',
    });
    expect(harness.counters).toMatchObject({
      lifecycleStreams: 2,
      callbackRemovals: 2,
    });
  });

  it('lists and stops the canonical lifecycle service when no handle is supplied', () => {
    const harness = fakeTTSModule();
    install(harness.module);
    mockCurrentLifecycleVoice('piper-en-us');

    expect(TTS.listLoadedVoices()).toEqual([
      expect.objectContaining({ id: 'piper-en-us', displayName: 'Piper US' }),
    ]);
    expect(flatFacade.stopSpeaking()).toBe(true);
    expect(harness.counters).toMatchObject({
      lifecycleVoiceLists: 1,
      lifecycleStops: 1,
      componentStops: 0,
    });
  });
});

function ttsOptionsForTest(): ReturnType<typeof TTSOptions.create> {
  return TTSOptions.create({ sampleRate: 22_050 });
}

async function collect<T>(values: AsyncIterable<T>): Promise<T[]> {
  const collected: T[] = [];
  for await (const value of values) collected.push(value);
  return collected;
}

function install(module: FakeTTSModule): void {
  registerWasmModule(['tts'], module, ['onnx', 'sherpa']);
}

function mockCurrentLifecycleVoice(modelId: string): void {
  vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
  vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
    CurrentModelResult.create({ found: true, modelId, resolvedPath: `/models/${modelId}` }),
  );
}

function mockNoLifecycleVoice(): void {
  vi.spyOn(WebModelLifecycle, 'supportsNativeLifecycle').mockReturnValue(true);
  vi.spyOn(WebModelLifecycle, 'currentModel').mockReturnValue(
    CurrentModelResult.create({ found: false }),
  );
}

function fakeTTSModule(): FakeTTSHarness {
  const counters: TTSCallCounters = {
    lifecycleSyntheses: 0,
    lifecycleStreams: 0,
    lifecycleStops: 0,
    lifecycleVoiceLists: 0,
    componentCreates: 0,
    componentLoads: 0,
    componentSyntheses: 0,
    componentStops: 0,
    componentDestroys: 0,
    callbackRemovals: 0,
  };
  const lifecycleRequests: ProtoTTSSynthesisRequest[] = [];
  const componentTexts: string[] = [];
  const memory = new ArrayBuffer(256 * 1024);
  const heapU8 = new Uint8Array(memory);
  const heap32 = new Int32Array(memory);
  const heapU32 = new Uint32Array(memory);
  const callbacks = new Map<number, (...args: number[]) => number | void>();
  let nextPointer = 1_024;
  let nextCallback = 1;
  let streamFailure = false;

  const allocate = (size: number): number => {
    const pointer = nextPointer;
    nextPointer += (Math.max(size, 1) + 7) & ~7;
    return pointer;
  };
  const utf8ToString = (pointer: number): string => {
    let end = pointer;
    while (heapU8[end] !== 0) end += 1;
    return new TextDecoder().decode(heapU8.subarray(pointer, end));
  };
  const writeResult = (outResult: number, bytes: Uint8Array): void => {
    const dataPointer = allocate(bytes.byteLength);
    heapU8.set(bytes, dataPointer);
    heapU32[outResult >>> 2] = dataPointer;
    heapU32[(outResult >>> 2) + 1] = bytes.byteLength;
    heap32[(outResult >>> 2) + 2] = 0;
    heapU32[(outResult >>> 2) + 3] = 0;
  };
  const emit = (callbackPointer: number, event: TTSStreamEvent): void => {
    const bytes = TTSStreamEvent.encode(event).finish();
    const eventPointer = allocate(bytes.byteLength);
    heapU8.set(bytes, eventPointer);
    callbacks.get(callbackPointer)?.(eventPointer, bytes.byteLength, 0);
  };

  const module: FakeTTSModule = {
    HEAPU8: heapU8,
    HEAP32: heap32,
    HEAPU32: heapU32,
    _malloc: allocate,
    _free: () => undefined,
    getValue: (pointer) => heap32[pointer >>> 2] ?? 0,
    setValue: (pointer, value) => {
      heap32[pointer >>> 2] = value;
    },
    UTF8ToString: utf8ToString,
    lengthBytesUTF8: (value) => new TextEncoder().encode(value).byteLength,
    stringToUTF8(value, pointer, maxBytesToWrite): number {
      const bytes = new TextEncoder().encode(value);
      const written = Math.min(bytes.byteLength, Math.max(0, maxBytesToWrite - 1));
      heapU8.set(bytes.subarray(0, written), pointer);
      heapU8[pointer + written] = 0;
      return written;
    },
    addFunction(callback): number {
      const pointer = nextCallback;
      nextCallback += 1;
      callbacks.set(pointer, callback);
      return pointer;
    },
    removeFunction(pointer): void {
      counters.callbackRemovals += 1;
      callbacks.delete(pointer);
    },
    _rac_voice_agent_set_proto_callback: () => 0,
    _rac_llm_set_stream_proto_callback: () => 0,
    _rac_llm_unset_stream_proto_callback: () => 0,
    _rac_proto_buffer_init: (pointer) => {
      heapU32.fill(0, pointer >>> 2, (pointer >>> 2) + 4);
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_backend_onnx_register: () => 0,
    _rac_backend_sherpa_register: () => 0,
    _rac_tts_synthesize_lifecycle_proto(requestPointer, requestSize, outResult): number {
      counters.lifecycleSyntheses += 1;
      lifecycleRequests.push(TTSSynthesisRequest.decode(
        heapU8.slice(requestPointer, requestPointer + requestSize),
      ));
      writeResult(outResult, TTSOutput.encode(TTSOutput.create({
        audioData: new TextEncoder().encode('lifecycle-audio'),
        sampleRate: 22_050,
        isFinal: true,
      })).finish());
      return 0;
    },
    _rac_tts_synthesize_stream_lifecycle_proto(
      requestPointer,
      requestSize,
      callbackPointer,
    ): number {
      counters.lifecycleStreams += 1;
      lifecycleRequests.push(TTSSynthesisRequest.decode(
        heapU8.slice(requestPointer, requestPointer + requestSize),
      ));
      emit(callbackPointer, TTSStreamEvent.create({
        kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_STARTED,
      }));
      if (streamFailure) {
        emit(callbackPointer, TTSStreamEvent.create({
          kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR,
          errorCode: -42,
          errorMessage: 'forced lifecycle stream failure',
        }));
        return -42;
      }
      emit(callbackPointer, TTSStreamEvent.create({
        kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_AUDIO_CHUNK,
        output: TTSOutput.create({
          audioData: new TextEncoder().encode('stream-audio'),
          sampleRate: 22_050,
        }),
      }));
      emit(callbackPointer, TTSStreamEvent.create({
        kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED,
      }));
      return 0;
    },
    _rac_tts_stop_lifecycle_proto(outResult): number {
      counters.lifecycleStops += 1;
      writeResult(outResult, TTSServiceState.encode(TTSServiceState.create({
        isReady: true,
        currentVoice: 'piper-en-us',
      })).finish());
      return 0;
    },
    _rac_tts_list_voices_lifecycle_proto(outResult): number {
      counters.lifecycleVoiceLists += 1;
      writeResult(outResult, TTSVoiceList.encode(TTSVoiceList.create({
        voices: [{ id: 'piper-en-us', displayName: 'Piper US' }],
      })).finish());
      return 0;
    },
    _rac_tts_component_create(outHandlePointer): number {
      counters.componentCreates += 1;
      heapU32[outHandlePointer >>> 2] = COMPONENT_HANDLE;
      return 0;
    },
    _rac_tts_component_load_voice(handle, voicePathPointer): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      expect(utf8ToString(voicePathPointer)).toBe('/models/fallback-voice.onnx');
      counters.componentLoads += 1;
      return 0;
    },
    _rac_tts_component_list_voices_proto: () => 0,
    _rac_tts_component_synthesize_proto(handle, textPointer, _options, _size, outResult): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      counters.componentSyntheses += 1;
      componentTexts.push(utf8ToString(textPointer));
      writeResult(outResult, TTSOutput.encode(TTSOutput.create({
        audioData: new TextEncoder().encode('component-audio'),
        sampleRate: 22_050,
        isFinal: true,
      })).finish());
      return 0;
    },
    _rac_tts_component_synthesize_stream_proto: () => 0,
    _rac_tts_component_stop(handle): number {
      expect(handle).toBe(COMPONENT_HANDLE);
      counters.componentStops += 1;
      return 0;
    },
    _rac_tts_component_destroy(handle): void {
      expect(handle).toBe(COMPONENT_HANDLE);
      counters.componentDestroys += 1;
    },
  };

  installCurrentModelRegistryExports(module);

  return {
    module,
    counters,
    lifecycleRequests,
    componentTexts,
    setStreamFailure(enabled): void {
      streamFailure = enabled;
    },
  };
}
