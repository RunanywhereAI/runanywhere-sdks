import {
  VLMGenerationOptions,
  VLMGenerationRequest,
  VLMImage,
  VLMResult,
  VLMStreamEvent,
  type VLMGenerationOptions as ProtoVLMGenerationOptions,
  type VLMImage as ProtoVLMImage,
  type VLMResult as ProtoVLMResult,
  type VLMStreamEvent as ProtoVLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge.js';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { formatRacResult, ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

export class VLMProtoAdapter {
  static tryDefault(): VLMProtoAdapter | null {
    const mod = adapterState.modalitySlots.vlm;
    return mod ? new VLMProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoVLM(): boolean {
    return missingExports(this.module, [
      '_rac_vlm_process_proto',
      '_rac_vlm_stream_proto',
      '_rac_vlm_cancel_proto',
    ]).length === 0;
  }

  async process(
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

  async processAsync(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): Promise<ProtoVLMResult | null> {
    return this.process(handle, image, options);
  }

  /**
   * Stream typed VLMStreamEvents from the lifecycle-owned VLM model via
   * `rac_vlm_stream_proto` (STARTED → TOKEN* → exactly one terminal
   * COMPLETED/ERROR; COMPLETED carries the full VLMResult). The canonical
   * cross-SDK streaming shape — serialized VLMGenerationRequest in, no
   * handle, no out-result buffer. `handle` is retained only for cancel
   * routing (0 falls back to the lifecycle-owned service).
   */
  streamEvents(
    handle: number,
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): AsyncIterable<ProtoVLMStreamEvent> {
    const requestBytes = VLMGenerationRequest.encode(
      VLMGenerationRequest.fromPartial({
        images: [image],
        options: { ...options, streamingEnabled: true },
      }),
    ).finish();
    // T6.1: prefer Worker path when available; otherwise main-thread MVP.
    const offscreen = OffscreenRuntimeBridge.tryGet();
    if (offscreen != null) {
      return offscreen.getStreamIterator(
        {
          kind: 'stream.vlm.generate',
          requestBytes,
        },
        VLMStreamEvent,
        { onCancel: () => { this.cancel(handle); } },
      );
    }
    if (!ensureExports(this.module, 'vlm.processImageStream', ['_rac_vlm_stream_proto'])) {
      return emptyStream();
    }
    const bridge = this.bridge();
    return streamCallback(
      this.module,
      VLMStreamEvent,
      'rac_vlm_stream_proto',
      (callbackPtr) => (
        bridge.withHeapBytesAsync(requestBytes, (requestPtr, requestSize) => (
          this.callStream(requestPtr, requestSize, callbackPtr)
        ))
      ),
      undefined,
      () => {
        this.cancel(handle);
      },
      // Swift parity (CppBridge+ModalityProtoABI.swift VLM stream): no
      // synthetic terminal event — a non-success rc finishes the stream
      // silently.
      undefined,
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
  ): Promise<number> {
    return callEmscriptenAsyncNumber(
      this.module,
      'rac_vlm_process_proto',
      ['number', 'number', 'number', 'number', 'number', 'number'],
      [handle, imagePtr, imageSize, optionsPtr, optionsSize, outResult],
      () => this.module._rac_vlm_process_proto!(
        handle,
        imagePtr,
        imageSize,
        optionsPtr,
        optionsSize,
        outResult,
      ),
    );
  }

  private callStream(
    requestPtr: number,
    requestSize: number,
    callbackPtr: number,
  ): Promise<number> {
    return callEmscriptenAsyncNumber(
      this.module,
      'rac_vlm_stream_proto',
      ['number', 'number', 'number', 'number'],
      [requestPtr, requestSize, callbackPtr, 0],
      () => this.module._rac_vlm_stream_proto!(requestPtr, requestSize, callbackPtr, 0),
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
