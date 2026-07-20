import {
  LLMGenerateRequest,
  LLMStreamEvent,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import {
  LLMGenerationOptions,
  LLMGenerationResult,
  type LLMGenerationResult as ProtoLLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { OffscreenRuntimeBridge } from '../runtime/OffscreenRuntimeBridge.js';
import { getActiveBackendWorkerHost } from '../runtime/BackendWorkerHost.js';
import { hasBackendWorkerOwnedModels } from '../runtime/BackendWorkerModelOwnership.js';
import { callEmscriptenAsyncNumber } from '../runtime/EmscriptenAsync.js';
import { ProtoWasmBridge } from '../runtime/ProtoWasm.js';
import { SDKException } from '../Foundation/SDKException.js';
import {
  adapterState,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  requireExports,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';

export class LLMProtoAdapter {
  static tryDefault(): LLMProtoAdapter | null {
    const mod = adapterState.modalitySlots.llm;
    return mod ? new LLMProtoAdapter(mod) : null;
  }

  constructor(private readonly module: ModalityProtoModule) {}

  supportsProtoLLM(): boolean {
    return this.missingExports([
      '_rac_llm_generate_proto',
      '_rac_llm_generate_stream_proto',
      '_rac_llm_cancel_proto',
    ]).length === 0;
  }

  async generate(request: ProtoLLMGenerateRequest): Promise<ProtoLLMGenerationResult | null> {
    const host = getActiveBackendWorkerHost();
    if (host && hasBackendWorkerOwnedModels()) {
      const encoded = LLMGenerateRequest.encode(request).finish();
      const response = await host.infer('llm.generate', { requestBytes: encoded }) as {
        resultBytes?: Uint8Array;
      };
      if (!response?.resultBytes) return null;
      return LLMGenerationResult.decode(response.resultBytes);
    }
    if (!this.ensureExports('llm.generate', ['_rac_llm_generate_proto'])) return null;
    return this.bridge().withEncodedRequestAsync(
      request,
      LLMGenerateRequest,
      LLMGenerationResult,
      (requestPtr, requestSize, outResult) => this.callGenerate(
        requestPtr,
        requestSize,
        outResult,
      ),
      'rac_llm_generate_proto',
    );
  }

  generateStream(request: ProtoLLMGenerateRequest): AsyncIterable<ProtoLLMStreamEvent> {
    const options = request.options;
    const encoded = LLMGenerateRequest.encode({
      ...request,
      options: LLMGenerationOptions.fromPartial({
        maxTokens: options?.maxTokens ?? 100,
        temperature: options?.temperature ?? 0.8,
        topP: options?.topP ?? 1.0,
        topK: options?.topK ?? 0,
        repetitionPenalty: options?.repetitionPenalty ?? 1.0,
        ...options,
        streamingEnabled: true,
      }),
    }).finish();

    // Prefer the model-owning BackendWorker when it holds the loaded LLM.
    const host = getActiveBackendWorkerHost();
    if (host && hasBackendWorkerOwnedModels()) {
      const events = host.stream('llm.generate', { requestBytes: encoded });
      return {
        [Symbol.asyncIterator]: (): AsyncIterator<ProtoLLMStreamEvent> => {
          const iterator = events[Symbol.asyncIterator]();
          return {
            async next(): Promise<IteratorResult<ProtoLLMStreamEvent>> {
              const item = await iterator.next();
              if (item.done) return { value: undefined, done: true };
              const payload = item.value;
              const bytes = payload instanceof Uint8Array
                ? payload
                : (payload as { eventBytes?: Uint8Array })?.eventBytes;
              if (!bytes) {
                return { value: LLMStreamEvent.fromPartial({ isFinal: false }), done: false };
              }
              return { value: LLMStreamEvent.decode(bytes), done: false };
            },
            async return(): Promise<IteratorResult<ProtoLLMStreamEvent>> {
              await iterator.return?.();
              return { value: undefined, done: true };
            },
          };
        },
      };
    }

    // T6.1: prefer the Worker path when a streamWorkerFactory is
    // registered (and `streamingMode !== 'main'`); transparently fall
    // back to the existing main-thread `streamCallback` MVP otherwise.
    const offscreen = OffscreenRuntimeBridge.tryGet();
    if (offscreen != null) {
      return offscreen.getStreamIterator(
        { kind: 'stream.llm.generate', handle: 0, requestBytes: encoded },
        LLMStreamEvent,
        {
          stopWhen: (event) => event.isFinal,
          onCancel: () => { this.cancel(); },
        },
      );
    }
    this.requireExports('llm.generateStream', ['_rac_llm_generate_stream_proto']);
    return streamCallback(
      this.module,
      LLMStreamEvent,
      'rac_llm_generate_stream_proto',
      (callbackPtr) => (
        this.bridge().withHeapBytesAsync(encoded, (requestPtr, requestSize) => (
          this.callGenerateStream(
            requestPtr,
            requestSize,
            callbackPtr,
          )
        ))
      ),
      (event) => event.isFinal,
      () => {
        this.cancel();
      },
      // Swift parity (ModalityProtoABI+Generated.swift:308-316): non-success
      // rc synthesizes a terminal error event instead of rejecting the
      // iterator.
      (rc) => LLMStreamEvent.fromPartial({
        isFinal: true,
        finishReason: 'error',
        errorCode: rc,
        errorMessage: SDKException.fromRACResult(
          rc,
          `LLM stream failed: ${rc}`,
          { module: this.module, logger },
        ).message,
      }),
    );
  }

  cancel(): ProtoSDKEvent | null {
    const host = getActiveBackendWorkerHost();
    if (host && hasBackendWorkerOwnedModels()) {
      host.cancelActiveStreams();
      return SDKEvent.fromPartial({});
    }
    if (!this.ensureExports('llm.cancel', ['_rac_llm_cancel_proto'])) return null;
    return this.bridge().callResultProto(
      SDKEvent,
      (outEvent) => this.module._rac_llm_cancel_proto!(outEvent),
      'rac_llm_cancel_proto',
    );
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private callGenerate(
    requestPtr: number,
    requestSize: number,
    outResult: number,
  ): Promise<number> {
    return callEmscriptenAsyncNumber(
      this.module,
      'rac_llm_generate_proto',
      ['number', 'number', 'number'],
      [requestPtr, requestSize, outResult],
      () => this.module._rac_llm_generate_proto!(requestPtr, requestSize, outResult),
    );
  }

  private callGenerateStream(
    requestPtr: number,
    requestSize: number,
    callbackPtr: number,
  ): Promise<number> {
    return callEmscriptenAsyncNumber(
      this.module,
      'rac_llm_generate_stream_proto',
      ['number', 'number', 'number', 'number'],
      [requestPtr, requestSize, callbackPtr, 0],
      () => this.module._rac_llm_generate_stream_proto!(
        requestPtr,
        requestSize,
        callbackPtr,
        0,
      ),
    );
  }

  private ensureExports(operation: string, required: Array<keyof ModalityProtoModule>): boolean {
    return ensureExports(this.module, operation, required);
  }

  private requireExports(operation: string, required: Array<keyof ModalityProtoModule>): void {
    requireExports(this.module, operation, required);
  }

  private missingExports(required: Array<keyof ModalityProtoModule>): string[] {
    return missingExports(this.module, required);
  }
}
