import { SDKException } from '../Foundation/SDKException';
import { createSecureStore } from '../Infrastructure/OpfsSecureStore';
import { loadWasmModule, type LoadedModule } from './WasmModuleLoader';
import { marshalArg, runWasmCall } from './WasmCallMarshaller';
import type { SecureStore } from './PlatformAdapter';
import type { WasmCallArg, WorkerRequest, WorkerResponse } from './WorkerProtocol';

export type PostResponse = (msg: WorkerResponse, transfer?: Transferable[]) => void;

interface ActiveStream {
  callbackPtr: number;
  cancelled: boolean;
}

interface Subscription {
  callbackPtr: number;
  unsubscribeFn: string;
  unsubscribeArgs: WasmCallArg[];
}

export class WasmWorkerServer {
  private loaded: LoadedModule | null = null;
  private readonly streams = new Map<number, ActiveStream>();
  private readonly subscriptions = new Map<number, Subscription>();

  constructor(
    private readonly post: PostResponse,
    private readonly secureStore?: SecureStore,
  ) {}

  async handle(req: WorkerRequest): Promise<void> {
    try {
      switch (req.type) {
        case 'init': return await this.onInit(req);
        case 'call': return await this.onCall(req);
        case 'stream': return await this.onStream(req);
        case 'cancel': return this.onCancel(req);
        case 'shutdown': return this.onShutdown(req);
      }
    } catch (err) {
      this.post({ type: 'error', id: req.id, message: message(err) });
    }
  }

  private async onInit(req: Extract<WorkerRequest, { type: 'init' }>): Promise<void> {
    const secureStore = this.secureStore ?? await createSecureStore();
    this.loaded = await loadWasmModule({
      wasmJsUrl: req.wasmJsUrl,
      logLevel: req.logLevel,
      registerFns: req.registerFns,
      secureStore,
      telemetry: req.telemetry,
    });
    this.post({ type: 'ready', id: req.id, telemetryManagerPtr: this.loaded.telemetry?.managerPtr ?? 0 });
  }

  private async onCall(req: Extract<WorkerRequest, { type: 'call' }>): Promise<void> {
    const module = this.module();
    const { rc, bytes, outValues } = await runWasmCall(module, req.fn, req.args);
    this.post({ type: 'result', id: req.id, rc, bytes, outValues }, bytes ? [bytes.buffer] : undefined);
  }

  private async onStream(req: Extract<WorkerRequest, { type: 'stream' }>): Promise<void> {
    const module = this.module();
    const scArg = req.args.find((a) => a.k === 'streamCallback');
    const returnsBool = scArg?.k === 'streamCallback' ? scArg.returnsBool : false;

    const state: ActiveStream = { callbackPtr: 0, cancelled: false };
    const callbackPtr = module.addFunction((bytesPtr: number, size: number) => {
      if (bytesPtr && size > 0) {
        const payload = module.HEAPU8.slice(bytesPtr, bytesPtr + size);
        this.post({ type: 'callback', id: req.id, payload }, [payload.buffer]);
      }
      return returnsBool ? (state.cancelled ? 0 : 1) : undefined;
    }, returnsBool ? 'iiii' : 'viii');
    state.callbackPtr = callbackPtr;
    if (!req.persistent) this.streams.set(req.id, state);

    const toFree: number[] = [];
    const types: string[] = [];
    const values: Array<number | bigint> = [];
    const outU32Ptrs: number[] = [];
    try {
      for (const arg of req.args) {
        const slot = marshalArg(module, arg, toFree, callbackPtr);
        types.push(...slot.types);
        values.push(...slot.values);
        if (arg.k === 'outU32' || arg.k === 'outU64') outU32Ptrs.push(slot.values[0]! as number);
      }
      const rc = Number(await module.ccall(req.fn, 'number', types, values, { async: true }));
      if (req.persistent) {
        const outValues = outU32Ptrs.length > 0 ? outU32Ptrs.map((p) => module.HEAPU32[p >>> 2] ?? 0) : undefined;
        this.post({ type: 'stream-open', id: req.id, rc, outValues });
        const unsubscribeArgs = req.persistent.unsubscribeArgs ?? [{ k: 'num', v: rc }];
        this.subscriptions.set(req.id, { callbackPtr, unsubscribeFn: req.persistent.unsubscribeFn, unsubscribeArgs });
      } else {
        this.post({ type: 'done', id: req.id, rc });
        module.removeFunction(callbackPtr);
        this.streams.delete(req.id);
      }
    } catch (err) {
      module.removeFunction(callbackPtr);
      this.streams.delete(req.id);
      throw err;
    } finally {
      for (const ptr of toFree) module._free(ptr);
    }
  }

  private onCancel(req: Extract<WorkerRequest, { type: 'cancel' }>): void {
    const sub = this.subscriptions.get(req.id);
    if (sub) {
      this.runUnsubscribe(sub);
      this.subscriptions.delete(req.id);
      return;
    }
    const stream = this.streams.get(req.id);
    if (stream) stream.cancelled = true;
  }

  private onShutdown(_req: Extract<WorkerRequest, { type: 'shutdown' }>): void {
    if (!this.loaded) return;
    for (const sub of this.subscriptions.values()) this.runUnsubscribe(sub);
    this.subscriptions.clear();
    try { this.loaded.telemetry?.flush(); } catch {}
    try { this.loaded.telemetry?.uninstall(); } catch {}
    try { this.loaded.module._rac_shutdown?.(); } catch {}
    this.loaded.adapter.cleanup();
    this.loaded = null;
  }

  private runUnsubscribe(sub: Subscription): void {
    const module = this.loaded?.module;
    if (!module) return;
    const toFree: number[] = [];
    const types: string[] = [];
    const values: Array<number | bigint> = [];
    try {
      for (const arg of sub.unsubscribeArgs) {
        const slot = marshalArg(module, arg, toFree);
        types.push(...slot.types);
        values.push(...slot.values);
      }
      try { module.ccall(sub.unsubscribeFn, 'number', types, values); } catch {}
      try { module.removeFunction(sub.callbackPtr); } catch {}
    } finally {
      for (const ptr of toFree) module._free(ptr);
    }
  }

  private module(): LoadedModule['module'] {
    if (!this.loaded) throw SDKException.wasmNotLoaded('worker module not initialized');
    return this.loaded.module;
  }
}

function message(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
