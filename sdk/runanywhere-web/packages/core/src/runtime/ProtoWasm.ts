import type { SDKLogger } from '../Foundation/SDKLogger';
import {
  RAC_OK as RAC_SUCCESS,
  RAC_ERROR_NOT_FOUND,
  RAC_ERROR_FEATURE_NOT_AVAILABLE,
  RAC_ERROR_INVALID_ARGUMENT,
} from '../Foundation/RACErrors';

const OUT_PTR_SIZE = 4;

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
  ccall?(
    fname: string,
    returnType: string | null,
    argTypes: string[],
    args: unknown[],
    opts?: { async?: boolean },
  ): unknown;

  _rac_wasm_infer_model_file_role?(filenamePtr: number, modalityProto: number): number;

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

  async withEncodedRequestAsync<Request, Result>(
    request: Request,
    requestCodec: ProtoCodec<Request>,
    resultCodec: ProtoCodec<Result>,
    call: (requestBytes: number, requestSize: number, outResult: number) => number | Promise<number>,
    functionName: string,
  ): Promise<Result | null> {
    const requestBytes = requestCodec.encode(request).finish();
    return this.withHeapBytesAsync(requestBytes, (ptr, size) => (
      this.callResultProtoAsync(resultCodec, (outResult) => call(ptr, size, outResult), functionName)
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

  async callResultProtoAsync<Result>(
    resultCodec: ProtoCodec<Result>,
    call: (outResult: number) => number | Promise<number>,
    functionName: string,
  ): Promise<Result | null> {
    const bytes = await this.readResultProtoAsync(call, functionName);
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

  async readResultProtoAsync(
    call: (outResult: number) => number | Promise<number>,
    functionName: string,
  ): Promise<Uint8Array | null> {
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
      const rc = await call(bufferPtr);
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

  async withHeapBytesAsync<T>(
    bytes: Uint8Array,
    fn: (bytesPtr: number, bytesLen: number) => T | Promise<T>,
  ): Promise<T> {
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
      return await fn(ptr, bytes.byteLength);
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

  /**
   * Infer the descriptor role for a sidecar filename. Delegates to the shared
   * commons classifier via the `rac_wasm_infer_model_file_role` WASM export so
   * the heuristic stays byte-identical with the C++ resolver and every other
   * SDK. `modalityProto` and the return value are proto `ModelCategory` /
   * `ModelFileRole` int values; returns `MODEL_FILE_ROLE_PRIMARY_MODEL` (1) on
   * any failure or when the export is unavailable.
   */
  inferModelFileRole(filename: string, modalityProto: number): number {
    const mod = this.module;
    const filenamePtr = this.allocUtf8(filename);
    if (!filenamePtr) {
      return 1; // MODEL_FILE_ROLE_PRIMARY_MODEL
    }
    try {
      if (typeof mod.ccall === 'function') {
        const result = mod.ccall(
          'rac_wasm_infer_model_file_role',
          'number',
          ['number', 'number'],
          [filenamePtr, modalityProto],
        );
        return Number(result);
      }
      if (mod._rac_wasm_infer_model_file_role) {
        return mod._rac_wasm_infer_model_file_role(filenamePtr, modalityProto);
      }
      this.logger.warning('rac_wasm_infer_model_file_role export unavailable');
      return 1; // MODEL_FILE_ROLE_PRIMARY_MODEL
    } finally {
      this.free(filenamePtr);
    }
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
    case RAC_ERROR_FEATURE_NOT_AVAILABLE:
      return 'RAC_ERROR_FEATURE_NOT_AVAILABLE';
    case RAC_ERROR_INVALID_ARGUMENT:
      return 'RAC_ERROR_INVALID_ARGUMENT';
    case -252:
      return 'RAC_ERROR_INVALID_FORMAT';
    default:
      return `rc=${rc}`;
  }
}
