import {
  LLMGenerateRequest,
  LLMStreamEvent,
  type LLMGenerateRequest as ProtoLLMGenerateRequest,
  type LLMStreamEvent as ProtoLLMStreamEvent,
} from '@runanywhere/proto-ts/llm_service';
import {
  LLMGenerationResult,
  type LLMGenerationResult as ProtoLLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
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

  generate(request: ProtoLLMGenerateRequest): ProtoLLMGenerationResult | null {
    if (!this.ensureExports('llm.generate', ['_rac_llm_generate_proto'])) return null;
    return this.bridge().withEncodedRequest(
      request,
      LLMGenerateRequest,
      LLMGenerationResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_llm_generate_proto!(requestPtr, requestSize, outResult)
      ),
      'rac_llm_generate_proto',
    );
  }

  generateStream(request: ProtoLLMGenerateRequest): AsyncIterable<ProtoLLMStreamEvent> {
    const encoded = LLMGenerateRequest.encode({ ...request, streamingEnabled: true }).finish();
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
        this.bridge().withHeapBytes(encoded, (requestPtr, requestSize) => (
          this.module._rac_llm_generate_stream_proto!(
            requestPtr,
            requestSize,
            callbackPtr,
            0,
          )
        ))
      ),
      (event) => event.isFinal,
      () => {
        this.cancel();
      },
    );
  }

  cancel(): ProtoSDKEvent | null {
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
