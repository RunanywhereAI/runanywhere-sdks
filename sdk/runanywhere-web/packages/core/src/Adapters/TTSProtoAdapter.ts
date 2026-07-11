import {
  TTSOptions,
  TTSOutput,
  TTSServiceState,
  TTSStreamEvent,
  TTSStreamEventKind,
  TTSSynthesisRequest,
  TTSVoiceList,
  TTSVoiceInfo,
  type TTSOptions as ProtoTTSOptions,
  type TTSOutput as ProtoTTSOutput,
  type TTSServiceState as ProtoTTSServiceState,
  type TTSStreamEvent as ProtoTTSStreamEvent,
  type TTSVoiceInfo as ProtoTTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  collectCallback,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  requireExports,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

export class TTSProtoAdapter {
  static tryDefault(): TTSProtoAdapter | null {
    const mod = adapterState.modalitySlots.tts;
    return mod ? new TTSProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoTTS(): boolean {
    return missingExports(this.module, [
      '_rac_tts_component_list_voices_proto',
      '_rac_tts_component_synthesize_proto',
      '_rac_tts_component_synthesize_stream_proto',
    ]).length === 0;
  }

  /** Whether one-shot synthesis can use the model owned by model lifecycle. */
  supportsLifecycleProtoTTS(): boolean {
    return missingExports(this.module, [
      '_rac_tts_synthesize_lifecycle_proto',
    ]).length === 0;
  }

  /** Whether streaming synthesis can use the model owned by model lifecycle. */
  supportsLifecycleProtoTTSStream(): boolean {
    return missingExports(this.module, [
      '_rac_tts_synthesize_stream_lifecycle_proto',
    ]).length === 0;
  }

  synthesizeLifecycle(
    text: string,
    options: ProtoTTSOptions,
    ssml?: string,
  ): ProtoTTSOutput | null {
    if (!ensureExports(this.module, 'tts.synthesizeLifecycle', [
      '_rac_tts_synthesize_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      lifecycleRequest(text, options, ssml),
      TTSSynthesisRequest,
      TTSOutput,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_tts_synthesize_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_tts_synthesize_lifecycle_proto',
    );
  }

  /**
   * Canonical lifecycle stream envelopes. Callers that need phoneme/progress
   * events can consume this method without losing information while the
   * `synthesizeLifecycleStream` convenience below preserves the existing
   * AsyncIterable<TTSOutput> surface.
   */
  synthesizeLifecycleStreamEvents(
    text: string,
    options: ProtoTTSOptions,
    ssml?: string,
  ): AsyncIterable<ProtoTTSStreamEvent> {
    requireExports(this.module, 'tts.synthesizeLifecycleStream', [
      '_rac_tts_synthesize_stream_lifecycle_proto',
    ]);
    const requestBytes = TTSSynthesisRequest.encode(
      lifecycleRequest(text, options, ssml),
    ).finish();
    return streamCallback(
      this.module,
      TTSStreamEvent,
      'rac_tts_synthesize_stream_lifecycle_proto',
      (callbackPtr) => this.bridge().withHeapBytes(
        requestBytes,
        (requestPtr, requestSize) => (
          this.module._rac_tts_synthesize_stream_lifecycle_proto!(
            requestPtr,
            requestSize,
            callbackPtr,
            0,
          )
        ),
      ),
      (event) => event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_COMPLETED
        || event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR,
      undefined,
      (rc) => TTSStreamEvent.fromPartial({
        kind: TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR,
        errorCode: rc,
        errorMessage: `TTS stream failed: ${rc}`,
      }),
    );
  }

  synthesizeLifecycleStream(
    text: string,
    options: ProtoTTSOptions,
    ssml?: string,
  ): AsyncIterable<ProtoTTSOutput> {
    const events = this.synthesizeLifecycleStreamEvents(text, options, ssml);
    return outputsFromLifecycleEvents(events);
  }

  listLifecycleVoices(): ProtoTTSVoiceInfo[] | null {
    if (!ensureExports(this.module, 'tts.listLifecycleVoices', [
      '_rac_tts_list_voices_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().callResultProto(
      TTSVoiceList,
      (outResult) => this.module._rac_tts_list_voices_lifecycle_proto!(outResult),
      'rac_tts_list_voices_lifecycle_proto',
    )?.voices ?? null;
  }

  stopLifecycle(): ProtoTTSServiceState | null {
    if (!ensureExports(this.module, 'tts.stopLifecycle', [
      '_rac_tts_stop_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().callResultProto(
      TTSServiceState,
      (outResult) => this.module._rac_tts_stop_lifecycle_proto!(outResult),
      'rac_tts_stop_lifecycle_proto',
    );
  }

  listVoices(handle: number): ProtoTTSVoiceInfo[] | null {
    if (!ensureExports(this.module, 'tts.listVoices', ['_rac_tts_component_list_voices_proto'])) {
      return null;
    }
    return collectCallback(
      this.module,
      TTSVoiceInfo,
      'rac_tts_component_list_voices_proto',
      (callbackPtr) => this.module._rac_tts_component_list_voices_proto!(handle, callbackPtr, 0),
    );
  }

  synthesize(
    handle: number,
    text: string,
    options: ProtoTTSOptions,
  ): ProtoTTSOutput | null {
    if (!ensureExports(this.module, 'tts.synthesize', ['_rac_tts_component_synthesize_proto'])) {
      return null;
    }
    const bridge = this.bridge();
    const optionsBytes = TTSOptions.encode(options).finish();
    const textPtr = bridge.allocUtf8(text);
    if (!textPtr) return null;
    try {
      return bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          TTSOutput,
          (outResult) => this.module._rac_tts_component_synthesize_proto!(
            handle,
            textPtr,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_tts_component_synthesize_proto',
        )
      ));
    } finally {
      bridge.free(textPtr);
    }
  }

  synthesizeStream(
    handle: number,
    text: string,
    options: ProtoTTSOptions,
  ): AsyncIterable<ProtoTTSOutput> {
    const optionsBytes = TTSOptions.encode(options).finish();
    // T6.1: prefer Worker path when available; otherwise main-thread MVP.
    const offscreen = OffscreenRuntimeBridge.tryGet();
    if (offscreen != null) {
      return offscreen.getStreamIterator(
        { kind: 'stream.tts.synthesize', handle, text, optionsBytes },
        TTSOutput,
      );
    }
    requireExports(this.module, 'tts.synthesizeStream', [
      '_rac_tts_component_synthesize_stream_proto',
    ]);
    return streamCallback(
      this.module,
      TTSOutput,
      'rac_tts_component_synthesize_stream_proto',
      (callbackPtr) => {
        const bridge = this.bridge();
        const textPtr = bridge.allocUtf8(text);
        if (!textPtr) return -903;
        try {
          return bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
            this.module._rac_tts_component_synthesize_stream_proto!(
              handle,
              textPtr,
              optionsPtr,
              optionsSize,
              callbackPtr,
              0,
            )
          ));
        } finally {
          bridge.free(textPtr);
        }
      },
      undefined,
      undefined,
      // Swift parity (ModalityProtoABI+Generated.swift:448-455): terminal
      // timestamp-only output instead of rejecting the iterator.
      () => TTSOutput.fromPartial({ timestampMs: Date.now() }),
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

function lifecycleRequest(
  text: string,
  options: ProtoTTSOptions,
  ssml?: string,
): ReturnType<typeof TTSSynthesisRequest.create> {
  return TTSSynthesisRequest.create({
    text,
    ssml,
    options,
    metadata: {},
  });
}

async function* outputsFromLifecycleEvents(
  events: AsyncIterable<ProtoTTSStreamEvent>,
): AsyncIterable<ProtoTTSOutput> {
  for await (const event of events) {
    if (event.output) {
      yield event.output;
      continue;
    }
    if (event.kind === TTSStreamEventKind.TTS_STREAM_EVENT_KIND_ERROR) {
      yield TTSOutput.fromPartial({
        isFinal: true,
        timestampMs: Date.now(),
        errorCode: event.errorCode,
        errorMessage: event.errorMessage ?? 'TTS lifecycle stream failed',
      });
    }
  }
}
