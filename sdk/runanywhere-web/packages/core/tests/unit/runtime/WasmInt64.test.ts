import { describe, expect, it } from 'vitest';
import {
  readWasmUint64,
  wasmUint64ToSafeNumber,
} from '../../../src/runtime/WasmInt64';

describe('WASM_BIGINT uint64 boundaries', () => {
  it('reconstructs both uint32 halves without Number precision loss', () => {
    const heap = new Uint32Array(8);
    heap[2] = 0x89ab_cdef;
    heap[3] = 0x0123_4567;

    expect(readWasmUint64(heap, 8)).toBe(0x0123_4567_89ab_cdefn);
  });

  it('converts to Number only when a generated proto uint64 is lossless', () => {
    expect(wasmUint64ToSafeNumber(0x42n, 'session')).toBe(0x42);
    expect(() => wasmUint64ToSafeNumber(0x0020_0000_0000_0000n, 'session'))
      .toThrow(/cannot be represented losslessly/);
  });
});
