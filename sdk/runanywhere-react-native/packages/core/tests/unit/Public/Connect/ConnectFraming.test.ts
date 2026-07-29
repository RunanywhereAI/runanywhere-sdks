import {
  ConnectClientFrame,
  ConnectInvocationCancelRequest,
} from '@runanywhere/proto-ts/connect';
import {
  concatBytes,
  encodeConnectFrame,
  extractConnectFrames,
} from '../../../../src/Public/Connect/ConnectFraming';

describe('ConnectFraming', () => {
  it('concatBytes never spreads into a temporary array', () => {
    const left = new Uint8Array([1, 2, 3]);
    const right = new Uint8Array(64 * 1024).fill(9);
    const merged = concatBytes(left, right);
    expect(merged.length).toBe(left.length + right.length);
    expect(merged[0]).toBe(1);
    expect(merged[merged.length - 1]).toBe(9);
  });

  it('round-trips length-prefixed frames including cancel payloads', () => {
    const cancel = ConnectInvocationCancelRequest.encode({
      sessionId: 'session-1',
      requestId: 'req-42',
    }).finish();
    const payload = ConnectClientFrame.encode({
      cancel: { sessionId: 'session-1', requestId: 'req-42' },
    }).finish();
    const framed = encodeConnectFrame(payload);
    const { frames, remaining } = extractConnectFrames(framed);
    expect(remaining.length).toBe(0);
    expect(frames).toHaveLength(1);
    const decoded = ConnectClientFrame.decode(frames[0]);
    expect(decoded.cancel?.sessionId).toBe('session-1');
    expect(decoded.cancel?.requestId).toBe('req-42');
    expect(cancel.length).toBeGreaterThan(0);
  });

  it('retains partial frames across chunks', () => {
    const payload = new Uint8Array([10, 20, 30, 40, 50]);
    const framed = encodeConnectFrame(payload);
    const first = framed.subarray(0, 3);
    const second = framed.subarray(3);
    const partial = extractConnectFrames(first);
    expect(partial.frames).toHaveLength(0);
    expect(partial.remaining.length).toBe(3);
    const complete = extractConnectFrames(concatBytes(partial.remaining, second));
    expect(complete.frames).toHaveLength(1);
    expect(Array.from(complete.frames[0])).toEqual(Array.from(payload));
  });

  it('rejects oversized length prefixes', () => {
    const header = new Uint8Array(4);
    new DataView(header.buffer).setUint32(0, 8 * 1024 * 1024, false);
    expect(() => extractConnectFrames(header)).toThrow(/invalid frame size/i);
  });
});
