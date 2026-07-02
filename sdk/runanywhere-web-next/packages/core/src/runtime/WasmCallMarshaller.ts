import { RAC_OK, RAC_ERROR_NOT_FOUND } from '../Foundation/RACErrors';
import type { WasmCallArg } from './WorkerProtocol';

export interface WorkerWasmModule {
  _malloc(size: number): number;
  _free(ptr: number): void;
  HEAPU8: Uint8Array;
  HEAPU32: Uint32Array;
  HEAP32: Int32Array;
  lengthBytesUTF8(str: string): number;
  stringToUTF8(str: string, ptr: number, maxBytesToWrite: number): void;
  UTF8ToString(ptr: number, maxBytesToRead?: number): string;
  ccall(
    name: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): unknown;
  _rac_proto_buffer_init(ptr: number): void;
  _rac_proto_buffer_free(ptr: number): void;
  _rac_wasm_sizeof_proto_buffer(): number;
  _rac_wasm_offsetof_proto_buffer_data(): number;
  _rac_wasm_offsetof_proto_buffer_size(): number;
  _rac_wasm_offsetof_proto_buffer_status(): number;
  _rac_wasm_offsetof_proto_buffer_error_message(): number;
  [key: string]: unknown;
}

export interface CallOutcome {
  rc: number;
  bytes: Uint8Array | null;
  outValues?: number[];
}

export interface MarshalledSlot {
  types: string[];
  values: Array<number | bigint>;
}

export async function runWasmCall(
  module: WorkerWasmModule,
  fn: string,
  args: WasmCallArg[],
): Promise<CallOutcome> {
  const toFree: number[] = [];
  const types: string[] = [];
  const values: Array<number | bigint> = [];
  let outProtoPtr = 0;
  let ownedBytes: { bytesPtr: number; sizePtr: number; freeFn: string } | null = null;
  const outU32Ptrs: number[] = [];

  try {
    for (const arg of args) {
      const slot = marshalArg(module, arg, toFree);
      types.push(...slot.types);
      values.push(...slot.values);
      if (arg.k === 'outProto') outProtoPtr = slot.values[0]! as number;
      else if (arg.k === 'outU32' || arg.k === 'outU64') outU32Ptrs.push(slot.values[0]! as number);
      else if (arg.k === 'outBytesSize') ownedBytes = { bytesPtr: slot.values[0]! as number, sizePtr: slot.values[1]! as number, freeFn: arg.freeFn };
    }

    const rcRaw = await module.ccall(fn, 'number', types, values, { async: true });
    const rc = Number(rcRaw);

    let bytes = outProtoPtr ? readProtoBuffer(module, outProtoPtr, rc) : null;
    if (ownedBytes) bytes = readOwnedBytes(module, ownedBytes, rc);
    const outValues = outU32Ptrs.length > 0 ? outU32Ptrs.map((p) => readU32(module, p)) : undefined;
    return { rc, bytes, outValues };
  } finally {
    if (outProtoPtr) module._rac_proto_buffer_free(outProtoPtr);
    for (const ptr of toFree) module._free(ptr);
  }
}

export function marshalArg(
  module: WorkerWasmModule,
  arg: WasmCallArg,
  toFree: number[],
  streamCallbackPtr?: number,
): MarshalledSlot {
  switch (arg.k) {
    case 'num':
      return { types: ['number'], values: [arg.v] };
    case 'u64':
      return { types: ['number'], values: [BigInt(arg.v)] };
    case 'string': {
      const size = module.lengthBytesUTF8(arg.v) + 1;
      const ptr = module._malloc(size);
      module.stringToUTF8(arg.v, ptr, size);
      toFree.push(ptr);
      return { types: ['number'], values: [ptr] };
    }
    case 'bytes': {
      const len = arg.v.byteLength;
      const ptr = module._malloc(Math.max(len, 1));
      module.HEAPU8.set(arg.v, ptr);
      toFree.push(ptr);
      return { types: ['number', 'number'], values: [ptr, len] };
    }
    case 'bytesPtr': {
      const ptr = module._malloc(Math.max(arg.v.byteLength, 1));
      module.HEAPU8.set(arg.v, ptr);
      toFree.push(ptr);
      return { types: ['number'], values: [ptr] };
    }
    case 'outProto': {
      const size = module._rac_wasm_sizeof_proto_buffer();
      const ptr = module._malloc(Math.max(size, 1));
      module._rac_proto_buffer_init(ptr);
      return { types: ['number'], values: [ptr] };
    }
    case 'outU32': {
      const ptr = module._malloc(4);
      module.HEAPU32[ptr >>> 2] = 0;
      toFree.push(ptr);
      return { types: ['number'], values: [ptr] };
    }
    case 'outU64': {
      const ptr = module._malloc(8);
      module.HEAPU32[ptr >>> 2] = 0;
      module.HEAPU32[(ptr + 4) >>> 2] = 0;
      toFree.push(ptr);
      return { types: ['number'], values: [ptr] };
    }
    case 'outBytesSize': {
      const bytesPtr = module._malloc(4);
      const sizePtr = module._malloc(4);
      module.HEAPU32[bytesPtr >>> 2] = 0;
      module.HEAPU32[sizePtr >>> 2] = 0;
      toFree.push(bytesPtr, sizePtr);
      return { types: ['number', 'number'], values: [bytesPtr, sizePtr] };
    }
    case 'streamCallback':
      if (streamCallbackPtr !== undefined) return { types: ['number'], values: [streamCallbackPtr] };
      throw new Error('runWasmCall does not handle streamCallback args; use the stream path');
  }
}

function readProtoBuffer(module: WorkerWasmModule, bufferPtr: number, rc: number): Uint8Array | null {
  const status = readI32(module, bufferPtr + module._rac_wasm_offsetof_proto_buffer_status());
  if (rc === RAC_ERROR_NOT_FOUND || status === RAC_ERROR_NOT_FOUND) return null;
  if (rc !== RAC_OK || status !== RAC_OK) return null;

  const dataPtr = readU32(module, bufferPtr + module._rac_wasm_offsetof_proto_buffer_data());
  const dataSize = readU32(module, bufferPtr + module._rac_wasm_offsetof_proto_buffer_size());
  if (!dataPtr || dataSize === 0) return new Uint8Array();
  return module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
}

function readOwnedBytes(
  module: WorkerWasmModule,
  owned: { bytesPtr: number; sizePtr: number; freeFn: string },
  rc: number,
): Uint8Array | null {
  const dataPtr = readU32(module, owned.bytesPtr);
  const dataSize = readU32(module, owned.sizePtr);
  let result: Uint8Array | null = null;
  if (rc === RAC_OK && dataPtr && dataSize) result = module.HEAPU8.slice(dataPtr, dataPtr + dataSize);
  if (dataPtr) {
    try { module.ccall(owned.freeFn, null, ['number'], [dataPtr]); } catch { /* best-effort free */ }
  }
  return result;
}

function readU32(module: WorkerWasmModule, ptr: number): number {
  return module.HEAPU32[ptr >>> 2] ?? 0;
}

function readI32(module: WorkerWasmModule, ptr: number): number {
  return module.HEAP32[ptr >>> 2] ?? 0;
}
