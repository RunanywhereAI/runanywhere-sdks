import { AudioEncoding } from '@runanywhere/proto-ts/model_types';
import {
  STTOutput,
  STTPartialResult,
  STTServiceState,
  STTStreamEvent,
  STTStreamEventKind,
  STTTranscriptionRequest,
  type STTOptions as ProtoSTTOptions,
  type STTOutput as ProtoSTTOutput,
  type STTPartialResult as ProtoSTTPartialResult,
  type STTServiceState as ProtoSTTServiceState,
  type STTStreamEvent as ProtoSTTStreamEvent,
  type STTTranscriptionRequest as ProtoSTTTranscriptionRequest,
} from '@runanywhere/proto-ts/stt_options';
import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge.js';
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import { mustUseOnnxBackendWorker } from '../runtime/BackendWorkerModelOwnership.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import { SDKException } from '../Foundation/SDKException.js';
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
import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';

function requireLiveOnnxWorkerOrMain(operation: string) {
  const host = getActiveBackendWorkerHost('onnx');
  if (host?.diagnostics.executionContext === 'worker') return host;
  if (mustUseOnnxBackendWorker()) {
    throw SDKException.backendNotAvailable(
      operation,
      'ONNX BackendWorker is required for speech (or owns loaded models); '
        + 'reload after recovering the worker. Main-thread fallback is disabled.',
    );
  }
  return null;
}

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

  stateLifecycle(): ProtoSTTServiceState | null {
    if (!ensureExports(this.module, 'stt.stateLifecycle', [
      '_rac_stt_state_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().callResultProto(
      STTServiceState,
      (outResult) => this.module._rac_stt_state_lifecycle_proto!(outResult),
      'rac_stt_state_lifecycle_proto',
    );
  }

  async transcribeLifecycle(
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): Promise<ProtoSTTOutput | null> {
    const request = lifecycleRequest(audioData, options);
    const host = requireLiveOnnxWorkerOrMain('stt.transcribeLifecycle');
    if (host) {
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
    const host = requireLiveOnnxWorkerOrMain('stt.transcribeLifecycleStream');
    if (host) {
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
        error: SDKException.fromCode(rc, `STT stream failed: ${rc}`).proto,
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
    return this.bridge().withEncodedRequest(
      lifecycleRequest(audioData, options),
      STTTranscriptionRequest,
      STTOutput,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_stt_component_transcribe_proto!(
          handle,
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_stt_component_transcribe_proto',
    );
  }

  transcribeStream(
    handle: number,
    audioData: Uint8Array,
    options: ProtoSTTOptions,
  ): AsyncIterable<ProtoSTTPartialResult> {
    const requestBytes = STTTranscriptionRequest.encode(
      lifecycleRequest(audioData, options),
    ).finish();
    // T6.1: prefer Worker path when available; otherwise main-thread MVP.
    const offscreen = OffscreenRuntimeBridge.tryGet();
    if (offscreen != null) {
      return offscreen.getStreamIterator(
        {
          kind: 'stream.stt.transcribe',
          handle,
          requestBytes,
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
      (callbackPtr) => this.bridge().withHeapBytes(requestBytes, (requestPtr, requestSize) => (
        this.module._rac_stt_component_transcribe_stream_proto!(
          handle,
          requestPtr,
          requestSize,
          callbackPtr,
          0,
        )
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
  sampleRate = audioCaptureDefaults.micSampleRateHz,
): ProtoSTTTranscriptionRequest {
  return STTTranscriptionRequest.create({
    audio: {
      audioData,
      encoding: AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM_S16LE,
      sampleRate,
      channels: 1,
      durationMs: (audioData.byteLength / 2 / sampleRate) * 1000,
    },
    options,
  });
}
