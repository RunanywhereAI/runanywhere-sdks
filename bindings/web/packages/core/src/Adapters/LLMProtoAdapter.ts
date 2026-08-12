import {
  LLMGenerateRequest,
  LLMStreamEvent,
  LLMStreamEventKind,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import {
  LLMGenerationOptions,
  LLMGenerationResult,
  type LLMGenerationResult as ProtoLLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import { FinishReason } from '@runanywhere/proto-ts/finish_reason';
import { lLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/llm_options_convenience';
import {
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
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
  decodeWorkerInferResult,
  decodeWorkerStream,
  ensureExports,
  missingExports,
  modalityLogger as logger,
  requireExports,
  streamCallback,
  type ModalityProtoModule,
} from './ProtoAdapterTypes.js';
import type { BackendWorkerHost } from '../runtime/BackendWorkerHost.js';

/**
 * Worker path is required. After a crash the host can recreate the
 * DedicatedWorker, but model weights are gone — ask for an explicit reload
 * instead of a vague "Backend not available" / sticky dead state.
 */
export function requireLlamaWorkerHost(
  host: BackendWorkerHost | null,
  operation: string,
): BackendWorkerHost {
  if (!host || host.diagnostics.executionContext !== 'worker') {
    throw SDKException.backendNotAvailable(
      operation,
      getLlamaBackendWorkerDeadReason()
        ?? 'BackendWorker is required for LLM inference; main-thread fallback is disabled.',
    );
  }
  const dead = getLlamaBackendWorkerDeadReason();
  if (dead && !hasBackendWorkerOwnedModels('llamacpp')) {
    throw SDKException.backendNotAvailable(
      operation,
      `${dead} Reload the language model to continue.`,
    );
  }
  return host;
}

/**
 * `LLMStreamEvent` has no `isFinal` boolean; the terminal discriminator is
 * `eventKind === COMPLETED | ERROR`.
 */
function isTerminalLLMStreamEvent(event: ProtoLLMStreamEvent): boolean {
  return event.eventKind === LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED
    || event.eventKind === LLMStreamEventKind.LLM_STREAM_EVENT_KIND_ERROR;
}

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
    const host = getActiveBackendWorkerHost('llamacpp');
    if (mustUseLlamaBackendWorker()) {
      const workerHost = requireLlamaWorkerHost(host, 'llm.generate');
      const encoded = LLMGenerateRequest.encode(request).finish();
      const response = await workerHost.infer('llm.generate', { requestBytes: encoded });
      return decodeWorkerInferResult(response, LLMGenerationResult);
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
    const encoded = LLMGenerateRequest.encode({
      ...request,
      options: LLMGenerationOptions.fromPartial({
        ...lLMGenerationOptionsDefaults(),
        ...request.options,
      }),
    }).finish();

    // Prefer the model-owning BackendWorker when it holds the loaded LLM.
    const host = getActiveBackendWorkerHost('llamacpp');
    if (mustUseLlamaBackendWorker()) {
      const workerHost = requireLlamaWorkerHost(host, 'llm.generateStream');
      return decodeWorkerStream(
        workerHost.stream('llm.generate', { requestBytes: encoded }),
        LLMStreamEvent,
      );
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
          stopWhen: isTerminalLLMStreamEvent,
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
      isTerminalLLMStreamEvent,
      () => {
        this.cancel();
      },
      // Swift parity (ModalityProtoABI+Generated.swift:308-316): non-success
      // rc synthesizes a terminal error event instead of rejecting the
      // iterator.
      (rc) => LLMStreamEvent.fromPartial({
        eventKind: LLMStreamEventKind.LLM_STREAM_EVENT_KIND_ERROR,
        finishReason: FinishReason.FINISH_REASON_ERROR,
        error: SDKException.fromRACResult(
          rc,
          `LLM stream failed: ${rc}`,
          { module: this.module, logger },
        ).proto,
      }),
    );
  }

  cancel(): ProtoSDKEvent | null {
    const host = getActiveBackendWorkerHost('llamacpp');
    if (
      host
      && host.diagnostics.executionContext === 'worker'
      && mustUseLlamaBackendWorker()
    ) {
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
