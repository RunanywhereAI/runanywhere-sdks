export type WasmCallArg =
  | { k: 'num'; v: number }
  | { k: 'u64'; v: number }
  | { k: 'string'; v: string }
  | { k: 'bytes'; v: Uint8Array }
  | { k: 'bytesPtr'; v: Uint8Array }
  | { k: 'outProto' }
  | { k: 'outU32' }
  | { k: 'outU64' }
  | { k: 'outBytesSize'; freeFn: string }
  | { k: 'streamCallback'; returnsBool: boolean };

export interface WorkerInit {
  moduleId: string;
  wasmJsUrl: string;
  logLevel?: number;
  registerFns?: string[];
}

export type WorkerRequest =
  | ({ type: 'init'; id: number } & WorkerInit)
  | { type: 'call'; id: number; fn: string; args: WasmCallArg[] }
  | { type: 'stream'; id: number; fn: string; args: WasmCallArg[]; persistent?: { unsubscribeFn: string; unsubscribeArgs?: WasmCallArg[] } }
  | { type: 'cancel'; id: number }
  | { type: 'shutdown'; id: number };

export type WorkerResponse =
  | { type: 'ready'; id: number }
  | { type: 'result'; id: number; rc: number; bytes: Uint8Array | null; outValues?: number[] }
  | { type: 'stream-open'; id: number; rc: number; outValues?: number[] }
  | { type: 'callback'; id: number; payload: Uint8Array }
  | { type: 'done'; id: number; rc: number }
  | { type: 'error'; id?: number; message: string };
