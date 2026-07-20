import {
  VLMGenerationRequest,
  VLMResult,
  VLMStreamEvent,
  type VLMGenerationOptions as ProtoVLMGenerationOptions,
  type VLMImage as ProtoVLMImage,
  type VLMResult as ProtoVLMResult,
  type VLMStreamEvent as ProtoVLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge.js';
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import {
  getLlamaBackendWorkerDeadReason,
  hasBackendWorkerOwnedModels,
  mustUseLlamaBackendWorker,
} from '../runtime/BackendWorkerModelOwnership.js';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import { SDKException } from '../Foundation/SDKException.js';
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
      '_rac_vlm_generate_proto',
      '_rac_vlm_stream_proto',
      '_rac_vlm_cancel_lifecycle_proto',
    ]).length === 0;
  }

  async process(
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): Promise<ProtoVLMResult | null> {
    const requestBytes = VLMGenerationRequest.encode(
      VLMGenerationRequest.fromPartial({ images: [image], options }),
    ).finish();
    const host = getActiveBackendWorkerHost('llamacpp');
    const useWorker = mustUseLlamaBackendWorker()
      || (
        host != null
        && host.diagnostics.executionContext === 'worker'
        && hasBackendWorkerOwnedModels()
      );
    if (useWorker) {
      if (!host || host.diagnostics.executionContext !== 'worker') {
        throw SDKException.backendNotAvailable(
          'vlm.process',
          getLlamaBackendWorkerDeadReason()
            ?? 'BackendWorker is required for VLM inference; main-thread fallback is disabled.',
        );
      }
      const response = await host.infer('vlm.generate', { requestBytes }) as {
        resultBytes?: Uint8Array;
      };
      if (!response?.resultBytes) return null;
      return VLMResult.decode(response.resultBytes);
    }
    if (!ensureExports(this.module, 'vlm.process', ['_rac_vlm_generate_proto'])) {
      return null;
    }
    const bridge = this.bridge();
    return bridge.withHeapBytesAsync(requestBytes, (requestPtr, requestSize) => (
      bridge.callResultProtoAsync(
        VLMResult,
        (outResult) => this.callProcess(requestPtr, requestSize, outResult),
        'rac_vlm_generate_proto',
      )
    ));
  }

  async processAsync(
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): Promise<ProtoVLMResult | null> {
    return this.process(image, options);
  }

  /**
   * Stream typed VLMStreamEvents from the lifecycle-owned VLM model via
   * `rac_vlm_stream_proto` (STARTED → TOKEN* → exactly one terminal
   * COMPLETED/ERROR; COMPLETED carries the full VLMResult). The canonical
   * cross-SDK streaming shape — serialized VLMGenerationRequest in, no
   * handle, no out-result buffer.
   */
  streamEvents(
    image: ProtoVLMImage,
    options: ProtoVLMGenerationOptions,
  ): AsyncIterable<ProtoVLMStreamEvent> {
    const requestBytes = VLMGenerationRequest.encode(
      VLMGenerationRequest.fromPartial({
        images: [image],
        options: { ...options, streamingEnabled: true },
      }),
    ).finish();
    const host = getActiveBackendWorkerHost('llamacpp');
    const useWorker = mustUseLlamaBackendWorker()
      || (
        host != null
        && host.diagnostics.executionContext === 'worker'
        && hasBackendWorkerOwnedModels()
      );
    if (useWorker) {
      if (!host || host.diagnostics.executionContext !== 'worker') {
        throw SDKException.backendNotAvailable(
          'vlm.processImageStream',
          getLlamaBackendWorkerDeadReason()
            ?? 'BackendWorker is required for VLM streaming; main-thread fallback is disabled.',
        );
      }
      const events = host.stream('vlm.generate', { requestBytes });
      return {
        [Symbol.asyncIterator]: (): AsyncIterator<ProtoVLMStreamEvent> => {
          const iterator = events[Symbol.asyncIterator]();
          return {
            async next(): Promise<IteratorResult<ProtoVLMStreamEvent>> {
              const item = await iterator.next();
              if (item.done) return { value: undefined, done: true };
              const payload = item.value;
              const bytes = payload instanceof Uint8Array
                ? payload
                : (payload as { eventBytes?: Uint8Array })?.eventBytes;
              if (!bytes) {
                return { value: VLMStreamEvent.fromPartial({}), done: false };
              }
              return { value: VLMStreamEvent.decode(bytes), done: false };
            },
            async return(): Promise<IteratorResult<ProtoVLMStreamEvent>> {
              await iterator.return?.();
              return { value: undefined, done: true };
            },
          };
        },
      };
    }
    // Legacy offscreen StreamWorker path when BackendWorker is not active.
    const offscreen = OffscreenRuntimeBridge.tryGet();
    if (offscreen != null) {
      return offscreen.getStreamIterator(
        {
          kind: 'stream.vlm.generate',
          requestBytes,
        },
        VLMStreamEvent,
        { onCancel: () => { this.cancel(); } },
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
        this.cancel();
      },
      // Swift parity (CppBridge+ModalityProtoABI.swift VLM stream): no
      // synthetic terminal event — a non-success rc finishes the stream
      // silently.
      undefined,
      true,
    );
  }

  cancel(): boolean {
    const host = getActiveBackendWorkerHost('llamacpp');
    if (
      host
      && host.diagnostics.executionContext === 'worker'
      && (mustUseLlamaBackendWorker() || hasBackendWorkerOwnedModels())
    ) {
      host.cancelActiveStreams();
      return true;
    }
    if (!ensureExports(this.module, 'vlm.cancel', ['_rac_vlm_cancel_lifecycle_proto'])) {
      return false;
    }
    const bytes = this.bridge().readResultProto(
      (outEvent) => this.module._rac_vlm_cancel_lifecycle_proto!(outEvent),
      'rac_vlm_cancel_lifecycle_proto',
    );
    return bytes !== null;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private callProcess(
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ): Promise<number> {
    return callEmscriptenAsyncNumber(
      this.module,
      'rac_vlm_generate_proto',
      ['number', 'number', 'number'],
      [requestPtr, requestSize, outResult],
      () => this.module._rac_vlm_generate_proto!(requestPtr, requestSize, outResult),
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
