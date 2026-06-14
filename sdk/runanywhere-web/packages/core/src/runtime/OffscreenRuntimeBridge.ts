/**
 * OffscreenRuntimeBridge.ts
 *
 * T6.1 — Main-thread orchestrator for the Worker streaming path.
 *
 * @internal @experimental
 *
 * INTERNAL/EXPERIMENTAL — NOT a stable public surface. The T6.1 Worker
 * streaming path ships as scaffolding only: no production backend
 * (`@runanywhere/web-llamacpp`, `@runanywhere/web-onnx`) currently
 * installs the `StreamWorkerFactory` or calls `setStreamWorkerInit`, so
 * `OffscreenRuntimeBridge.tryGet()` returns `null` in every production
 * code path and adapters fall through to the main-thread
 * `streamCallback` (queueMicrotask) path. The dispatch code below is
 * exercised only by the unit tests under
 * `tests/unit/runtime/StreamWorker.test.ts` until a backend lands its
 * Worker bootstrap.
 *
 * REMOVAL CONTRACT:
 *   Either (a) a backend package wires a worker bundle + calls
 *   `setStreamWorkerFactory(...)` + `setStreamWorkerInit(...)` from its
 *   `register()`, at which point this file flips to a stable public
 *   surface (drop the `@internal @experimental` tag) — OR (b) the
 *   Worker streaming path is abandoned in favour of the documented
 *   SAB ring-buffer follow-up (Option C in
 *   `docs/STREAM_DELIVERY_DESIGN.md`), at which point this file plus
 *   `StreamWorker.ts` + `StreamWorkerFactoryRegistry.ts` are deleted
 *   wholesale. Do NOT build new SDK features against the
 *   `OffscreenRuntimeBridge` API surface until that disposition lands.
 *
 *   Tracked by:
 *     - `comments/pr-494/addressing/comments/pass2-syn-027.json` —
 *       "T6.1 Worker streaming path is dead code in production"
 *     - `docs/STREAM_DELIVERY_DESIGN.md` — DECISION-3 + Recommended-next-step
 *
 * Owns a lazily-spawned `Worker` and routes per-call streaming requests
 * (`stream.llm.generate`, `stream.stt.transcribe`, `stream.tts.synthesize`,
 * `stream.vlm.process`) to it. Each request returns an `AsyncIterable<T>`
 * whose `next()` resolves as `callback` messages arrive from the worker.
 *
 * Design notes:
 *  - The bridge is a singleton scoped to the registered Worker factory.
 *    Backends call `setStreamWorkerFactory(...)` during `register()`;
 *    `OffscreenRuntimeBridge.tryGet(mode)` returns the bridge iff that
 *    factory is installed.
 *  - The Worker holds its own Emscripten module instance for STREAMING
 *    ONLY (DECISION-3): non-streaming exports stay on the main-thread
 *    `EmscriptenModule` singleton. Accepts ~2× memory for the streaming
 *    WASM. Documented in `docs/STREAM_DELIVERY_DESIGN.md`.
 *  - Cancellation is deterministic on the main thread: `cancel(requestId)`
 *    posts a `cancel` message to the worker and immediately ends the
 *    iterator. Any further `callback` messages for that requestId are
 *    silently dropped.
 *  - VAD activity callback and `VoiceAgentStreamAdapter` are EXCLUDED
 *    from T6.1 — those are slot-based (set-once, fire-many) rather
 *    than per-call request/response.
 */

import { ProtoErrorCode, SDKException } from '../Foundation/SDKException';
import { SDKLogger } from '../Foundation/SDKLogger';
import { Runtime, type StreamingMode } from '../Foundation/RuntimeConfig';
import {
  getStreamWorkerFactory,
  type StreamWorkerFactory,
} from './StreamWorkerFactoryRegistry';
import type { ProtoCodec } from './ProtoWasm';
import type {
  StreamRequestKind,
  WorkerRequest,
  WorkerResponse,
} from './StreamWorker';

const logger = new SDKLogger('OffscreenRuntimeBridge');

/**
 * The set of fields the bridge needs from the caller for each stream
 * variant — `requestId` is allocated by the bridge, so the adapter only
 * supplies the payload.
 */
export type BridgeStreamRequest =
  | { kind: 'stream.llm.generate'; handle: number; requestBytes: Uint8Array }
  | {
      kind: 'stream.stt.transcribe';
      handle: number;
      audioBytes: Uint8Array;
      optionsBytes: Uint8Array;
    }
  | {
      kind: 'stream.tts.synthesize';
      handle: number;
      text: string;
      optionsBytes: Uint8Array;
    }
  | {
      kind: 'stream.vlm.generate';
      requestBytes: Uint8Array;
    };

export interface StreamIteratorOptions<T> {
  /** When this predicate returns true on a decoded event the iterator finishes. */
  stopWhen?: (event: T) => boolean;
  /** Invoked on `iterator.return()` (consumer cancel) BEFORE the worker cancel
   *  message is posted. Useful for adapters that want to also poke a
   *  main-thread cancel export (e.g. legacy bookkeeping). */
  onCancel?: () => void;
}

interface WorkerInit {
  wasmBytes: ArrayBuffer;
  moduleFactoryId: string;
}

interface PerRequestState {
  emit(payloadBytes: Uint8Array): void;
  finish(returnCode: number): void;
  fail(err: unknown): void;
}

/** Module-scoped singleton — one bridge per process. */
let _instance: OffscreenRuntimeBridge | null = null;
let _init: WorkerInit | null = null;

/**
 * Backend hook: provide the wasm bytes + factory id the worker needs to
 * initialise its mirror module. Called by `@runanywhere/web-llamacpp`
 * (and onnx) once during their `register()`. May be omitted by tests
 * that supply a fake Worker with no real init handshake.
 */
export function setStreamWorkerInit(init: WorkerInit | null): void {
  _init = init;
}

export class OffscreenRuntimeBridge {
  /**
   * Return the shared bridge instance if Worker-mode is available given
   * the current `streamingMode` preference. Returns `null` (and
   * adapters fall back to the main-thread path) when:
   *   - `mode === 'main'`, or
   *   - no `streamWorkerFactory` is registered, or
   *   - no `setStreamWorkerInit(...)` payload has been registered.
   *
   * `mode === 'worker'` with no factory logs a warning on first use,
   * then still returns `null` — adapters must not break.
   *
   * Mode sampling: `streamingMode` is read on every `tryGet()` call.
   * Mid-session flips between `'auto'`/`'worker'` and `'main'` correctly
   * short-circuit because `'main'` returns `null` immediately. Flips
   * between `'auto'` and `'worker'` reuse the cached bridge singleton —
   * both are Worker-eligible so no reconfiguration is needed. The
   * Worker-mode-with-no-factory warning is reset on `dispose()`.
   */
  static tryGet(mode: StreamingMode = Runtime.streamingMode): OffscreenRuntimeBridge | null {
    if (mode === 'main') return null;
    const factory = getStreamWorkerFactory();
    if (!factory) {
      if (mode === 'worker' && !_warnedNoFactory) {
        _warnedNoFactory = true;
        logger.warning(
          'streamingMode="worker" requested but no streamWorkerFactory registered — falling back to main-thread streaming',
        );
      }
      return null;
    }
    // Gate the bridge on a non-null init payload too: without it the
    // worker can never receive its wasmBytes/moduleFactoryId and the
    // handshake would hang. See pass2-syn-034.
    if (!_init) {
      if (mode === 'worker' && !_warnedNoInit) {
        _warnedNoInit = true;
        logger.warning(
          'streamingMode="worker" requested but no setStreamWorkerInit payload registered — falling back to main-thread streaming',
        );
      }
      return null;
    }
    if (!_instance) _instance = new OffscreenRuntimeBridge(factory);
    return _instance;
  }

  /** Test-only: tear down the singleton + reset the no-factory warning. */
  static resetForTesting(): void {
    _instance?.dispose();
    _instance = null;
    _warnedNoFactory = false;
    _warnedNoInit = false;
  }

  /**
   * Public teardown — called by `RunAnywhere.shutdown()` to release the
   * cached singleton + its worker thread + any pending iterators. Unlike
   * `resetForTesting()` this is part of the SDK shutdown contract.
   */
  static disposeShared(): void {
    _instance?.dispose();
    _instance = null;
    _warnedNoFactory = false;
    _warnedNoInit = false;
  }

  private worker: Worker | null = null;
  private readyPromise: Promise<void> | null = null;
  private requestCounter = 0;
  private readonly pending = new Map<string, PerRequestState>();

  private constructor(private readonly factory: StreamWorkerFactory) {}

  /**
   * Idempotent spawn — the first caller wins and every subsequent caller
   * awaits the same `ready` handshake.
   *
   * Bounded by {@link HANDSHAKE_TIMEOUT_MS}: a Worker bundle that fails
   * silently (404, malformed wasm, throws before wiring `onmessage`)
   * rejects every consumer iterator with an actionable
   * `SDKException(WASMNotLoaded)` instead of hanging indefinitely.
   * See pass2-syn-034 / pass2-syn-092.
   */
  async spawnWorker(): Promise<void> {
    if (this.readyPromise) return this.readyPromise;
    this.readyPromise = new Promise<void>((resolve, reject) => {
      let handshakeTimer: ReturnType<typeof setTimeout> | null = null;
      const settleReject = (err: unknown): void => {
        if (handshakeTimer != null) {
          clearTimeout(handshakeTimer);
          handshakeTimer = null;
        }
        this._handshakeResolve = null;
        // Best-effort terminate to release a stuck worker thread.
        try { this.worker?.terminate(); } catch { /* swallow */ }
        this.worker = null;
        // pass3-syn-155: clear the cached readyPromise on rejection so
        // a subsequent spawnWorker() can retry instead of returning the
        // sticky rejected promise (which would force a full SDK shutdown
        // just to recover from a transient handshake failure).
        this.readyPromise = null;
        reject(err instanceof Error ? err : new Error(String(err)));
      };
      try {
        // Belt-and-braces: tryGet() already gates on a non-null _init,
        // but if a caller raced setStreamWorkerInit(null) we must fail
        // fast with a clear diagnostic rather than spawn a worker we
        // can never initialise.
        if (!_init) {
          throw new SDKException(
            -ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED,
            'OffscreenRuntimeBridge.spawnWorker called with no setStreamWorkerInit payload registered',
          );
        }
        const worker = this.factory();
        this.worker = worker;
        worker.onmessage = (ev: MessageEvent<WorkerResponse>) => {
          this.handleResponse(ev.data);
        };
        worker.onerror = (ev: ErrorEvent) => {
          logger.warning(`stream worker error: ${ev.message ?? '<unknown>'}`);
          this.failAll(new Error(`stream worker error: ${ev.message ?? '<unknown>'}`));
        };
        // Hook the handshake so it resolves on the first `ready` message.
        const handshakeKey = '__ready__';
        this.pending.set(handshakeKey, {
          emit() { /* unused for handshake */ },
          finish() { /* unused for handshake */ },
          fail: (err: unknown) => settleReject(err),
        });
        // The `handleResponse` switch resolves the handshake explicitly.
        this._handshakeResolve = () => {
          if (handshakeTimer != null) {
            clearTimeout(handshakeTimer);
            handshakeTimer = null;
          }
          this.pending.delete(handshakeKey);
          resolve();
        };
        // Upper-bound the handshake. The design doc budgets ~10-50 ms
        // cold-path bootstrap; the timeout is two orders of magnitude
        // looser so it only fires on real breakage.
        handshakeTimer = setTimeout(() => {
          handshakeTimer = null;
          this.pending.delete(handshakeKey);
          settleReject(
            new SDKException(
              -ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED,
              `stream worker handshake timed out after ${HANDSHAKE_TIMEOUT_MS}ms — check streamWorkerFactory bundle and setStreamWorkerInit payload`,
            ),
          );
        }, HANDSHAKE_TIMEOUT_MS);
        // pass3-syn-154: clone wasmBytes into a fresh ArrayBuffer for
        // each spawn before transferring. The previous code transferred
        // `_init.wasmBytes` directly, which detached the original buffer
        // and left a zero-length view in `_init` — every spawn after the
        // first (e.g. retry after settleReject() clears readyPromise, or
        // a future second bridge instantiation) would post an empty
        // wasmBytes to the worker. Cloning costs one extra copy of the
        // wasm payload (tens of MB) per spawn but is the only correct
        // option: we cannot re-fetch the bytes from here, because the
        // original source is owned by the backend that called
        // `setStreamWorkerInit`. Spawns are rare (singleton + sticky
        // success caching) so the perf impact is negligible.
        const wasmBytesCopy = _init.wasmBytes.slice(0);
        const initMsg: WorkerRequest = {
          type: 'init',
          wasmBytes: wasmBytesCopy,
          moduleFactoryId: _init.moduleFactoryId,
        };
        // Transfer the fresh copy (not the original) — the worker
        // takes ownership and the main thread does not need it after
        // init. See pass2-syn-089 / pass3-syn-154.
        worker.postMessage(initMsg, [wasmBytesCopy]);
      } catch (err) {
        settleReject(err);
      }
    });
    return this.readyPromise;
  }

  /**
   * Start a stream and return an `AsyncIterable<T>` over the decoded
   * payloads. The bridge ensures the worker is spawned + ready before
   * the request is posted. Cancellation (`iterator.return()`) posts a
   * `cancel` message and ends the iterator deterministically.
   */
  getStreamIterator<T>(
    request: BridgeStreamRequest,
    codec: ProtoCodec<T>,
    options: StreamIteratorOptions<T> = {},
  ): AsyncIterable<T> {
    const requestId = `r${++this.requestCounter}`;
    const { stopWhen, onCancel } = options;
    return {
      [Symbol.asyncIterator]: (): AsyncIterator<T> => {
        const queue: T[] = [];
        const waiters: Array<{
          resolve(v: IteratorResult<T>): void;
          reject(e: unknown): void;
        }> = [];
        let started = false;
        let finished = false;

        const finish = (): void => {
          if (finished) return;
          finished = true;
          this.pending.delete(requestId);
          while (waiters.length > 0) {
            waiters.shift()!.resolve({ value: undefined as T, done: true });
          }
        };

        const fail = (err: unknown): void => {
          if (finished) return;
          finished = true;
          this.pending.delete(requestId);
          while (waiters.length > 0) waiters.shift()!.reject(err);
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
          this.pending.set(requestId, {
            emit: (payloadBytes) => {
              if (finished) return;
              try {
                emit(codec.decode(payloadBytes));
              } catch (err) {
                fail(err);
              }
            },
            finish: (returnCode) => {
              if (returnCode !== 0 && !finished) {
                fail(SDKException.fromRACResult(returnCode, toRequestKind(request)));
                return;
              }
              finish();
            },
            fail,
          });
          // Defer the actual postMessage onto a microtask so the
          // iterator handle is observable BEFORE native generation
          // starts — mirrors the main-thread `streamCallback` defer
          // (HOTSPOT-WEB-CORE-002 / WEB-CORE-001).
          queueMicrotask(() => {
            this.spawnWorker()
              .then(() => {
                if (finished || !this.worker) return;
                this.worker.postMessage(toWorkerRequest(request, requestId));
              })
              .catch((err) => fail(err));
          });
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
          return: (): Promise<IteratorResult<T>> => {
            try { onCancel?.(); } catch { /* swallow — cancel is best-effort */ }
            // Tell the worker to stop emitting (best-effort) and end the
            // iterator immediately. Any in-flight `callback` messages
            // for this requestId are dropped because `pending` is gone.
            if (started && !finished && this.worker) {
              const cancelMsg: WorkerRequest = { type: 'cancel', requestId };
              this.worker.postMessage(cancelMsg);
            }
            finish();
            return Promise.resolve({ value: undefined as T, done: true });
          },
        };
      },
    };
  }

  /** Tear down the worker and reject every pending iterator. */
  dispose(): void {
    this.failAll(new SDKException(-ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED, 'OffscreenRuntimeBridge disposed'));
    this.worker?.terminate();
    this.worker = null;
    this.readyPromise = null;
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  private _handshakeResolve: (() => void) | null = null;

  private handleResponse(msg: WorkerResponse): void {
    switch (msg.type) {
      case 'ready':
        this._handshakeResolve?.();
        this._handshakeResolve = null;
        return;
      case 'callback':
        this.pending.get(msg.requestId)?.emit(msg.payloadBytes);
        return;
      case 'done':
        this.pending.get(msg.requestId)?.finish(msg.returnCode);
        return;
      case 'error': {
        const err = new Error(msg.message);
        if (msg.requestId) {
          this.pending.get(msg.requestId)?.fail(err);
        } else {
          logger.warning(`stream worker reported error: ${msg.message}`);
          this.failAll(err);
        }
        return;
      }
    }
  }

  private failAll(err: unknown): void {
    for (const state of this.pending.values()) state.fail(err);
    this.pending.clear();
  }
}

let _warnedNoFactory = false;
let _warnedNoInit = false;

/**
 * Upper bound on the `init`→`ready` handshake. The design doc budgets
 * ~10-50 ms for a healthy cold-path bootstrap; this gives 100× headroom
 * so the timer only fires on genuine breakage (404 worker bundle,
 * malformed wasm, throw-before-onmessage). See pass2-syn-092.
 */
const HANDSHAKE_TIMEOUT_MS = 10_000;

function toRequestKind(req: BridgeStreamRequest): StreamRequestKind {
  return req.kind;
}

function toWorkerRequest(req: BridgeStreamRequest, requestId: string): WorkerRequest {
  switch (req.kind) {
    case 'stream.llm.generate':
      return {
        type: 'stream.llm.generate',
        requestId,
        handle: req.handle,
        requestBytes: req.requestBytes,
      };
    case 'stream.stt.transcribe':
      return {
        type: 'stream.stt.transcribe',
        requestId,
        handle: req.handle,
        audioBytes: req.audioBytes,
        optionsBytes: req.optionsBytes,
      };
    case 'stream.tts.synthesize':
      return {
        type: 'stream.tts.synthesize',
        requestId,
        handle: req.handle,
        text: req.text,
        optionsBytes: req.optionsBytes,
      };
    case 'stream.vlm.generate':
      return {
        type: 'stream.vlm.generate',
        requestId,
        requestBytes: req.requestBytes,
      };
  }
}
