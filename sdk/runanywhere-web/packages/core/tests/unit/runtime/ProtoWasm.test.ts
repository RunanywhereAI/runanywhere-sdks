import { describe, expect, it, vi } from 'vitest';
import { SDKLogger } from '../../../src/Foundation/SDKLogger';
import {
  ProtoWasmBridge,
  type ProtoWasmModule,
  type ProtoWasmNativeFailure,
} from '../../../src/runtime/ProtoWasm';

describe('ProtoWasmBridge native failures', () => {
  it('keeps legacy null semantics when no failure handler is provided', () => {
    const harness = nativeFailureHarness(-252, 'invalid native output');
    const logger = new SDKLogger('ProtoWasmTest');
    const warning = vi.spyOn(logger, 'warning').mockImplementation(() => undefined);

    expect(new ProtoWasmBridge(harness.module, logger).readResultProto(
      harness.call,
      'rac_test_proto',
    )).toBeNull();
    expect(warning).toHaveBeenCalledWith(
      'rac_test_proto returned RAC_ERROR_INVALID_FORMAT',
    );
  });

  it('exposes return code, buffer status, and native message to an opt-in handler', () => {
    const harness = nativeFailureHarness(0, 'post-dispatch native failure', -252);
    const logger = new SDKLogger('ProtoWasmTest');
    let captured: ProtoWasmNativeFailure | undefined;

    const bridge = new ProtoWasmBridge(
      harness.module,
      logger,
      {
        onNativeFailure: (failure) => {
          captured = failure;
          throw new Error('typed failure delivered');
        },
      },
    );
    expect(() => bridge.readResultProto(harness.call, 'rac_test_proto'))
      .toThrow('typed failure delivered');
    expect(captured).toEqual({
      functionName: 'rac_test_proto',
      resultCode: -252,
      returnCode: 0,
      bufferStatus: -252,
      message: 'post-dispatch native failure',
    });
  });
});

interface NativeFailureHarness {
  module: ProtoWasmModule;
  call(outResult: number): number;
}

function nativeFailureHarness(
  returnCode: number,
  message: string,
  bufferStatus = returnCode,
): NativeFailureHarness {
  const memory = new ArrayBuffer(4_096);
  const heapU8 = new Uint8Array(memory);
  const heapU32 = new Uint32Array(memory);
  const heap32 = new Int32Array(memory);
  let nextAllocation = 256;

  const allocate = (size: number): number => {
    const pointer = nextAllocation;
    nextAllocation += (Math.max(size, 1) + 7) & ~7;
    return pointer;
  };
  const module: ProtoWasmModule = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc: allocate,
    _free: () => undefined,
    _rac_proto_buffer_init: (bufferPointer: number) => {
      heapU32.fill(0, bufferPointer >>> 2, (bufferPointer >>> 2) + 4);
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    UTF8ToString: (pointer: number) => {
      let end = pointer;
      while (heapU8[end] !== 0) end += 1;
      return new TextDecoder().decode(heapU8.subarray(pointer, end));
    },
  };

  return {
    module,
    call(outResult) {
      const messageBytes = new TextEncoder().encode(message);
      const messagePointer = allocate(messageBytes.byteLength + 1);
      heapU8.set(messageBytes, messagePointer);
      heapU8[messagePointer + messageBytes.byteLength] = 0;
      heap32[(outResult + 8) >>> 2] = bufferStatus;
      heapU32[(outResult + 12) >>> 2] = messagePointer;
      return returnCode;
    },
  };
}
