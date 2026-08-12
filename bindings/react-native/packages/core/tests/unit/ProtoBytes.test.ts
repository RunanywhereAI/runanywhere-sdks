/**
 * ProtoBytes unit tests — round-trip the Nitro proto buffer helpers.
 */

import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../src/services/ProtoBytes';

describe('ProtoBytes', () => {
  it('bytesToArrayBuffer copies the exact byte slice when offset is zero', () => {
    const src = new Uint8Array([1, 2, 3, 4]);
    const buf = bytesToArrayBuffer(src);
    expect(buf.byteLength).toBe(4);
    expect(Array.from(new Uint8Array(buf))).toEqual([1, 2, 3, 4]);
  });

  it('bytesToArrayBuffer respects byteOffset and byteLength', () => {
    const backing = new Uint8Array([9, 9, 1, 2, 3, 9, 9]);
    // Slice indices 2..5 (3 bytes: [1, 2, 3])
    const view = new Uint8Array(backing.buffer, 2, 3);
    const buf = bytesToArrayBuffer(view);
    expect(buf.byteLength).toBe(3);
    expect(Array.from(new Uint8Array(buf))).toEqual([1, 2, 3]);
  });

  it('arrayBufferToBytes returns a Uint8Array over the same buffer', () => {
    const ab = new ArrayBuffer(4);
    new DataView(ab).setUint8(0, 7);
    new DataView(ab).setUint8(3, 42);
    const bytes = arrayBufferToBytes(ab);
    expect(bytes.byteLength).toBe(4);
    expect(bytes[0]).toBe(7);
    expect(bytes[3]).toBe(42);
  });

  it('round-trips arbitrary Uint8Array contents', () => {
    const src = new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 255]);
    const roundtripped = arrayBufferToBytes(bytesToArrayBuffer(src));
    expect(roundtripped.byteLength).toBe(src.byteLength);
    expect(Array.from(roundtripped)).toEqual(Array.from(src));
  });
});
