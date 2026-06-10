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
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  streamCallback,
  withOptionalCallback,
  type ModalityProtoModule,
  type ProtoEventHandler,
} from './ProtoAdapterTypes';

export class VLMProtoAdapter {
  static tryDefault(): VLMProtoAdapter | null {
    const mod = adapterState.modalitySlots.vlm;
    return mod ? new VLMProtoAdapter(mod) : null;
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

  async processAsync(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): Promise<ProtoVLMResult | null> {
    if (!ensureExports(this.module, 'vlm.process', ['_rac_vlm_process_proto'])) {
      return null;
    }
    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode(options).finish();
    const bridge = this.bridge();
    return bridge.withHeapBytesAsync(imageBytes, (imagePtr, imageSize) => (
      bridge.withHeapBytesAsync(optionsBytes, (optionsPtr, optionsSize) => (
        bridge.callResultProtoAsync(
          VLMResult,
          (outResult) => this.callProcess(
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

  streamEvents(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): AsyncIterable<ProtoSDKEvent> {
    const imageBytes = VLMImage.encode(image).finish();
    const optionsBytes = VLMGenerationOptions.encode({ ...options, streamingEnabled: true }).finish();
    // T6.1: prefer Worker path when available; otherwise main-thread MVP.
    const offscreen = OffscreenRuntimeBridge.tryGet();
    if (offscreen != null) {
      return offscreen.getStreamIterator(
        {
          kind: 'stream.vlm.process',
          handle,
          imageBytes,
          promptBytes: optionsBytes,
        },
        SDKEvent,
        { onCancel: () => { this.cancel(handle); } },
      );
    }
    if (!ensureExports(this.module, 'vlm.processImageStream', ['_rac_vlm_process_stream_proto'])) {
      return emptyStream();
    }
    const bridge = this.bridge();
    return streamCallback(
      this.module,
      SDKEvent,
      'rac_vlm_process_stream_proto',
      (callbackPtr) => {
        const result = bridge.withHeapBytes(imageBytes, (imagePtr, imageSize) => (
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
        ));
        return result ? 0 : -903;
      },
      undefined,
      () => {
        this.cancel(handle);
      },
      true,
    );
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

  private callProcess(
    handle: number,
    imagePtr: number,
    imageSize: number,
    optionsPtr: number,
    optionsSize: number,
    outResult: number,
  ): number | Promise<number> {
    if (typeof this.module.ccall === 'function') {
      const result = this.module.ccall(
        'rac_vlm_process_proto',
        'number',
        ['number', 'number', 'number', 'number', 'number', 'number'],
        [handle, imagePtr, imageSize, optionsPtr, optionsSize, outResult],
        { async: true },
      );
      return result instanceof Promise
        ? result.then((value) => Number(value))
        : Number(result);
    }
    return this.module._rac_vlm_process_proto!(
      handle,
      imagePtr,
      imageSize,
      optionsPtr,
      optionsSize,
      outResult,
    );
  }
}

function emptyStream<T>(): AsyncIterable<T> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<T> {
      return {
        next(): Promise<IteratorResult<T>> {
          return Promise.resolve({ value: undefined as T, done: true });
        },
      };
    },
  };
}
