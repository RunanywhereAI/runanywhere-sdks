import type { LoRAState as ProtoLoRAState } from '@runanywhere/proto-ts/lora_options';
import { SDKException } from '../Foundation/SDKException';
import { SDKLogger } from '../Foundation/SDKLogger';
import {
  formatRacResult,
  ProtoWasmBridge,
  type ProtoCodec,
  type ProtoWasmModule,
} from '../runtime/ProtoWasm';

/**
 * Shared module-scoped logger for the modality proto adapters. Every
 * per-modality adapter file reuses this identity so log category strings
 * stay uniform across the split.
 */
export const modalityLogger = new SDKLogger('ModalityProtoAdapter');

export type CallbackSignature = 'viii' | 'iiii';
export type CallbackResult = void | number;
export type CallbackFn = (...args: number[]) => CallbackResult;

export interface ModalityProtoModule extends ProtoWasmModule {
  HEAPF32?: Float32Array;
  addFunction?(fn: CallbackFn, signature: string): number;
  removeFunction?(ptr: number): void;

  _rac_llm_generate_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_llm_generate_stream_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_llm_cancel_proto?(outEvent: number): number;

  _rac_stt_component_transcribe_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_stt_component_transcribe_stream_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_tts_component_list_voices_proto?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_tts_component_synthesize_proto?(
    handle: number,
    text: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_tts_component_synthesize_stream_proto?(
    handle: number,
    text: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_vad_component_configure_proto?(
    handle: number,
    configBytes: number,
    configSize: number,
  ): number;
  _rac_vad_component_process_proto?(
    handle: number,
    samples: number,
    numSamples: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_vad_component_get_statistics_proto?(
    handle: number,
    outResult: number,
  ): number;
  _rac_vad_component_set_activity_proto_callback?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_voice_agent_initialize_proto?(
    handle: number,
    configBytes: number,
    configSize: number,
    outComponentStates: number,
  ): number;
  _rac_voice_agent_component_states_proto?(
    handle: number,
    outComponentStates: number,
  ): number;
  _rac_voice_agent_process_voice_turn_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    outResult: number,
  ): number;
  _rac_voice_agent_set_proto_callback?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_vlm_process_proto?(
    handle: number,
    imageBytes: number,
    imageSize: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_vlm_process_stream_proto?(
    handle: number,
    imageBytes: number,
    imageSize: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
    outResult: number,
  ): number;
  _rac_vlm_cancel_proto?(handle: number): number;

  _rac_embeddings_embed_batch_proto?(
    handle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;

  _rac_diffusion_generate_proto?(
    handle: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  _rac_diffusion_generate_with_progress_proto?(
    handle: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
    outResult: number,
  ): number;
  _rac_diffusion_cancel_proto?(handle: number): number;

  _rac_rag_session_create_proto?(
    configBytes: number,
    configSize: number,
    outSession: number,
  ): number;
  _rac_rag_session_destroy_proto?(session: number): void;
  _rac_rag_ingest_proto?(
    session: number,
    documentBytes: number,
    documentSize: number,
    outStats: number,
  ): number;
  _rac_rag_query_proto?(
    session: number,
    queryBytes: number,
    querySize: number,
    outResult: number,
  ): number;
  _rac_rag_clear_proto?(session: number, outStats: number): number;
  _rac_rag_stats_proto?(session: number, outStats: number): number;

  _rac_get_lora_registry?(): number;
  _rac_lora_register_proto?(
    registry: number,
    entryBytes: number,
    entrySize: number,
    outEntry: number,
  ): number;
  _rac_lora_catalog_list_proto?(
    registry: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_catalog_query_proto?(
    registry: number,
    queryBytes: number,
    querySize: number,
    outResult: number,
  ): number;
  _rac_lora_catalog_get_proto?(
    registry: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_catalog_mark_download_completed_proto?(
    registry: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_compatibility_proto?(
    llmComponent: number,
    configBytes: number,
    configSize: number,
    outResult: number,
  ): number;
  _rac_lora_apply_proto?(
    llmComponent: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_remove_proto?(
    llmComponent: number,
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;
  _rac_lora_list_proto?(
    llmComponent: number,
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;
  _rac_lora_state_proto?(
    llmComponent: number,
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;

  _rac_structured_output_parse_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
}

export type ProtoEventHandler<T> = (event: T) => void;

// ---------------------------------------------------------------------------
// Shared mutable state used by `ModalityProtoAdapter.setDefaultModule` and
// `VADProtoAdapter.setActivityHandler`. Lives in one module so the per-
// modality files don't drift out of sync.
// ---------------------------------------------------------------------------

export const adapterState = {
  defaultModule: null as ModalityProtoModule | null,
  vadActivityCallbackPtrs: new Map<number, number>(),
};

export function emptyLoRAState(): ProtoLoRAState {
  return {
    loadedAdapters: [],
    hasActiveAdapters: false,
    errorCode: 0,
  };
}

export function streamCallback<T>(
  module: ModalityProtoModule,
  codec: ProtoCodec<T>,
  functionName: string,
  call: (callbackPtr: number) => number,
  stopWhen?: (event: T) => boolean,
  onCancel?: () => void,
  callbackReturnsBool = false,
): AsyncIterable<T> {
  return {
    [Symbol.asyncIterator](): AsyncIterator<T> {
      const queue: T[] = [];
      const waiters: Array<{
        resolve(value: IteratorResult<T>): void;
        reject(reason?: unknown): void;
      }> = [];
      let callbackPtr = 0;
      let started = false;
      let finished = false;
      let callActive = false;

      const cleanup = (): void => {
        if (callbackPtr && !callActive) {
          module.removeFunction?.(callbackPtr);
          callbackPtr = 0;
        }
      };

      const finish = (): void => {
        if (finished) return;
        finished = true;
        while (waiters.length > 0) {
          waiters.shift()!.resolve({ value: undefined as T, done: true });
        }
        cleanup();
      };

      const fail = (error: unknown): void => {
        if (finished) return;
        finished = true;
        while (waiters.length > 0) {
          waiters.shift()!.reject(error);
        }
        cleanup();
      };

      const emit = (event: T): void => {
        if (finished) return;
        if (waiters.length > 0) {
          waiters.shift()!.resolve({ value: event, done: false });
        } else {
          queue.push(event);
        }
        if (stopWhen?.(event)) finish();
      };

      const start = (): void => {
        if (started) return;
        started = true;
        if (!module.addFunction || !module.removeFunction || !module.HEAPU8) {
          fail(SDKException.wasmNotLoaded(`${functionName}: module missing callback helpers`));
          return;
        }

        callbackPtr = module.addFunction((bytesPtr: number, size: number): CallbackResult => {
          if (!bytesPtr || size <= 0) return callbackReturnsBool ? 1 : undefined;
          try {
            const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
            emit(codec.decode(bytes));
            return callbackReturnsBool ? 1 : undefined;
          } catch (error) {
            fail(error);
            return callbackReturnsBool ? 0 : undefined;
          }
        }, callbackSignature(callbackReturnsBool));

        callActive = true;
        try {
          const rc = call(callbackPtr);
          if (rc !== 0) {
            fail(SDKException.fromRACResult(rc, functionName));
            return;
          }
          if (!finished) finish();
        } catch (error) {
          fail(error);
        } finally {
          callActive = false;
          cleanup();
        }
      };

      return {
        next(): Promise<IteratorResult<T>> {
          start();
          if (queue.length > 0) {
            return Promise.resolve({ value: queue.shift()!, done: false });
          }
          if (finished) {
            return Promise.resolve({ value: undefined as T, done: true });
          }
          return new Promise((resolve, reject) => {
            waiters.push({ resolve, reject });
          });
        },
        return(): Promise<IteratorResult<T>> {
          try {
            onCancel?.();
          } finally {
            finish();
          }
          return Promise.resolve({ value: undefined as T, done: true });
        },
      };
    },
  };
}

export function collectCallback<T>(
  module: ModalityProtoModule,
  codec: ProtoCodec<T>,
  functionName: string,
  call: (callbackPtr: number) => number,
): T[] | null {
  if (!module.addFunction || !module.removeFunction || !module.HEAPU8) {
    modalityLogger.warning(`${functionName}: module missing callback helpers`);
    return null;
  }
  const values: T[] = [];
  const callbackPtr = module.addFunction((bytesPtr: number, size: number): void => {
    if (!bytesPtr || size <= 0) return;
    const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
    values.push(codec.decode(bytes));
  }, 'viii');
  try {
    const rc = call(callbackPtr);
    if (rc !== 0) {
      modalityLogger.warning(`${functionName} returned ${formatRacResult(rc)}`);
      return null;
    }
    return values;
  } finally {
    module.removeFunction(callbackPtr);
  }
}

export function withOptionalCallback<T, R>(
  module: ModalityProtoModule,
  codec: ProtoCodec<T>,
  handler: ProtoEventHandler<T> | null,
  functionName: string,
  call: (callbackPtr: number) => R,
): R | null {
  if (!handler) return call(0);
  if (!module.addFunction || !module.removeFunction || !module.HEAPU8) {
    modalityLogger.warning(`${functionName}: module missing callback helpers`);
    return null;
  }
  const callbackPtr = module.addFunction((bytesPtr: number, size: number): number => {
    if (!bytesPtr || size <= 0) return 1;
    const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
    handler(codec.decode(bytes));
    return 1;
  }, callbackSignature(true));
  try {
    return call(callbackPtr);
  } finally {
    module.removeFunction(callbackPtr);
  }
}

export function callbackSignature(returnsBool: boolean): CallbackSignature {
  return returnsBool ? 'iiii' : 'viii';
}

export function bridgeFor(module: ModalityProtoModule): ProtoWasmBridge {
  return new ProtoWasmBridge(module, modalityLogger);
}

export function missingExports(
  module: ModalityProtoModule,
  required: Array<keyof ModalityProtoModule>,
): string[] {
  return [
    ...bridgeFor(module).missingProtoBufferExports(),
    ...required.filter((key) => !module[key]).map(String),
  ];
}

export function ensureExports(
  module: ModalityProtoModule,
  operation: string,
  required: Array<keyof ModalityProtoModule>,
): boolean {
  const missing = missingExports(module, required);
  if (missing.length > 0) {
    modalityLogger.warning(`${operation}: module missing modality proto exports: ${missing.join(', ')}`);
    return false;
  }
  return true;
}

export function requireExports(
  module: ModalityProtoModule,
  operation: string,
  required: Array<keyof ModalityProtoModule>,
): void {
  const missing = missingExports(module, required);
  if (missing.length > 0) {
    throw SDKException.backendNotAvailable(
      operation,
      `WASM module missing modality proto exports: ${missing.join(', ')}`,
    );
  }
}
