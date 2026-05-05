import {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
  type VLMGenerationOptions as ProtoVLMGenerationOptions,
  type VLMImage as ProtoVLMImage,
  type VLMResult as ProtoVLMResult,
} from '@runanywhere/proto-ts/vlm_options';
import {
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  withOptionalCallback,
  type ModalityProtoModule,
  type ProtoEventHandler,
} from './ProtoAdapterTypes';

export class VLMProtoAdapter {
  static tryDefault(): VLMProtoAdapter | null {
    return adapterState.defaultModule
      ? new VLMProtoAdapter(adapterState.defaultModule)
      : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoVLM(): boolean {
    return missingExports(this.module, [
      '_rac_vlm_process_proto',
      '_rac_vlm_process_stream_proto',
      '_rac_vlm_cancel_proto',
    ]).length === 0;
  }

  process(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): ProtoVLMResult | null {
    if (!ensureExports(this.module, 'vlm.process', ['_rac_vlm_process_proto'])) {
      return null;
    }
    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode(options).finish();
    const bridge = this.bridge();
    return bridge.withHeapBytes(imageBytes, (imagePtr, imageSize) => (
      bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProto(
          VLMResult,
          (outResult) => this.module._rac_vlm_process_proto!(
            handle,
            imagePtr,
            imageSize,
            optionsPtr,
            optionsSize,
            outResult,
          ),
          'rac_vlm_process_proto',
        )
      ))
    ));
  }

  processStream(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
    onEvent: ProtoEventHandler<ProtoSDKEvent> | null,
  ): ProtoVLMResult | null {
    if (!ensureExports(this.module, 'vlm.processStream', ['_rac_vlm_process_stream_proto'])) {
      return null;
    }
    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode(options).finish();
    const bridge = this.bridge();
    return withOptionalCallback(this.module, SDKEvent, onEvent, 'rac_vlm_process_stream_proto', (callbackPtr) => (
      bridge.withHeapBytes(imageBytes, (imagePtr, imageSize) => (
        bridge.withHeapBytes(optionsBytes, (optionsPtr, optionsSize) => (
          bridge.callResultProto(
            VLMResult,
            (outResult) => this.module._rac_vlm_process_stream_proto!(
              handle,
              imagePtr,
              imageSize,
              optionsPtr,
              optionsSize,
              callbackPtr,
              0,
              outResult,
            ),
            'rac_vlm_process_stream_proto',
          )
        ))
      ))
    ));
  }

  cancel(handle: number): boolean {
    if (!ensureExports(this.module, 'vlm.cancel', ['_rac_vlm_cancel_proto'])) return false;
    const rc = this.module._rac_vlm_cancel_proto!(handle);
    if (rc !== 0) logger.warning(`rac_vlm_cancel_proto returned ${formatRacResult(rc)}`);
    return rc === 0;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }
}
