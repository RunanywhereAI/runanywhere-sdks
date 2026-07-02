import type { CallResult, WasmWorkerHost } from './WasmWorkerHost';
import type { WasmCallArg } from './WorkerProtocol';

export interface ProtoCodec<T> {
  encode(message: T): { finish(): Uint8Array };
  decode(input: Uint8Array): T;
}

export const Arg = {
  num: (v: number): WasmCallArg => ({ k: 'num', v }),
  u64: (v: number): WasmCallArg => ({ k: 'u64', v }),
  string: (v: string): WasmCallArg => ({ k: 'string', v }),
  bytes: (v: Uint8Array): WasmCallArg => ({ k: 'bytes', v }),
  bytesPtr: (v: Uint8Array): WasmCallArg => ({ k: 'bytesPtr', v }),
  outProto: (): WasmCallArg => ({ k: 'outProto' }),
  outU32: (): WasmCallArg => ({ k: 'outU32' }),
  outU64: (): WasmCallArg => ({ k: 'outU64' }),
  outBytesSize: (freeFn: string): WasmCallArg => ({ k: 'outBytesSize', freeFn }),
  streamCb: (returnsBool: boolean): WasmCallArg => ({ k: 'streamCallback', returnsBool }),
};

export class WorkerProtoClient {
  constructor(private readonly host: WasmWorkerHost) {}

  async callProto<T>(fn: string, args: WasmCallArg[], resCodec: ProtoCodec<T>): Promise<T | null> {
    const { bytes } = await this.host.call(fn, args);
    return bytes ? resCodec.decode(bytes) : null;
  }

  call(fn: string, args: WasmCallArg[]): Promise<CallResult> {
    return this.host.call(fn, args);
  }

  async callRc(fn: string, args: WasmCallArg[]): Promise<number> {
    return (await this.host.call(fn, args)).rc;
  }

  async collectProto<T>(fn: string, args: WasmCallArg[], evCodec: ProtoCodec<T>): Promise<T[]> {
    const out: T[] = [];
    for await (const bytes of this.host.stream(fn, args)) out.push(evCodec.decode(bytes));
    return out;
  }

  streamProto<T>(
    fn: string,
    args: WasmCallArg[],
    evCodec: ProtoCodec<T>,
    opts: { stopWhen?: (event: T) => boolean; persistent?: { unsubscribeFn: string; unsubscribeArgs?: WasmCallArg[] } } = {},
  ): AsyncIterable<T> {
    const host = this.host;
    const { stopWhen, persistent } = opts;
    return {
      [Symbol.asyncIterator](): AsyncIterator<T> {
        const inner = host.stream(fn, args, persistent)[Symbol.asyncIterator]();
        let done = false;
        return {
          async next(): Promise<IteratorResult<T>> {
            if (done) return { value: undefined as unknown as T, done: true };
            const raw = await inner.next();
            if (raw.done) {
              done = true;
              return { value: undefined as unknown as T, done: true };
            }
            const event = evCodec.decode(raw.value);
            if (stopWhen?.(event)) {
              done = true;
              await inner.return?.();
            }
            return { value: event, done: false };
          },
          async return(): Promise<IteratorResult<T>> {
            done = true;
            await inner.return?.();
            return { value: undefined as unknown as T, done: true };
          },
        };
      },
    };
  }

  subscribeWithHandle<T>(
    fn: string,
    unsubscribe: { fn: string; args?: WasmCallArg[] },
    args: WasmCallArg[],
    evCodec: ProtoCodec<T>,
    onEvent: (event: T) => void,
  ): Promise<{ handle: number; unsubscribe: () => void }> {
    return new Promise((resolve, reject) => {
      let settled = false;
      const iterator = this.host.stream(
        fn,
        args,
        { unsubscribeFn: unsubscribe.fn, unsubscribeArgs: unsubscribe.args },
        (_rc, outValues) => {
          if (settled) return;
          settled = true;
          resolve({ handle: outValues?.[0] ?? 0, unsubscribe: () => { void iterator.return?.(); } });
        },
      )[Symbol.asyncIterator]();
      void (async () => {
        try {
          for (;;) {
            const raw = await iterator.next();
            if (raw.done) break;
            onEvent(evCodec.decode(raw.value));
          }
        } catch (err) {
          if (!settled) { settled = true; reject(err); }
        }
      })();
    });
  }

  subscribe<T>(
    fn: string,
    unsubscribe: { fn: string; args?: WasmCallArg[] },
    args: WasmCallArg[],
    evCodec: ProtoCodec<T>,
    onEvent: (event: T) => void,
  ): () => void {
    const iterator = this.host.stream(fn, args, {
      unsubscribeFn: unsubscribe.fn,
      unsubscribeArgs: unsubscribe.args,
    })[Symbol.asyncIterator]();
    void (async () => {
      try {
        for (;;) {
          const raw = await iterator.next();
          if (raw.done) break;
          onEvent(evCodec.decode(raw.value));
        }
      } catch {

      }
    })();
    return () => { void iterator.return?.(); };
  }
}
