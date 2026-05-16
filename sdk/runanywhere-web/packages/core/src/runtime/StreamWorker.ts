/**
 * StreamWorker.ts
 *
 * T6.1 — Web Worker thread script + shared protocol types.
 *
 * Two distinct concerns live in this file:
 *
 *  1. The discriminated-union message protocol shared between
 *     `OffscreenRuntimeBridge` (main thread) and the worker. The bridge
 *     imports the types via `import type` so no worker runtime is pulled
 *     into the main bundle.
 *
 *  2. The worker-side dispatch logic. A backend package builds a tiny
 *     bootstrap worker bundle that:
 *       - registers its Emscripten module factory via
 *         {@link registerStreamModuleFactory},
 *       - calls {@link runStreamWorker} to wire `self.onmessage`.
 *
 *     The same `racommons-llamacpp.wasm` (or onnx variant) is instantiated
 *     a second time inside the worker — see DECISION-3 in the design doc.
 *     Accepting ~2× memory for streaming WASM is the explicit trade-off
 *     for live token delivery without rebuilding C++ with Asyncify.
 *
 * Non-streaming exports stay on the main-thread `EmscriptenModule`
 * instance; only the four `_rac_*_stream_proto` exports below are
 * mirrored into the worker.
 *
 * VAD activity callback and `VoiceAgentStreamAdapter` are EXCLUDED from
 * T6.1: those are slot-based (set-once, fire-many) rather than per-call,
 * so they don't fit the request/response message pattern used here.
 */

// ---------------------------------------------------------------------------
// Wire protocol — shared with `OffscreenRuntimeBridge` via `import type`.
// ---------------------------------------------------------------------------

/** Discriminated union of every message the bridge may send to the worker. */
export type WorkerRequest =
  | { type: 'init'; wasmBytes: ArrayBuffer; moduleFactoryId: string }
  | {
      type: 'stream.llm.generate';
      requestId: string;
      handle: number;
      requestBytes: Uint8Array;
    }
  | {
      type: 'stream.stt.transcribe';
      requestId: string;
      handle: number;
      audioBytes: Uint8Array;
      optionsBytes: Uint8Array;
    }
  | {
      type: 'stream.tts.synthesize';
      requestId: string;
      handle: number;
      text: string;
      optionsBytes: Uint8Array;
    }
  | {
      type: 'stream.vlm.process';
      requestId: string;
      handle: number;
      imageBytes: Uint8Array;
      promptBytes: Uint8Array;
    }
  | { type: 'cancel'; requestId: string };

/** Discriminated union of every message the worker may post back. */
export type WorkerResponse =
  | { type: 'ready' }
  | { type: 'error'; requestId?: string; message: string }
  | { type: 'callback'; requestId: string; payloadBytes: Uint8Array }
  | { type: 'done'; requestId: string; returnCode: number };

/** All non-`init` stream variants — the `OffscreenRuntimeBridge` accepts
 *  these (sans `requestId`, which it allocates) when starting an iterator. */
export type StreamRequestKind = Exclude<
  WorkerRequest['type'],
  'init' | 'cancel'
>;

// ---------------------------------------------------------------------------
// Worker-side module factory registry
// ---------------------------------------------------------------------------

/**
 * Minimal subset of the Emscripten module surface the worker dispatch needs.
 * Mirrors the streaming subset of `ModalityProtoModule`.
 */
export interface StreamWorkerModule {
  HEAPU8: Uint8Array;
  _malloc(size: number): number;
  _free(ptr: number): void;
  lengthBytesUTF8?(str: string): number;
  stringToUTF8?(str: string, ptr: number, maxBytesToWrite: number): number;
  addFunction(fn: (...args: number[]) => number | void, signature: string): number;
  removeFunction(ptr: number): void;

  _rac_llm_generate_stream_proto?(
    requestBytes: number,
    requestSize: number,
    callbackPtr: number,
    userData: number,
  ): number;
  _rac_llm_cancel_proto?(outEvent: number): number;

  _rac_stt_component_transcribe_stream_proto?(
    handle: number,
    audioData: number,
    audioSize: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
  ): number;

  _rac_tts_component_synthesize_stream_proto?(
    handle: number,
    text: number,
    optionsBytes: number,
    optionsSize: number,
    callbackPtr: number,
    userData: number,
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
}

export type StreamModuleFactory = (wasmBytes: ArrayBuffer) => Promise<StreamWorkerModule>;

const _moduleFactories = new Map<string, StreamModuleFactory>();

/**
 * Backend bootstrap helper — called from the worker bundle BEFORE
 * `runStreamWorker()` to install the module factory keyed by the same
 * `moduleFactoryId` the main thread will send in its `init` message.
 */
export function registerStreamModuleFactory(id: string, factory: StreamModuleFactory): void {
  _moduleFactories.set(id, factory);
}

// ---------------------------------------------------------------------------
// Worker-side dispatch
// ---------------------------------------------------------------------------

/**
 * Worker-thread scope subset the dispatcher needs. Mirrors
 * `DedicatedWorkerGlobalScope` without forcing a lib.webworker.d.ts
 * dependency on the core package's tsconfig.
 */
export interface StreamWorkerScope {
  onmessage: ((ev: MessageEvent<WorkerRequest>) => void) | null;
  postMessage(message: WorkerResponse, transfer?: Transferable[]): void;
}

/**
 * Wire `self.onmessage` on the worker side and dispatch every
 * `WorkerRequest` to the appropriate `_rac_*_stream_proto` export.
 *
 * Cancellation is best-effort: the bridge stops listening immediately
 * for cancelled requests, and the worker calls the matching `_cancel`
 * export when it has one (LLM, VLM). Synchronous exports cannot be
 * pre-empted from inside their own frame.
 */
export function runStreamWorker(scope: StreamWorkerScope): void {
  let mod: StreamWorkerModule | null = null;
  const cancelled = new Set<string>();

  const postError = (message: string, requestId?: string): void => {
    scope.postMessage({ type: 'error', requestId, message });
  };

  const ensureModule = (): StreamWorkerModule | null => {
    if (!mod) {
      postError('stream worker received stream request before init');
      return null;
    }
    return mod;
  };

  const installCallback = (
    moduleRef: StreamWorkerModule,
    requestId: string,
    callbackReturnsBool: boolean,
  ): number => {
    const trampoline = (bytesPtr: number, size: number): number | void => {
      if (cancelled.has(requestId) || !bytesPtr || size <= 0) {
        return callbackReturnsBool ? 1 : undefined;
      }
      try {
        const payloadBytes = moduleRef.HEAPU8.slice(bytesPtr, bytesPtr + size);
        scope.postMessage({ type: 'callback', requestId, payloadBytes });
        return callbackReturnsBool ? 1 : undefined;
      } catch (err) {
        postError(`callback marshal failed: ${(err as Error).message}`, requestId);
        return callbackReturnsBool ? 0 : undefined;
      }
    };
    return moduleRef.addFunction(trampoline, callbackReturnsBool ? 'iiii' : 'viii');
  };

  const withHeapBytes = <T>(
    moduleRef: StreamWorkerModule,
    bytes: Uint8Array,
    fn: (ptr: number, len: number) => T,
  ): T => {
    const ptr = moduleRef._malloc(Math.max(bytes.byteLength, 1));
    if (!ptr) throw new Error('stream worker: heap allocation failed');
    try {
      moduleRef.HEAPU8.set(bytes, ptr);
      return fn(ptr, bytes.byteLength);
    } finally {
      moduleRef._free(ptr);
    }
  };

  const allocUtf8 = (moduleRef: StreamWorkerModule, value: string): number => {
    if (!moduleRef.lengthBytesUTF8 || !moduleRef.stringToUTF8) {
      throw new Error('stream worker: module missing UTF-8 helpers');
    }
    const size = moduleRef.lengthBytesUTF8(value) + 1;
    const ptr = moduleRef._malloc(size);
    if (!ptr) throw new Error('stream worker: UTF-8 alloc failed');
    moduleRef.stringToUTF8(value, ptr, size);
    return ptr;
  };

  const runWithCallback = (
    requestId: string,
    callbackReturnsBool: boolean,
    invoke: (callbackPtr: number) => number,
  ): void => {
    const moduleRef = ensureModule();
    if (!moduleRef) {
      scope.postMessage({ type: 'done', requestId, returnCode: -901 });
      return;
    }
    const callbackPtr = installCallback(moduleRef, requestId, callbackReturnsBool);
    let returnCode = 0;
    try {
      returnCode = invoke(callbackPtr);
    } catch (err) {
      postError(`stream export threw: ${(err as Error).message}`, requestId);
      returnCode = -902;
    } finally {
      moduleRef.removeFunction(callbackPtr);
    }
    scope.postMessage({ type: 'done', requestId, returnCode });
  };

  scope.onmessage = (ev: MessageEvent<WorkerRequest>): void => {
    const msg = ev.data;
    switch (msg.type) {
      case 'init': {
        const factory = _moduleFactories.get(msg.moduleFactoryId);
        if (!factory) {
          postError(`stream worker: no module factory registered for id="${msg.moduleFactoryId}"`);
          return;
        }
        void factory(msg.wasmBytes)
          .then((instantiated) => {
            mod = instantiated;
            scope.postMessage({ type: 'ready' });
          })
          .catch((err: unknown) => {
            postError(
              `stream worker: module instantiation failed: ${(err as Error).message ?? String(err)}`,
            );
          });
        return;
      }
      case 'cancel': {
        cancelled.add(msg.requestId);
        // Best-effort: poke the matching cancel export. The worker has no
        // way to know which modality the requestId belongs to without
        // bookkeeping, so it pokes both modality-specific cancel verbs
        // that exist and lets the C side ignore the no-op.
        mod?._rac_llm_cancel_proto?.(0);
        // VLM cancel takes a handle — we don't have it here. Document the
        // gap: deep cancel for VLM requires per-requestId handle tracking,
        // tracked as a follow-up in STREAM_DELIVERY_DESIGN.md.
        return;
      }
      case 'stream.llm.generate': {
        runWithCallback(msg.requestId, false, (callbackPtr) => {
          const m = mod!;
          if (!m._rac_llm_generate_stream_proto) return -801;
          return withHeapBytes(m, msg.requestBytes, (requestPtr, requestSize) =>
            m._rac_llm_generate_stream_proto!(requestPtr, requestSize, callbackPtr, 0),
          );
        });
        return;
      }
      case 'stream.stt.transcribe': {
        runWithCallback(msg.requestId, false, (callbackPtr) => {
          const m = mod!;
          if (!m._rac_stt_component_transcribe_stream_proto) return -801;
          return withHeapBytes(m, msg.audioBytes, (audioPtr, audioSize) =>
            withHeapBytes(m, msg.optionsBytes, (optionsPtr, optionsSize) =>
              m._rac_stt_component_transcribe_stream_proto!(
                msg.handle,
                audioPtr,
                audioSize,
                optionsPtr,
                optionsSize,
                callbackPtr,
                0,
              ),
            ),
          );
        });
        return;
      }
      case 'stream.tts.synthesize': {
        runWithCallback(msg.requestId, false, (callbackPtr) => {
          const m = mod!;
          if (!m._rac_tts_component_synthesize_stream_proto) return -801;
          const textPtr = allocUtf8(m, msg.text);
          try {
            return withHeapBytes(m, msg.optionsBytes, (optionsPtr, optionsSize) =>
              m._rac_tts_component_synthesize_stream_proto!(
                msg.handle,
                textPtr,
                optionsPtr,
                optionsSize,
                callbackPtr,
                0,
              ),
            );
          } finally {
            m._free(textPtr);
          }
        });
        return;
      }
      case 'stream.vlm.process': {
        runWithCallback(msg.requestId, true, (callbackPtr) => {
          const m = mod!;
          if (!m._rac_vlm_process_stream_proto) return -801;
          // VLM also needs an out-result pointer; allocate a small scratch
          // slot. The actual result envelope is delivered via callbacks
          // (mirrors the main-thread `streamEvents` adapter contract); the
          // scratch slot is freed before returning the rc to the bridge.
          const outResult = m._malloc(8);
          try {
            return withHeapBytes(m, msg.imageBytes, (imagePtr, imageSize) =>
              withHeapBytes(m, msg.promptBytes, (promptPtr, promptSize) =>
                m._rac_vlm_process_stream_proto!(
                  msg.handle,
                  imagePtr,
                  imageSize,
                  promptPtr,
                  promptSize,
                  callbackPtr,
                  0,
                  outResult,
                ),
              ),
            );
          } finally {
            if (outResult) m._free(outResult);
          }
        });
        return;
      }
    }
  };
}
