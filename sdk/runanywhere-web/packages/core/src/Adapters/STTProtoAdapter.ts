import {
  STTOptions,
  STTOutput,
  STTPartialResult,
  type STTOptions as ProtoSTTOptions,
  type STTOutput as ProtoSTTOutput,
  type STTPartialResult as ProtoSTTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  requireExports,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes';

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
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
