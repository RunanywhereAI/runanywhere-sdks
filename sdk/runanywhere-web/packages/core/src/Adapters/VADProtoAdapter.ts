import {
  SpeechActivityEvent,
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
  type SpeechActivityEvent as ProtoSpeechActivityEvent,
  type VADConfiguration as ProtoVADConfiguration,
  type VADOptions as ProtoVADOptions,
  type VADResult as ProtoVADResult,
  type VADStatistics as ProtoVADStatistics,
} from '@runanywhere/proto-ts/vad_options';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  type ModalityProtoModule,
  type ProtoEventHandler,
} from './ProtoAdapterTypes';

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
}
