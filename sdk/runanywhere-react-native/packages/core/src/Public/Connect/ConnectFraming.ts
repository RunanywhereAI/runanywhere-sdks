/**
 * Length-prefixed Connect framing helpers used by the React Native transport.
 * Kept free of socket I/O so cancel/buffering invariants can be unit-tested.
 */

export const CONNECT_MAX_FRAME_LENGTH = 4 * 1024 * 1024;

export function concatBytes(left: Uint8Array, right: Uint8Array): Uint8Array {
  if (left.length === 0) return right.slice();
  if (right.length === 0) return left;
  const merged = new Uint8Array(left.length + right.length);
  merged.set(left, 0);
  merged.set(right, left.length);
  return merged;
}

export function encodeConnectFrame(payload: Uint8Array): Uint8Array {
  if (payload.length < 1 || payload.length > CONNECT_MAX_FRAME_LENGTH) {
    throw new Error('Connect frame size is invalid');
  }
  const frame = new Uint8Array(payload.length + 4);
  new DataView(frame.buffer).setUint32(0, payload.length, false);
  frame.set(payload, 4);
  return frame;
}

/**
 * Extract complete frames from a byte stream. Returns remaining unparsed bytes
 * and any complete payloads. Throws on an invalid length prefix.
 */
export function extractConnectFrames(buffer: Uint8Array): {
  frames: Uint8Array[];
  remaining: Uint8Array;
} {
  const frames: Uint8Array[] = [];
  let offset = 0;
  while (buffer.length - offset >= 4) {
    const view = new DataView(buffer.buffer, buffer.byteOffset + offset, 4);
    const length = view.getUint32(0, false);
    if (length < 1 || length > CONNECT_MAX_FRAME_LENGTH) {
      throw new Error('The Connect host returned an invalid frame size');
    }
    if (buffer.length - offset < length + 4) break;
    frames.push(buffer.subarray(offset + 4, offset + 4 + length).slice());
    offset += length + 4;
  }
  return {
    frames,
    remaining: offset === 0 ? buffer : buffer.subarray(offset).slice(),
  };
}
