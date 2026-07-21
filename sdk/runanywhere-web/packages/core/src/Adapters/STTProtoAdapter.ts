import {
  STTAudioEncoding,
  STTOptions,
  STTOutput,
  STTPartialResult,
  STTStreamEvent,
  STTStreamEventKind,
  STTTranscriptionRequest,
  type STTOptions as ProtoSTTOptions,
  type STTOutput as ProtoSTTOutput,
  type STTPartialResult as ProtoSTTPartialResult,
  type STTStreamEvent as ProtoSTTStreamEvent,
  type STTTranscriptionRequest as ProtoSTTTranscriptionRequest,
} from '@runanywhere/proto-ts/stt_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge.js';
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  decodeWorkerInferResult,
  decodeWorkerStream,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  requireExports,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

export class STTProtoAdapter {
  static tryDefault(): STTProtoAdapter | null {
    const mod = adapterState.modalitySlots.stt;
    return mod ? new STTProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoSTT(): boolean {
    return missingExports(this.module, [
      '_rac_stt_component_transcribe_proto',
      '_rac_stt_component_transcribe_stream_proto',
    ]).length === 0;
  }

  supportsLifecycleProtoSTT(): boolean {
    return missingExports(this.module, [
      '_rac_stt_transcribe_lifecycle_proto',
      '_rac_stt_transcribe_stream_lifecycle_proto',
    ]).length === 0;
  }

  async transcribeLifecycle(
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): Promise<ProtoSTTOutput | null> {
    const request = lifecycleRequest(audioData, options);
    const host = getActiveBackendWorkerHost('onnx');
    if (host?.diagnostics.executionContext === 'worker') {
      const response = await host.infer('stt.transcribe', {
        requestBytes: STTTranscriptionRequest.encode(request).finish(),
      });
      return decodeWorkerInferResult(response, STTOutput);
    }
    if (!ensureExports(this.module, 'stt.transcribeLifecycle', [
      '_rac_stt_transcribe_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      request,
      STTTranscriptionRequest,
      STTOutput,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_stt_transcribe_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_stt_transcribe_lifecycle_proto',
    );
  }

  transcribeLifecycleStream(
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): AsyncIterable<ProtoSTTStreamEvent> {
    const requestBytes = STTTranscriptionRequest.encode(
      lifecycleRequest(audioData, options),
    ).finish();
    const host = getActiveBackendWorkerHost('onnx');
    if (host?.diagnostics.executionContext === 'worker') {
      return decodeWorkerStream(host.stream('stt.transcribe', { requestBytes }), STTStreamEvent);
    }
    requireExports(this.module, 'stt.transcribeLifecycleStream', [
      '_rac_stt_transcribe_stream_lifecycle_proto',
    ]);
    return streamCallback(
      this.module,
      STTStreamEvent,
      'rac_stt_transcribe_stream_lifecycle_proto',
      (callbackPtr) => this.bridge().withHeapBytes(
        requestBytes,
        (requestPtr, requestSize) => (
          this.module._rac_stt_transcribe_stream_lifecycle_proto!(
            requestPtr,
            requestSize,
            callbackPtr,
            0,
          )
        ),
      ),
      (event) => event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL
        || event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR,
      undefined,
      (rc) => STTStreamEvent.fromPartial({
        kind: STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR,
        errorCode: rc,
        errorMessage: `STT stream failed: ${rc}`,
      }),
    );
  }

  transcribe(
    handle: number,
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): ProtoSTTOutput | null {
    if (!ensureExports(this.module, 'stt.transcribe', ['_rac_stt_component_transcribe_proto'])) {
      return null;
    }
    const optionsBytes = STTOptions.encode(options).finish();
    const bridge = this.bridge();
    return bridge.withHeapBytes(audioData, (audioPtr, audioSize) => (
      bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          STTOutput,
          (outResult) => this.module._rac_stt_component_transcribe_proto!(
            handle,
            audioPtr,
            audioSize,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_stt_component_transcribe_proto',
        )
      ))
    ));
  }

  transcribeStream(
    handle: number,
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): AsyncIterable<ProtoSTTPartialResult> {
    const optionsBytes = STTOptions.encode(options).finish();
    // T6.1: prefer Worker path when available; otherwise main-thread MVP.
    const offscreen = OffscreenRuntimeBridge.tryGet();
    if (offscreen != null) {
      return offscreen.getStreamIterator(
        {
          kind: 'stream.stt.transcribe',
          handle,
          audioBytes: audioData,
          optionsBytes,
        },
        STTPartialResult,
        { stopWhen: (event) => event.isFinal },
      );
    }
    requireExports(this.module, 'stt.transcribeStream', [
      '_rac_stt_component_transcribe_stream_proto',
    ]);
    return streamCallback(
      this.module,
      STTPartialResult,
      'rac_stt_component_transcribe_stream_proto',
      (callbackPtr) => this.bridge().withHeapBytes(audioData, (audioPtr, audioSize) => (
        this.bridge().withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
          this.module._rac_stt_component_transcribe_stream_proto!(
            handle,
            audioPtr,
            audioSize,
            optionsPtr,
            optionsSize,
            callbackPtr,
            0,
          )
        ))
      )),
      (event) => event.isFinal,
      undefined,
      // Swift parity (ModalityProtoABI+Generated.swift:394-398): terminal
      // final partial instead of rejecting the iterator.
      (rc) => STTPartialResult.fromPartial({
        isFinal: true,
        text: `STT stream failed: ${rc}`,
      }),
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}

function lifecycleRequest(
  audioData: Uint8Array,
  options: ProtoSTTOptions,
): ProtoSTTTranscriptionRequest {
  return STTTranscriptionRequest.create({
    audio: {
      audioData,
      encoding: STTAudioEncoding.STT_AUDIO_ENCODING_PCM_S16_LE,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM_S16LE,
      sampleRate: options.sampleRate > 0 ? options.sampleRate : 16_000,
      channels: 1,
      bitsPerSample: 16,
    },
    options,
  });
}
