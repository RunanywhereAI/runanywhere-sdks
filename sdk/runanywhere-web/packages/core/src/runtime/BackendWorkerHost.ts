/**
 * Main-thread host for the backend worker RPC protocol.
 *
 * @internal
 */

import type {
  BackendWorkerDiagnostics,
  BackendWorkerHealthResponse,
  BackendWorkerInferenceKind,
  BackendWorkerModality,
  BackendWorkerRequest,
  BackendWorkerResponse,
} from './BackendWorkerProtocol.js';

export interface BackendWorkerLike {
  onmessage: ((event: MessageEvent<BackendWorkerResponse>) => void) | null;
  onerror: ((event: ErrorEvent) => void) | null;
  postMessage(message: BackendWorkerRequest, transfer?: Transferable[]): void;
  terminate(): void;
}

export type BackendWorkerFactory = () => BackendWorkerLike;

export interface BackendWorkerHostOptions {
  initTimeoutMs?: number;
}

export class BackendWorkerError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BackendWorkerError';
  }
}

export class BackendWorkerCrashedError extends BackendWorkerError {
  constructor(message = 'Backend worker terminated unexpectedly') {
    super(message);
    this.name = 'BackendWorkerCrashedError';
  }
}

interface UnaryPending {
  kind: 'unary';
  resolve(value: unknown): void;
  reject(reason: unknown): void;
}

interface StreamPending {
  kind: 'stream';
  events: unknown[];
  waiters: Array<{
    resolve(value: IteratorResult<unknown>): void;
    reject(reason: unknown): void;
  }>;
  finished: boolean;
}

type PendingRequest = UnaryPending | StreamPending;

const defaultInitTimeoutMs = 10_000;
let activeHost: BackendWorkerHost | null = null;

/** Current worker-runtime state for `RunAnywhere.runtime` diagnostics. */
export function getBackendWorkerRuntimeDiagnostics(): BackendWorkerDiagnostics {
  return activeHost?.diagnostics ?? { executionContext: 'main', queueDepth: 0 };
}

/**
 * Lazily creates a backend Worker and routes unary and stream RPC calls.
 * A worker crash rejects active calls and resets the host to main-thread
 * diagnostics; a later call can start a fresh Worker from the same factory.
 */
export class BackendWorkerHost {
  private worker: BackendWorkerLike | null = null;
  private ready: Promise<void> | null = null;
  private initResolve: (() => void) | null = null;
  private initReject: ((reason: unknown) => void) | null = null;
  private requestCounter = 0;
  private readonly pending = new Map<string, PendingRequest>();
  private executionContext: 'main' | 'worker' = 'main';

  constructor(
    private readonly factory: BackendWorkerFactory,
    private readonly options: BackendWorkerHostOptions = {},
  ) {
    activeHost = this;
  }

  get diagnostics(): BackendWorkerDiagnostics {
    return {
      executionContext: this.executionContext,
      queueDepth: this.pending.size,
    };
  }

  async init(payload?: unknown, transfer?: Transferable[]): Promise<void> {
    if (this.ready) return this.ready;
    const requestId = this.nextRequestId('init');
    this.ready = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.initReject = null;
        this.initResolve = null;
        this.ready = null;
        this.worker?.terminate();
        this.worker = null;
        reject(new BackendWorkerError(
          `Backend worker init handshake timed out after ${this.options.initTimeoutMs ?? defaultInitTimeoutMs}ms`,
        ));
      }, this.options.initTimeoutMs ?? defaultInitTimeoutMs);

      this.initResolve = () => {
        clearTimeout(timeout);
        this.initResolve = null;
        this.initReject = null;
        this.executionContext = 'worker';
        resolve();
      };
      this.initReject = (error: unknown) => {
        clearTimeout(timeout);
        this.initResolve = null;
        this.initReject = null;
        this.ready = null;
        this.executionContext = 'main';
        this.worker?.terminate();
        this.worker = null;
        reject(error);
      };

      try {
        const worker = this.factory();
        this.worker = worker;
        worker.onmessage = (event) => this.handleResponse(event.data);
        worker.onerror = (event) => this.handleCrash(
          new BackendWorkerCrashedError(`Backend worker error: ${event.message || '<unknown>'}`),
        );
        worker.postMessage({ type: 'init', requestId, payload }, transfer);
      } catch (error) {
        this.initReject?.(error);
      }
    });
    return this.ready;
  }

  async loadModel(
    modality: BackendWorkerModality,
    payload: unknown,
    transfer?: Transferable[],
  ): Promise<unknown> {
    return this.request('loadModel', { modality, payload }, transfer);
  }

  async unloadModel(
    modality: BackendWorkerModality,
    payload?: unknown,
    transfer?: Transferable[],
  ): Promise<unknown> {
    return this.request('unloadModel', { modality, payload }, transfer);
  }

  async infer(
    kind: BackendWorkerInferenceKind,
    payload: unknown,
    transfer?: Transferable[],
  ): Promise<unknown> {
    return this.request('infer', { kind, payload }, transfer);
  }

  stream(
    kind: BackendWorkerInferenceKind,
    payload: unknown,
    transfer?: Transferable[],
  ): AsyncIterable<unknown> {
    const requestId = this.nextRequestId('stream');
    let started = false;
    const state: StreamPending = { kind: 'stream', events: [], waiters: [], finished: false };

    const finish = (): void => {
      if (state.finished) return;
      state.finished = true;
      this.pending.delete(requestId);
      while (state.waiters.length) {
        state.waiters.shift()!.resolve({ value: undefined, done: true });
      }
    };
    const fail = (error: unknown): void => {
      if (state.finished) return;
      state.finished = true;
      this.pending.delete(requestId);
      while (state.waiters.length) state.waiters.shift()!.reject(error);
    };
    const start = (): void => {
      if (started) return;
      started = true;
      this.pending.set(requestId, state);
      void this.init()
        .then(() => this.post({ type: 'stream', requestId, kind, payload }, transfer))
        .catch(fail);
    };

    return {
      [Symbol.asyncIterator]: (): AsyncIterator<unknown> => ({
        next: (): Promise<IteratorResult<unknown>> => {
          start();
          if (state.events.length) {
            return Promise.resolve({ value: state.events.shift(), done: false });
          }
          if (state.finished) return Promise.resolve({ value: undefined, done: true });
          return new Promise((resolve, reject) => state.waiters.push({ resolve, reject }));
        },
        return: (): Promise<IteratorResult<unknown>> => {
          if (started && !state.finished) this.cancel(requestId);
          finish();
          return Promise.resolve({ value: undefined, done: true });
        },
      }),
    };
  }

  cancel(targetRequestId: string): void {
    if (!this.worker) return;
    this.post({
      type: 'cancel',
      requestId: this.nextRequestId('cancel'),
      targetRequestId,
    });
  }

  async health(): Promise<BackendWorkerHealthResponse> {
    return this.request('health', {}) as Promise<BackendWorkerHealthResponse>;
  }

  async teardown(): Promise<void> {
    try {
      await this.request('teardown', {});
    } finally {
      this.dispose();
    }
  }

  dispose(): void {
    const error = new BackendWorkerError('Backend worker host disposed');
    this.rejectAll(error);
    this.initReject?.(error);
    this.initReject = null;
    this.initResolve = null;
    this.worker?.terminate();
    this.worker = null;
    this.ready = null;
    this.executionContext = 'main';
    if (activeHost === this) activeHost = null;
  }

  private async request(
    type: 'loadModel' | 'unloadModel' | 'infer' | 'health' | 'teardown',
    fields: Record<string, unknown>,
    transfer?: Transferable[],
  ): Promise<unknown> {
    await this.init();
    const requestId = this.nextRequestId(type);
    return new Promise<unknown>((resolve, reject) => {
      this.pending.set(requestId, { kind: 'unary', resolve, reject });
      try {
        this.post({ type, requestId, ...fields } as BackendWorkerRequest, transfer);
      } catch (error) {
        this.pending.delete(requestId);
        reject(error);
      }
    });
  }

  private post(request: BackendWorkerRequest, transfer?: Transferable[]): void {
    if (!this.worker) throw new BackendWorkerCrashedError();
    this.worker.postMessage(request, transfer);
  }

  private handleResponse(response: BackendWorkerResponse): void {
    if (response.type === 'ready') {
      this.initResolve?.();
      return;
    }
    if (response.type === 'error') {
      const error = new BackendWorkerError(response.message);
      if (response.requestId) {
        this.failRequest(response.requestId, error);
      } else {
        this.handleCrash(error);
      }
      return;
    }

    const pending = this.pending.get(response.requestId);
    if (!pending) return;
    if (pending.kind === 'unary') {
      if (response.type === 'result' || response.type === 'complete' || response.type === 'health') {
        this.pending.delete(response.requestId);
        pending.resolve(response.type === 'health' ? response : response.result);
      }
      return;
    }

    if (response.type === 'streamEvent' && !pending.finished) {
      if (pending.waiters.length) {
        pending.waiters.shift()!.resolve({ value: response.payload, done: false });
      } else {
        pending.events.push(response.payload);
      }
    } else if (response.type === 'complete') {
      pending.finished = true;
      this.pending.delete(response.requestId);
      while (pending.waiters.length) pending.waiters.shift()!.resolve({ value: undefined, done: true });
    }
  }

  private failRequest(requestId: string, error: unknown): void {
    const pending = this.pending.get(requestId);
    if (!pending) return;
    this.pending.delete(requestId);
    if (pending.kind === 'unary') {
      pending.reject(error);
      return;
    }
    pending.finished = true;
    while (pending.waiters.length) pending.waiters.shift()!.reject(error);
  }

  private handleCrash(error: unknown): void {
    this.executionContext = 'main';
    this.ready = null;
    this.worker?.terminate();
    this.worker = null;
    this.initReject?.(error);
    this.initReject = null;
    this.initResolve = null;
    this.rejectAll(error);
  }

  private rejectAll(error: unknown): void {
    for (const requestId of [...this.pending.keys()]) this.failRequest(requestId, error);
  }

  private nextRequestId(prefix: string): string {
    this.requestCounter += 1;
    return `${prefix}-${this.requestCounter}`;
  }
}
