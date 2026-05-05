import {
  TTSOptions,
  TTSOutput,
  TTSVoiceInfo,
  type TTSOptions as ProtoTTSOptions,
  type TTSOutput as ProtoTTSOutput,
  type TTSVoiceInfo as ProtoTTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  collectCallback,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  requireExports,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes';

export class TTSProtoAdapter {
  static tryDefault(): TTSProtoAdapter | null {
    return adapterState.defaultModule
      ? new TTSProtoAdapter(adapterState.defaultModule)
      : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoTTS(): boolean {
    return missingExports(this.module, [
      '_rac_tts_component_list_voices_proto',
      '_rac_tts_component_synthesize_proto',
      '_rac_tts_component_synthesize_stream_proto',
    ]).length === 0;
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
    requireExports(this.module, 'tts.synthesizeStream', [
      '_rac_tts_component_synthesize_stream_proto',
    ]);
    const optionsBytes = TTSOptions.encode(options).finish();
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
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
