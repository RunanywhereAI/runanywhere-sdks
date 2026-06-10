export function bytesToArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength
  ) as ArrayBuffer;
}

export function arrayBufferToBytes(buffer: ArrayBuffer): Uint8Array {
  return new Uint8Array(buffer);
}
