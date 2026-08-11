/**
 * ProtoWire unit tests — confirms the Hermes-safe UTF-8 codec install,
 * proto message round-trip via `encodeProtoMessage`, and the
 * BinaryWriter availability gate.
 */

import { SDKError } from '@runanywhere/proto-ts/errors';
import {
  createProtoBinaryWriter,
  encodeProtoMessage,
  ensureProtoTextEncoding,
} from '../../src/services/ProtoWire';
import { arrayBufferToBytes } from '../../src/services/ProtoBytes';

describe('ProtoWire', () => {
  it('ensureProtoTextEncoding is idempotent', () => {
    expect(() => {
      ensureProtoTextEncoding();
      ensureProtoTextEncoding();
      ensureProtoTextEncoding();
    }).not.toThrow();
  });

  it('createProtoBinaryWriter returns a BinaryWriter with a finish() method', () => {
    const writer = createProtoBinaryWriter();
    expect(typeof (writer as { finish: () => Uint8Array }).finish).toBe(
      'function'
    );
  });

  it('encodeProtoMessage produces a decodable SDKError ArrayBuffer', () => {
    const message = SDKError.create({
      code: 110,
      message: 'model not found: gpt-test',
      nestedMessage: 'NotFoundError',
    });
    const ab = encodeProtoMessage(message, SDKError);
    expect(ab.byteLength).toBeGreaterThan(0);

    const decoded = SDKError.decode(arrayBufferToBytes(ab));
    expect(decoded.code).toBe(110);
    expect(decoded.message).toBe('model not found: gpt-test');
    expect(decoded.nestedMessage).toBe('NotFoundError');
  });
});
