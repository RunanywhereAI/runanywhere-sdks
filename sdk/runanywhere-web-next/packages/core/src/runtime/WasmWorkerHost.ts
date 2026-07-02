import { ProtoErrorCode, SDKException } from '../Foundation/SDKException';
import { SDKLogger } from '../Foundation/SDKLogger';
import type {
  WasmCallArg,
  WorkerInit,
  WorkerRequest,
  WorkerResponse,
} from './WorkerProtocol';

const HANDSHAKE_TIMEOUT_MS = 10_000;

export interface CallResult {
  rc: number;
  bytes: Uint8Array | null;
  outValues?: number[];
}

interface CallWaiter {
  resolve(result: CallResult): void;
  reject(err: unknown): void;
}

interface StreamSink {
  emit(payload: Uint8Array): void;
  done(rc: number): void;
  fail(err: unknown): void;
  open?(rc: number, outValues?: number[]): void;
}

export class WasmWorkerHost {
  private worker: Worker | null = null;
  private readyPromise: Promise<void> | null = null;
  private handshakeResolve: (() => void) | null = null;
  private nextId = 1;
  private _telemetryManagerPtr = 0;

  /** Telemetry-manager pointer reported by the worker at init (0 if telemetry
   * is not wired). Valid only for calls executed inside this worker. */
  get telemetryManagerPtr(): number {
    return this._telemetryManagerPtr;
  }
  private readonly calls = new Map<number, CallWaiter>();
  private readonly streams = new Map<number, StreamSink>();

  constructor(
    private readonly factory: () => Worker,
    private readonly init: WorkerInit,
    private readonly logger: SDKLogger = new SDKLogger(`WasmWorkerHost:${init.moduleId}`),
  ) {}

  ensureReady(): Promise<void> {
    if (this.readyPromise) return this.readyPromise;
    this.readyPromise = new Promise<void>((resolve, reject) => {
      let timer: ReturnType<typeof setTimeout> | null = null;
      const settleReject = (err: unknown): void => {
        if (timer != null) { clearTimeout(timer); timer = null; }
        this.handshakeResolve = null;
        try { this.worker?.terminate(); } catch {}
        this.worker = null;
        this.readyPromise = null;
        reject(err instanceof Error ? err : new Error(String(err)));
      };
      try {
        const worker = this.factory();
        this.worker = worker;
        worker.onmessage = (ev: MessageEvent<WorkerResponse>) => this.handleResponse(ev.data);
        worker.onerror = (ev: ErrorEvent) => {
          const message = `worker error: ${ev.message ?? '<unknown>'}`;
          this.logger.warning(message);
          if (this.handshakeResolve) settleReject(new Error(message));
          this.failAll(new Error(message));
        };
        const id = this.nextId++;
        this.handshakeResolve = () => {
          if (timer != null) { clearTimeout(timer); timer = null; }
          this.handshakeResolve = null;
          resolve();
        };
        timer = setTimeout(() => {
          timer = null;
          settleReject(
            new SDKException(
              -ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED,
              `worker handshake timed out after ${HANDSHAKE_TIMEOUT_MS}ms (${this.init.moduleId})`,
            ),
          );
        }, HANDSHAKE_TIMEOUT_MS);
        const initMsg: WorkerRequest = { type: 'init', id, ...this.init };
        worker.postMessage(initMsg);
      } catch (err) {
        settleReject(err);
      }
    });
    return this.readyPromise;
  }

  async call(fn: string, args: WasmCallArg[]): Promise<CallResult> {
    await this.ensureReady();
    const id = this.nextId++;
    return new Promise<CallResult>((resolve, reject) => {
      this.calls.set(id, { resolve, reject });
      const msg: WorkerRequest = { type: 'call', id, fn, args };
      this.worker!.postMessage(msg);
    });
  }

  stream(
    fn: string,
    args: WasmCallArg[],
    persistent?: { unsubscribeFn: string; unsubscribeArgs?: WasmCallArg[] },
    onOpen?: (rc: number, outValues?: number[]) => void,
  ): AsyncIterable<Uint8Array> {
    return {
      [Symbol.asyncIterator]: (): AsyncIterator<Uint8Array> => {
        const queue: Uint8Array[] = [];
        const waiters: Array<{
          resolve(v: IteratorResult<Uint8Array>): void;
          reject(e: unknown): void;
        }> = [];
        let started = false;
        let finished = false;
        let id = 0;

        const finish = (): void => {
          if (finished) return;
          finished = true;
          this.streams.delete(id);
          while (waiters.length > 0) {
            waiters.shift()!.resolve({ value: undefined as unknown as Uint8Array, done: true });
          }
        };
        const fail = (err: unknown): void => {
          if (finished) return;
          finished = true;
          this.streams.delete(id);
          while (waiters.length > 0) waiters.shift()!.reject(err);
        };
        const emit = (payload: Uint8Array): void => {
          if (finished) return;
          if (waiters.length > 0) waiters.shift()!.resolve({ value: payload, done: false });
          else queue.push(payload);
        };

        const start = (): void => {
          if (started) return;
          started = true;
          id = this.nextId++;
          this.streams.set(id, {
            emit,
            done: (rc) => {
              if (rc !== 0) fail(SDKException.fromRACResult(rc, fn));
              else finish();
            },
            fail,
            open: onOpen,
          });
          this.ensureReady()
            .then(() => {
              if (finished || !this.worker) return;
              const msg: WorkerRequest = { type: 'stream', id, fn, args, persistent };
              this.worker.postMessage(msg);
            })
            .catch(fail);
        };

        return {
          next: (): Promise<IteratorResult<Uint8Array>> => {
            start();
            if (queue.length > 0) return Promise.resolve({ value: queue.shift()!, done: false });
            if (finished) return Promise.resolve({ value: undefined as unknown as Uint8Array, done: true });
            return new Promise((resolve, reject) => waiters.push({ resolve, reject }));
          },
          return: (): Promise<IteratorResult<Uint8Array>> => {
            if (started && !finished && this.worker) {
              const cancelMsg: WorkerRequest = { type: 'cancel', id };
              this.worker.postMessage(cancelMsg);
            }
            finish();
            return Promise.resolve({ value: undefined as unknown as Uint8Array, done: true });
          },
        };
      },
    };
  }

  shutdown(): void {
    const err = new SDKException(-ProtoErrorCode.ERROR_CODE_WASM_NOT_LOADED, `worker shut down (${this.init.moduleId})`);
    this.failAll(err);
    if (this.worker) {
      const msg: WorkerRequest = { type: 'shutdown', id: this.nextId++ };
      try { this.worker.postMessage(msg); } catch {}
      this.worker.terminate();
    }
    this.worker = null;
    this.readyPromise = null;
    this.handshakeResolve = null;
  }

  private handleResponse(msg: WorkerResponse): void {
    switch (msg.type) {
      case 'ready':
        this._telemetryManagerPtr = msg.telemetryManagerPtr ?? 0;
        this.handshakeResolve?.();
        return;
      case 'result': {
        const waiter = this.calls.get(msg.id);
        if (waiter) { this.calls.delete(msg.id); waiter.resolve({ rc: msg.rc, bytes: msg.bytes, outValues: msg.outValues }); }
        return;
      }
      case 'stream-open':
        this.streams.get(msg.id)?.open?.(msg.rc, msg.outValues);
        return;
      case 'callback':
        this.streams.get(msg.id)?.emit(msg.payload);
        return;
      case 'done':
        this.streams.get(msg.id)?.done(msg.rc);
        return;
      case 'error': {
        const err = new Error(msg.message);
        if (msg.id != null) {
          const waiter = this.calls.get(msg.id);
          if (waiter) { this.calls.delete(msg.id); waiter.reject(err); return; }
          this.streams.get(msg.id)?.fail(err);
        } else {
          this.logger.warning(`worker fatal error: ${msg.message}`);
          this.failAll(err);
        }
        return;
      }
    }
  }

  private failAll(err: unknown): void {
    for (const w of this.calls.values()) w.reject(err);
    this.calls.clear();
    for (const s of this.streams.values()) s.fail(err);
    this.streams.clear();
  }
}
