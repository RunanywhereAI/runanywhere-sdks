import { SDKLogger } from '../Foundation/SDKLogger';

const OUT_PTR_SIZE = 4;
const RAC_SUCCESS = 0;
const RAC_ERROR_NOT_FOUND = -423;

export interface ProtoWasmModule {
  _malloc?(size: number): number;
  _free?(ptr: number): void;
  HEAPU8?: Uint8Array;
  HEAPU32?: Uint32Array;
  HEAP32?: Int32Array;
  UTF8ToString?(ptr: number, maxBytesToRead?: number): string;
  stringToUTF8?(str: string, ptr: number, maxBytesToWrite: number): void | number;
  lengthBytesUTF8?(str: string): number;
  getValue?(ptr: number, type: string): number;
  setValue?(ptr: number, value: number, type: string): void;

  _rac_proto_buffer_init?(bufferPtr: number): void;
  _rac_proto_buffer_free?(bufferPtr: number): void;
  _rac_wasm_sizeof_proto_buffer?(): number;
  _rac_wasm_offsetof_proto_buffer_data?(): number;
  _rac_wasm_offsetof_proto_buffer_size?(): number;
  _rac_wasm_offsetof_proto_buffer_status?(): number;
  _rac_wasm_offsetof_proto_buffer_error_message?(): number;
}

export interface ProtoCodec<T> {
  encode(message: T): { finish(): Uint8Array };
  decode(input: Uint8Array): T;
}

export class ProtoWasmBridge {
  constructor(
    private readonly module: ProtoWasmModule,
    private readonly logger: SDKLogger,
  ) {}

  hasProtoBufferExports(): boolean {
    return this.missingProtoBufferExports().length === 0;
  }

  missingProtoBufferExports(): string[] {
    const required: Array<keyof ProtoWasmModule> = [
      '_malloc',
      '_free',
      'HEAPU8',
      '_rac_proto_buffer_init',
      '_rac_proto_buffer_free',
      '_rac_wasm_sizeof_proto_buffer',
      '_rac_wasm_offsetof_proto_buffer_data',
      '_rac_wasm_offsetof_proto_buffer_size',
      '_rac_wasm_offsetof_proto_buffer_status',
      '_rac_wasm_offsetof_proto_buffer_error_message',
    ];
    return required.filter((key) => !this.module[key]).map(String);
  }

  withEncodedRequest<Request, Result>(
    request: Request,
    requestCodec: ProtoCodec<Request>,
    resultCodec: ProtoCodec<Result>,
    call: (requestBytes: number, requestSize: number, outResult: number) => number,
    functionName: string,
  ): Result | null {
    const requestBytes = requestCodec.encode(request).finish();
    return this.withHeapBytes(requestBytes, (ptr, size) => (
      this.callResultProto(resultCodec, (outResult) => call(ptr, size, outResult), functionName)
    ));
  }

  callResultProto<Result>(
    resultCodec: ProtoCodec<Result>,
    call: (outResult: number) => number,
    functionName: string,
  ): Result | null {
    const bytes = this.readResultProto(call, functionName);
    return bytes ? resultCodec.decode(bytes) : null;
  }

  readResultProto(
    call: (outResult: number) => number,
    functionName: string,
  ): Uint8Array | null {
    const mod = this.module;
    const missing = this.missingProtoBufferExports();
    if (missing.length > 0) {
      this.logger.warning(`${functionName}: module missing proto-buffer exports: ${missing.join(', ')}`);
      return null;
    }

    const size = mod._rac_wasm_sizeof_proto_buffer!();
    const bufferPtr = mod._malloc!(Math.max(size, 1));
    if (!bufferPtr) {
      this.logger.warning(`${functionName}: failed to allocate proto buffer`);
      return null;
    }

    try {
      mod._rac_proto_buffer_init!(bufferPtr);
      const rc = call(bufferPtr);
      const status = this.readI32(bufferPtr + mod._rac_wasm_offsetof_proto_buffer_status!());
      if (rc === RAC_ERROR_NOT_FOUND || status === RAC_ERROR_NOT_FOUND) {
        return null;
      }
      if (rc !== RAC_SUCCESS) {
        this.logger.warning(`${functionName} returned ${formatRacResult(rc)}`);
        return null;
      }
      if (status !== RAC_SUCCESS) {
        const messagePtr = this.readU32(
          bufferPtr + mod._rac_wasm_offsetof_proto_buffer_error_message!(),
        );
        const message = messagePtr && mod.UTF8ToString ? mod.UTF8ToString(messagePtr) : '';
        this.logger.warning(
          `${functionName} buffer status ${formatRacResult(status)}${message ? `: ${message}` : ''}`,
        );
        return null;
      }

      const dataPtr = this.readU32(bufferPtr + mod._rac_wasm_offsetof_proto_buffer_data!());
      const dataSize = this.readU32(bufferPtr + mod._rac_wasm_offsetof_proto_buffer_size!());
      if (!dataPtr || dataSize === 0) {
        return new Uint8Array();
      }
      return mod.HEAPU8!.slice(dataPtr, dataPtr + dataSize);
    } finally {
      mod._rac_proto_buffer_free!(bufferPtr);
      mod._free!(bufferPtr);
    }
  }

  withHeapBytes<T>(bytes: Uint8Array, fn: (bytesPtr: number, bytesLen: number) => T): T {
    const mod = this.module;
    if (!mod._malloc || !mod._free || !mod.HEAPU8) {
      throw new Error('RunAnywhere WASM module is missing heap allocation helpers');
    }
    const ptr = mod._malloc(Math.max(bytes.byteLength, 1));
    if (!ptr) {
      throw new Error('Failed to allocate bytes in the RunAnywhere WASM heap');
    }
    try {
      mod.HEAPU8.set(bytes, ptr);
      return fn(ptr, bytes.byteLength);
    } finally {
      mod._free(ptr);
    }
  }

  allocUtf8(value: string): number {
    const mod = this.module;
    if (!mod._malloc || !mod.lengthBytesUTF8 || !mod.stringToUTF8) {
      this.logger.warning('module missing UTF-8 allocation helpers');
      return 0;
    }
    const size = mod.lengthBytesUTF8(value) + 1;
    const ptr = mod._malloc(size);
    if (!ptr) {
      this.logger.warning('failed to allocate UTF-8 string in WASM heap');
      return 0;
    }
    mod.stringToUTF8(value, ptr, size);
    return ptr;
  }

  free(ptr: number): void {
    this.module._free?.(ptr);
  }

  readU32(ptr: number): number {
    const mod = this.module;
    if (mod.HEAPU32) return mod.HEAPU32[ptr >>> 2] ?? 0;
    if (mod.getValue) return mod.getValue(ptr, '*') >>> 0;
    return 0;
  }

  writeU32(ptr: number, value: number): void {
    const mod = this.module;
    if (mod.HEAPU32) {
      mod.HEAPU32[ptr >>> 2] = value;
      return;
    }
    mod.setValue?.(ptr, value, '*');
  }

  allocOutPtr(): number {
    const mod = this.module;
    if (!mod._malloc) return 0;
    const ptr = mod._malloc(OUT_PTR_SIZE);
    if (ptr) this.writeU32(ptr, 0);
    return ptr;
  }

  private readI32(ptr: number): number {
    const mod = this.module;
    if (mod.HEAP32) return mod.HEAP32[ptr >>> 2] ?? 0;
    if (mod.getValue) return mod.getValue(ptr, 'i32') | 0;
    return 0;
  }
}

export function formatRacResult(rc: number): string {
  switch (rc) {
    case RAC_SUCCESS:
      return 'RAC_SUCCESS';
    case RAC_ERROR_NOT_FOUND:
      return 'RAC_ERROR_NOT_FOUND';
    case -801:
      return 'RAC_ERROR_FEATURE_NOT_AVAILABLE';
    case -259:
      return 'RAC_ERROR_INVALID_ARGUMENT';
    case -252:
      return 'RAC_ERROR_INVALID_FORMAT';
    default:
      return `rc=${rc}`;
  }
}
