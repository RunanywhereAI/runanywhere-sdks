import type { LoRAState as ProtoLoRAState } from '@runanywhere/proto-ts/lora_options';
import { SDKException } from '../Foundation/SDKException.js';
import { SDKLogger } from '../Foundation/SDKLogger.js';
import {
  formatRacResult,
  ProtoWasmBridge,
  type ProtoCodec,
  type ProtoWasmModule,
} from '../runtime/ProtoWasm.js';

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
  _rac_stt_transcribe_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_stt_transcribe_stream_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
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
  _rac_tts_synthesize_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_tts_synthesize_stream_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_tts_stop_lifecycle_proto?(outResult: number): number;
  _rac_tts_list_voices_lifecycle_proto?(outResult: number): number;

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
  _rac_vad_process_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_vad_configure_lifecycle_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_vad_start_lifecycle_proto?(outResult: number): number;
  _rac_vad_stop_lifecycle_proto?(outResult: number): number;
  _rac_vad_reset_lifecycle_proto?(outResult: number): number;
  _rac_vad_set_stream_proto_callback?(
    handle: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_vad_unset_stream_proto_callback?(handle: number): number;
  _rac_vad_proto_quiesce?(): void;
  _rac_vad_stream_start_proto?(
    handle: number,
    optionsBytes: number,
    optionsSize: number,
    outSessionIdPtr: number,
  ): number;
  _rac_vad_stream_feed_audio_proto?(
    sessionId: bigint,
    audioBytes: number,
    audioSize: number,
  ): number;
  _rac_vad_stream_stop_proto?(sessionId: bigint): number;
  _rac_vad_stream_cancel_proto?(sessionId: bigint): number;

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
  _rac_voice_agent_component_destroy_proto?(handle: number): number;

  _rac_vlm_process_proto?(
    handle: number,
    imageBytes: number,
    imageSize: number,
    optionsBytes: number,
    optionsSize: number,
    outResult: number,
  ): number;
  /** Typed stream ABI: serialized VLMGenerationRequest in, VLMStreamEvent
   *  per callback. Lifecycle-owned model — no handle, no out-result. */
  _rac_vlm_stream_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_vlm_cancel_proto?(handle: number): number;

  _rac_embeddings_embed_batch_proto?(
    handle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_embeddings_embed_batch_lifecycle_proto?(
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
  _rac_lora_adapter_import_proto?(
    registry: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_compatibility_proto?(
    configBytes: number,
    configSize: number,
    outResult: number,
  ): number;
  _rac_lora_apply_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_lora_remove_proto?(
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;
  _rac_lora_list_proto?(
    requestBytes: number,
    requestSize: number,
    outState: number,
  ): number;
  _rac_lora_state_proto?(
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
// Shared mutable state used by `ModalityProtoAdapter` and
// `VADProtoAdapter.setActivityHandler`. Lives in one module so the per-
// modality files don't drift out of sync.
//
// Per-modality slots replace the single `defaultModule` slot that the
// pre-P4 monolithic-WASM era used. Each per-modality adapter looks up the
// module that owns its capability, so backends that register narrower
// capability sets (e.g. ONNX → STT/TTS/VAD) no longer overwrite the module
// for unrelated modalities (e.g. LLM via llamacpp).
//
// Capability names mirror `WasmCapability` in EmscriptenModule.ts.
// ---------------------------------------------------------------------------

export interface ModalityCapabilitySlots {
  llm: ModalityProtoModule | null;
  vlm: ModalityProtoModule | null;
  stt: ModalityProtoModule | null;
  tts: ModalityProtoModule | null;
  vad: ModalityProtoModule | null;
  embedding: ModalityProtoModule | null;
  rag: ModalityProtoModule | null;
  diffusion: ModalityProtoModule | null;
  'structured-output': ModalityProtoModule | null;
  'tool-calling': ModalityProtoModule | null;
  lora: ModalityProtoModule | null;
  'voice-agent': ModalityProtoModule | null;
}

export type ModalityCapabilityName = keyof ModalityCapabilitySlots;

export const adapterState = {
  /**
   * Legacy aggregate slot — kept so `ModalityProtoAdapter.tryDefault()`
   * still returns a single module for callers that don't care which
   * capability they're talking to. Populated by whichever module last
   * registered the 'commons' capability, falling back to any module if no
   * commons exists.
   */
  defaultModule: null as ModalityProtoModule | null,
  /**
   * Per-modality module slots. A given module may occupy multiple slots
   * (LLM + VLM share the llamacpp module; STT/TTS/VAD share the onnx
   * module). Lookup is O(1).
   */
  modalitySlots: {
    llm: null,
    vlm: null,
    stt: null,
    tts: null,
    vad: null,
    embedding: null,
    rag: null,
    diffusion: null,
    'structured-output': null,
    'tool-calling': null,
    lora: null,
    'voice-agent': null,
  } as ModalityCapabilitySlots,
  vadActivityCallbackPtrs: new Map<number, number>(),
};

/**
 * Helper used by per-modality adapters: returns the module that owns the
 * given capability, or null if no backend has registered for it.
 */
export function modalityModuleFor(
  cap: ModalityCapabilityName,
): ModalityProtoModule | null {
  return adapterState.modalitySlots[cap];
}

export function emptyLoRAState(): ProtoLoRAState {
  return {
    loadedAdapters: [],
    hasActiveAdapters: false,
    errorCode: 0,
  };
}

/**
 * Default number of native callback emissions between cooperative yield
 * points. See `streamYield` for usage by async call wrappers.
 *
 * For a purely synchronous Emscripten export this counter is observed but
 * does not pause the export — `queueMicrotask`'d work cannot preempt a
 * still-running synchronous JS frame. The counter becomes meaningful for
 * cooperative (async) call wrappers — test fakes today, Asyncify / Worker
 * backends tomorrow — that `await streamYield()` between callback batches.
 */
export const DEFAULT_STREAM_YIELD_EVERY = 16;

/**
 * Cooperative yield primitive for asynchronous native-call wrappers used
 * with `streamCallback`. Resolves on the next microtask, giving the
 * consumer iterator's pending `next()` resolutions a chance to run before
 * the wrapper resumes emitting.
 *
 * Usage in an async wrapper:
 *
 * ```ts
 *   async (callbackPtr) => {
 *     for (let i = 0; i < tokens.length; i++) {
 *       emitToken(callbackPtr, tokens[i]);
 *       if (i % DEFAULT_STREAM_YIELD_EVERY === DEFAULT_STREAM_YIELD_EVERY - 1) {
 *         await streamYield();
 *       }
 *     }
 *     return 0;
 *   }
 * ```
 *
 * Purely synchronous Emscripten exports do not need to call this — they
 * cannot be preempted from JS, and `streamCallback` already defers them
 * onto a microtask so the AsyncIterable handle is observable before the
 * blocking call begins. See `docs/STREAM_DELIVERY_DESIGN.md` for the full
 * architectural picture and migration path to true live delivery.
 */
export function streamYield(): Promise<void> {
  return new Promise<void>((resolve) => queueMicrotask(resolve));
}

/**
 * Web-side slot.fn(user_data) lifetime contract (pass3-syn-033 / cross-SDK
 * mirror of rac_llm_stream.h `@warning` block).
 *
 * Current Web adapters register JS trampolines on the calling Emscripten
 * runtime and quiesce the native callback source before releasing them. The
 * pthread pool is used for native inference work, not as an excuse to release
 * a trampoline while it can still be called. The contract below therefore
 * still holds and is worth documenting so SDK-internal adapters stay correct
 * when:
 *
 *   1. The Asyncify / Worker backend lands (see
 *      docs/STREAM_DELIVERY_DESIGN.md) — at that point the callback can
 *      be invoked while a JS microtask is queued, and the closure capturing
 *      `this` / `userData` MUST remain alive until `streamYield()` /
 *      Asyncify's resumption point completes.
 *   2. Adapters wrap the native call in `Promise.resolve()` then call
 *      `removeFunction(callbackPtr)` — the closure passed to
 *      `addFunction(...)` is what the C runtime holds via `userData`; the
 *      adapter MUST NOT remove it while the call is still in flight
 *      (tracked via `callActive` below).
 *
 * Recommended teardown sequence (mirrors the canonical native recipe of
 * unset → quiesce → free):
 *
 *   (a) Issue the native unset (e.g. `_rac_llm_unset_stream_proto_callback`)
 *       OR rely on the natural completion of the native call.
 *   (b) Wait for `callActive === false` (the WASM export's promise has
 *       resolved). This is the WASM analogue of `rac_*_proto_quiesce()`.
 *   (c) Call `module.removeFunction(callbackPtr)` to release the JS
 *       trampoline and let GC reclaim the user_data closure.
 *
 * The implementation in `streamCallback` below enforces this contract: it
 * only calls `removeFunction` from `cleanup()` when `callActive` is false,
 * deferring the cleanup until the WASM call settles.
 */
export function streamCallback<T>(
  module: ModalityProtoModule,
  codec: ProtoCodec<T>,
  functionName: string,
  call: (callbackPtr: number) => number | Promise<number>,
  stopWhen?: (event: T) => boolean,
  onCancel?: () => void,
  onErrorEvent?: (rc: number) => T | null,
  callbackReturnsBool = false,
  yieldEvery: number = DEFAULT_STREAM_YIELD_EVERY,
): AsyncIterable<T> {
  const yieldThreshold = Math.max(1, yieldEvery | 0);
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
      let emitsSinceYield = 0;

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
        // Callback yield (option (b) in STREAM_DELIVERY_DESIGN.md): after
        // every `yieldThreshold` emissions, post an empty microtask. This
        // is the cooperative scheduling boundary an async call wrapper
        // can synchronise against via `await streamYield()` — at that
        // point any pending consumer waiter resolutions (queued by the
        // `resolve(...)` above) flush before the wrapper resumes, so the
        // consumer iterator observes events live instead of seeing the
        // full batch only after the native call returns. For purely
        // synchronous wrappers the queued microtask is a no-op because
        // sync JS frames cannot be preempted from inside `emit`.
        emitsSinceYield += 1;
        if (emitsSinceYield >= yieldThreshold) {
          emitsSinceYield = 0;
          queueMicrotask(noopBarrier);
        }
        if (stopWhen?.(event)) finish();
      };

      // HOTSPOT-WEB-CORE-002 / WEB-CORE-001: register the native callback
      // synchronously (cheap pointer install) but DEFER the blocking native
      // `call(callbackPtr)` until the next microtask. Without this defer,
      // the iterator's first `next()` re-enters the synchronous Emscripten
      // export, drains all events into the queue, and only then resolves —
      // which means the public `await generateStream(...)` / streamCallback
      // contract cannot return its handle before native generation begins
      // and cancellation cannot interleave with a still-running call.
      const installCallback = (): boolean => {
        if (!module.addFunction || !module.removeFunction || !module.HEAPU8) {
          fail(SDKException.wasmNotLoaded(`${functionName}: module missing callback helpers`));
          return false;
        }
        callbackPtr = module.addFunction((bytesPtr: number, size: number): CallbackResult => {
          if (!bytesPtr || size <= 0) return callbackReturnsBool ? 1 : undefined;
          try {
            const bytes = module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
            emit(codec.decode(bytes));
            return callbackReturnsBool ? 1 : undefined;
          } catch (error) {
            // Swift parity (ProtoStreamContext.yield): a per-event decode
            // failure is logged and the event skipped — it does not tear
            // down the whole stream.
            modalityLogger.warning(
              `${functionName}: failed to decode stream event: ${error instanceof Error ? error.message : String(error)}`,
            );
            return callbackReturnsBool ? 1 : undefined;
          }
        }, callbackSignature(callbackReturnsBool));
        return true;
      };

      // `runNativeCall` is async so the `call` wrapper may opt into
      // returning a Promise<number> instead of a sync number. Synchronous
      // CPU/ONNX exports continue to work transparently — `await sync_number`
      // resolves immediately — while the WebGPU release artifact resumes its
      // Asyncify call only after browser GPU work settles.
      //   • Test mocks can simulate live delivery (see
      //     `tests/unit/Adapters/StreamLiveDelivery.test.ts`).
      //   • Asyncify / Web Worker backends can yield between callback batches
      //     without any change to `streamCallback` or its consumers.
      const runNativeCall = async (): Promise<void> => {
        if (finished) {
          // Cancelled before the deferred call started — nothing to invoke.
          cleanup();
          return;
        }
        callActive = true;
        try {
          const rc = await call(callbackPtr);
          if (rc !== 0) {
            // Swift parity (CppBridge+ModalityProtoABI.swift:289-292): a
            // non-success return synthesizes a terminal event via the
            // modality's factory and finishes the stream — the iterator
            // never rejects. `finished` already true means the consumer
            // cancelled, which (like Swift's `!context.isCancelled` guard)
            // skips the synthetic event.
            if (!finished) {
              const terminal = onErrorEvent?.(rc) ?? null;
              if (terminal !== null) {
                emit(terminal);
              } else {
                modalityLogger.warning(`${functionName} returned ${formatRacResult(rc)}`);
              }
              finish();
            }
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

      const start = (): void => {
        if (started) return;
        started = true;
        if (!installCallback()) return;
        // Run the (potentially blocking) native call on a fresh microtask
        // so the iterator's first `next()` resolves (or registers its
        // waiter) before native code starts draining tokens. This keeps
        // the AsyncIterable contract observable and lets
        // `iterator.return()` / facade `cancel()` reach the `onCancel`
        // hook before the call begins for fake/test modules whose stream
        // export can block on a deferred latch. The returned Promise is
        // intentionally discarded — `runNativeCall` routes every error
        // through `fail()` so it never rejects.
        queueMicrotask(() => { void runNativeCall(); });
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

function noopBarrier(): void {
  /* cooperative-yield barrier; intentionally empty */
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
