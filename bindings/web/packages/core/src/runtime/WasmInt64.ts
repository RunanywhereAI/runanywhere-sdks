/**
 * Emscripten is linked with `-sWASM_BIGINT=1`, so every C/C++ `uint64_t` or
 * `int64_t` value crossing a JavaScript function boundary is a `bigint`.
 * Out-pointers remain ordinary WASM32 pointers; their two uint32 words must
 * be reconstructed without first passing through JavaScript's Number range.
 */

const UINT32_BITS = 32n;
const MAX_SAFE_UINT64_AS_NUMBER = BigInt(Number.MAX_SAFE_INTEGER);

export function readWasmUint64(heap: Uint32Array, ptr: number): bigint {
  const wordIndex = ptr >>> 2;
  const low = BigInt(heap[wordIndex] ?? 0);
  const high = BigInt(heap[wordIndex + 1] ?? 0);
  return low | (high << UINT32_BITS);
}

/**
 * Generated proto-ts currently represents protobuf uint64 fields as Number.
 * Keep the native ABI as bigint and perform the one unavoidable conversion
 * only at that serialization boundary, with an explicit losslessness guard.
 */
export function wasmUint64ToSafeNumber(value: bigint, fieldName: string): number {
  if (value < 0n || value > MAX_SAFE_UINT64_AS_NUMBER) {
    throw new RangeError(`${fieldName} cannot be represented losslessly by proto-ts`);
  }
  return Number(value);
}
