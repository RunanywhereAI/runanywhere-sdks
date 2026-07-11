import {
  SpeechActivityEvent,
  VADConfiguration,
  VADAudioEncoding,
  VADOptions,
  VADProcessRequest,
  VADResult,
  VADServiceState,
  VADStatistics,
  VADStreamEvent,
  VADStreamEventKind,
  type SpeechActivityEvent as ProtoSpeechActivityEvent,
  type VADConfiguration as ProtoVADConfiguration,
  type VADOptions as ProtoVADOptions,
  type VADResult as ProtoVADResult,
  type VADServiceState as ProtoVADServiceState,
  type VADStatistics as ProtoVADStatistics,
  type VADStreamEvent as ProtoVADStreamEvent,
} from '@runanywhere/proto-ts/vad_options';
import { SDKException } from '../Foundation/SDKException.js';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import { readWasmUint64 } from '../runtime/WasmInt64.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  requireExports,
  type ModalityProtoModule,
  type ProtoEventHandler,
} from './ProtoAdapterTypes.js';

export class VADProtoAdapter {
  static tryDefault(): VADProtoAdapter | null {
    const mod = adapterState.modalitySlots.vad;
    return mod ? new VADProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoVAD(): boolean {
    return missingExports(this.module, [
      '_rac_vad_component_configure_proto',
      '_rac_vad_component_process_proto',
      '_rac_vad_component_get_statistics_proto',
      '_rac_vad_component_set_activity_proto_callback',
    ]).length === 0;
  }

  supportsProtoVADStream(): boolean {
    return missingExports(this.module, [
      '_rac_vad_set_stream_proto_callback',
      '_rac_vad_unset_stream_proto_callback',
      '_rac_vad_proto_quiesce',
      '_rac_vad_stream_start_proto',
      '_rac_vad_stream_feed_audio_proto',
      '_rac_vad_stream_stop_proto',
      '_rac_vad_stream_cancel_proto',
    ]).length === 0;
  }

  /** Handle-less ABI backed by the model loaded through ModelLifecycle. */
  supportsLifecycleVAD(): boolean {
    return missingExports(this.module, [
      '_rac_vad_process_lifecycle_proto',
      '_rac_vad_configure_lifecycle_proto',
      '_rac_vad_start_lifecycle_proto',
      '_rac_vad_stop_lifecycle_proto',
      '_rac_vad_reset_lifecycle_proto',
    ]).length === 0;
  }

  configureLifecycle(config: ProtoVADConfiguration): ProtoVADServiceState | null {
    if (!ensureExports(this.module, 'vad.configureLifecycle', [
      '_rac_vad_configure_lifecycle_proto',
    ])) {
      return null;
    }
    return this.bridge().withEncodedRequest(
      config,
      VADConfiguration,
      VADServiceState,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_vad_configure_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_vad_configure_lifecycle_proto',
    );
  }

  processLifecycle(
    samples: Float32Array,
    options: ProtoVADOptions,
    sampleRate = 16_000,
  ): ProtoVADResult | null {
    if (!ensureExports(this.module, 'vad.processLifecycle', [
      '_rac_vad_process_lifecycle_proto',
    ])) {
      return null;
    }
    const request = VADProcessRequest.create({
      requestId: lifecycleRequestId(),
      audio: {
        audioData: float32ToLittleEndianBytes(samples),
        encoding: VADAudioEncoding.VAD_AUDIO_ENCODING_PCM_F32_LE,
        sampleRate,
        channels: 1,
        frameOffsetMs: 0,
      },
      options,
      metadata: {},
    });
    return this.bridge().withEncodedRequest(
      request,
      VADProcessRequest,
      VADResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_vad_process_lifecycle_proto!(
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_vad_process_lifecycle_proto',
    );
  }

  startLifecycle(): ProtoVADServiceState | null {
    return this.callLifecycleState(
      'vad.startLifecycle',
      '_rac_vad_start_lifecycle_proto',
      'rac_vad_start_lifecycle_proto',
    );
  }

  stopLifecycle(): ProtoVADServiceState | null {
    return this.callLifecycleState(
      'vad.stopLifecycle',
      '_rac_vad_stop_lifecycle_proto',
      'rac_vad_stop_lifecycle_proto',
    );
  }

  resetLifecycle(): ProtoVADServiceState | null {
    return this.callLifecycleState(
      'vad.resetLifecycle',
      '_rac_vad_reset_lifecycle_proto',
      'rac_vad_reset_lifecycle_proto',
    );
  }

  configure(handle: number, config: ProtoVADConfiguration): boolean {
    if (!ensureExports(this.module, 'vad.configure', ['_rac_vad_component_configure_proto'])) {
      return false;
    }
    const bytes = VADConfiguration.encode(config).finish();
    const rc = this.bridge().withHeapBytes(bytes, (ptr, size) => (
      this.module._rac_vad_component_configure_proto!(handle, ptr, size)
    ));
    if (rc !== 0) logger.warning(`rac_vad_component_configure_proto returned ${formatRacResult(rc)}`);
    return rc === 0;
  }

  process(
    handle: number,
    samples: Float32Array,
    options: ProtoVADOptions,
  ): ProtoVADResult | null {
    if (!ensureExports(this.module, 'vad.process', ['_rac_vad_component_process_proto'])) {
      return null;
    }
    const sampleBytes = new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
    const optionsBytes = VADOptions.encode(options).finish();
    const bridge = this.bridge();
    return bridge.withHeapBytes(sampleBytes, (samplesPtr) => (
      bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          VADResult,
          (outResult) => this.module._rac_vad_component_process_proto!(
            handle,
            samplesPtr,
            samples.length,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_vad_component_process_proto',
        )
      ))
    ));
  }

  /**
   * Feed a browser Float32 PCM iterable through one native VAD stream
   * session. The component/model handle is owned by the caller; this method
   * owns only the callback and native stream-session lifetime.
   */
  stream(
    handle: number,
    audio: AsyncIterable<Float32Array>,
    options: ProtoVADOptions,
  ): AsyncIterable<ProtoVADResult> {
    const module = this.module;
    const required = [
      '_rac_vad_set_stream_proto_callback',
      '_rac_vad_unset_stream_proto_callback',
      '_rac_vad_proto_quiesce',
      '_rac_vad_stream_start_proto',
      '_rac_vad_stream_feed_audio_proto',
      '_rac_vad_stream_stop_proto',
      '_rac_vad_stream_cancel_proto',
    ] as const;
    requireExports(module, 'vad.stream', [...required]);
    if (
      !module.addFunction
      || !module.removeFunction
      || !module.HEAPU8
      || !module.HEAPU32
      || !module._malloc
      || !module._free
    ) {
      throw SDKException.wasmNotLoaded(
        'vad.stream: module missing callback, heap, or allocation helpers',
      );
    }

    const bridge = this.bridge();
    const optionsBytes = VADOptions.encode(options).finish();

    return {
      async *[Symbol.asyncIterator](): AsyncGenerator<ProtoVADResult> {
        const events: ProtoVADStreamEvent[] = [];
        let callbackFailure: Error | null = null;
        const callbackPtr = module.addFunction!((bytesPtr: number, size: number) => {
          if (!bytesPtr || size <= 0) return;
          try {
            const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
            events.push(VADStreamEvent.decode(bytes));
          } catch (error) {
            callbackFailure ??= error instanceof Error
              ? error
              : new Error(String(error));
          }
        }, 'viii');

        const sessionIdPtr = module._malloc!(8);
        if (!sessionIdPtr) {
          module.removeFunction!(callbackPtr);
          throw SDKException.wasmNotLoaded('vad.stream: failed to allocate session id slot');
        }
        module.HEAPU32![sessionIdPtr >>> 2] = 0;
        module.HEAPU32![(sessionIdPtr >>> 2) + 1] = 0;

        let callbackRegistered = false;
        let sessionId = 0n;
        let sourceCompleted = false;
        try {
          const callbackRc = module._rac_vad_set_stream_proto_callback!(
            handle,
            callbackPtr,
            0,
          );
          if (callbackRc !== 0) {
            throw SDKException.fromRACResult(
              callbackRc,
              'rac_vad_set_stream_proto_callback failed',
              { module, logger },
            );
          }
          callbackRegistered = true;

          const startRc = bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
            module._rac_vad_stream_start_proto!(
              handle,
              optionsPtr,
              optionsSize,
              sessionIdPtr,
            )
          ));
          if (startRc !== 0) {
            throw SDKException.fromRACResult(
              startRc,
              'rac_vad_stream_start_proto failed',
              { module, logger },
            );
          }
          sessionId = readWasmUint64(module.HEAPU32!, sessionIdPtr);
          if (sessionId === 0n) {
            throw SDKException.processingFailed(
              'rac_vad_stream_start_proto returned an empty session id',
            );
          }

          for await (const chunk of audio) {
            if (chunk.length === 0) continue;
            const pcmBytes = float32ToPCM16Bytes(chunk);
            const feedRc = bridge.withHeapBytes(pcmBytes, (audioPtr, audioSize) => (
              module._rac_vad_stream_feed_audio_proto!(sessionId, audioPtr, audioSize)
            ));
            if (feedRc !== 0) {
              throw SDKException.fromRACResult(
                feedRc,
                'rac_vad_stream_feed_audio_proto failed',
                { module, logger },
              );
            }
            if (callbackFailure) throw callbackFailure;

            const emitted = events.splice(0, events.length);
            for (const event of emitted) {
              if (
                event.kind === VADStreamEventKind.VAD_STREAM_EVENT_KIND_ERROR
                || event.errorCode !== 0
              ) {
                throw SDKException.fromRACResult(
                  event.errorCode || -1,
                  event.errorMessage || 'VAD stream emitted an error event',
                  { module, logger },
                );
              }
              if (event.result) yield event.result;
            }
          }
          sourceCompleted = true;
        } finally {
          if (sessionId !== 0n) {
            try {
              const rc = sourceCompleted
                ? module._rac_vad_stream_stop_proto!(sessionId)
                : module._rac_vad_stream_cancel_proto!(sessionId);
              if (rc !== 0) {
                logger.warning(
                  `${sourceCompleted ? 'rac_vad_stream_stop_proto' : 'rac_vad_stream_cancel_proto'} `
                  + `returned ${formatRacResult(rc)}`,
                );
              }
            } catch (error) {
              logger.warning(
                `VAD stream session cleanup threw: ${error instanceof Error ? error.message : String(error)}`,
              );
            }
          }
          if (callbackRegistered) {
            try {
              const unsetRc = module._rac_vad_unset_stream_proto_callback!(handle);
              if (unsetRc !== 0) {
                logger.warning(
                  `rac_vad_unset_stream_proto_callback returned ${formatRacResult(unsetRc)}`,
                );
              }
            } finally {
              module._rac_vad_proto_quiesce!();
            }
          }
          module._free!(sessionIdPtr);
          module.removeFunction!(callbackPtr);
        }
      },
    };
  }

  statistics(handle: number): ProtoVADStatistics | null {
    if (!ensureExports(this.module, 'vad.statistics', ['_rac_vad_component_get_statistics_proto'])) {
      return null;
    }
    return this.bridge().callResultProto(
      VADStatistics,
      (outResult) => this.module._rac_vad_component_get_statistics_proto!(handle, outResult),
      'rac_vad_component_get_statistics_proto',
    );
  }

  setActivityHandler(
    handle: number,
    handler: ProtoEventHandler<ProtoSpeechActivityEvent> | null,
  ): boolean {
    if (!ensureExports(this.module, 'vad.setActivityHandler', [
      '_rac_vad_component_set_activity_proto_callback',
    ])) {
      return false;
    }
    if (!this.module.addFunction || !this.module.removeFunction || !this.module.HEAPU8) {
      logger.warning('vad.setActivityHandler: module missing callback/heap helpers');
      return false;
    }

    const previousPtr = adapterState.vadActivityCallbackPtrs.get(handle);
    if (previousPtr) {
      this.module._rac_vad_component_set_activity_proto_callback!(handle, 0, 0);
      this.module.removeFunction(previousPtr);
      adapterState.vadActivityCallbackPtrs.delete(handle);
    }
    if (!handler) return true;

    const callbackPtr = this.module.addFunction((bytesPtr: number, size: number) => {
      if (!bytesPtr || size <= 0) return;
      const bytes = this.module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
      handler(SpeechActivityEvent.decode(bytes));
    }, 'viii');
    const rc = this.module._rac_vad_component_set_activity_proto_callback!(handle, callbackPtr, 0);
    if (rc !== 0) {
      this.module.removeFunction(callbackPtr);
      logger.warning(`rac_vad_component_set_activity_proto_callback returned ${formatRacResult(rc)}`);
      return false;
    }
    adapterState.vadActivityCallbackPtrs.set(handle, callbackPtr);
    return true;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private callLifecycleState(
    feature: string,
    exportName:
      | '_rac_vad_start_lifecycle_proto'
      | '_rac_vad_stop_lifecycle_proto'
      | '_rac_vad_reset_lifecycle_proto',
    functionName: string,
  ): ProtoVADServiceState | null {
    if (!ensureExports(this.module, feature, [exportName])) return null;
    const call = this.module[exportName];
    if (typeof call !== 'function') return null;
    return this.bridge().callResultProto(
      VADServiceState,
      (outResult) => call(outResult),
      functionName,
    );
  }
}

/** Convert browser-native Float32 PCM to the PCM_S16_LE stream ABI. */
function float32ToPCM16Bytes(samples: Float32Array): Uint8Array {
  const buffer = new ArrayBuffer(samples.length * Int16Array.BYTES_PER_ELEMENT);
  const view = new DataView(buffer);
  for (let index = 0; index < samples.length; index += 1) {
    const sample = Math.max(-1, Math.min(1, samples[index] ?? 0));
    const pcm = sample < 0 ? Math.round(sample * 32_768) : Math.round(sample * 32_767);
    view.setInt16(index * Int16Array.BYTES_PER_ELEMENT, pcm, true);
  }
  return new Uint8Array(buffer);
}

/** Encode PCM explicitly as little-endian f32, independent of host byte order. */
function float32ToLittleEndianBytes(samples: Float32Array): Uint8Array {
  const buffer = new ArrayBuffer(samples.length * Float32Array.BYTES_PER_ELEMENT);
  const view = new DataView(buffer);
  for (let index = 0; index < samples.length; index += 1) {
    view.setFloat32(index * Float32Array.BYTES_PER_ELEMENT, samples[index] ?? 0, true);
  }
  return new Uint8Array(buffer);
}

function lifecycleRequestId(): string {
  if (typeof globalThis.crypto?.randomUUID === 'function') {
    return globalThis.crypto.randomUUID();
  }
  return `vad-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}
