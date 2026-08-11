/**
 * Hermes release bundles may lack `TextEncoder` / `TextDecoder`. Bufbuild's
 * default `getTextEncoding()` constructs those globals inside `BinaryWriter`
 * and `BinaryReader`, which breaks proto encode/decode in embedded bundles.
 */

import { BinaryWriter } from '@bufbuild/protobuf/wire';
import { bytesToArrayBuffer } from './ProtoBytes';

type BinaryWriterLike = { finish(): Uint8Array };

type ProtoEncoder<T> = {
  encode(message: T, writer?: BinaryWriterLike): BinaryWriterLike;
};

type ProtoTextEncoding = {
  encodeUtf8(text: string): Uint8Array;
  decodeUtf8(bytes: Uint8Array, strict?: boolean): string;
  checkUtf8(text: string): boolean;
};

const PROTO_TEXT_ENCODING_SYMBOL = Symbol.for('@bufbuild/protobuf/text-encoding');

let protoTextEncodingReady = false;

function utf8Encode(text: string): Uint8Array {
  const TextEncoderCtor = globalThis.TextEncoder;
  if (typeof TextEncoderCtor === 'function') {
    return new TextEncoderCtor().encode(text);
  }
  const encoded = unescape(encodeURIComponent(text));
  const bytes = new Uint8Array(encoded.length);
  for (let i = 0; i < encoded.length; i++) {
    bytes[i] = encoded.charCodeAt(i);
  }
  return bytes;
}

function utf8Decode(bytes: Uint8Array): string {
  const TextDecoderCtor = globalThis.TextDecoder;
  if (typeof TextDecoderCtor === 'function') {
    return new TextDecoderCtor('utf-8').decode(bytes);
  }
  let result = '';
  let index = 0;
  while (index < bytes.length) {
    const byte1 = bytes[index++];
    if (byte1 < 0x80) {
      result += String.fromCharCode(byte1);
      continue;
    }
    if ((byte1 & 0xe0) === 0xc0 && index < bytes.length) {
      const byte2 = bytes[index++];
      result += String.fromCharCode(((byte1 & 0x1f) << 6) | (byte2 & 0x3f));
      continue;
    }
    if ((byte1 & 0xf0) === 0xe0 && index + 1 < bytes.length) {
      const byte2 = bytes[index++];
      const byte3 = bytes[index++];
      result += String.fromCharCode(
        ((byte1 & 0x0f) << 12) | ((byte2 & 0x3f) << 6) | (byte3 & 0x3f)
      );
      continue;
    }
    if ((byte1 & 0xf8) === 0xf0 && index + 2 < bytes.length) {
      const byte2 = bytes[index++];
      const byte3 = bytes[index++];
      const byte4 = bytes[index++];
      const codePoint =
        ((byte1 & 0x07) << 18) |
        ((byte2 & 0x3f) << 12) |
        ((byte3 & 0x3f) << 6) |
        (byte4 & 0x3f);
      result += String.fromCodePoint(codePoint);
    }
  }
  return result;
}

function createProtoTextEncoding(): ProtoTextEncoding {
  return {
    encodeUtf8: utf8Encode,
    decodeUtf8: (bytes, strict) => {
      const decoded = utf8Decode(bytes);
      if (strict) {
        try {
          encodeURIComponent(decoded);
        } catch {
          throw new Error('invalid UTF-8');
        }
      }
      return decoded;
    },
    checkUtf8(text) {
      try {
        encodeURIComponent(text);
        return true;
      } catch {
        return false;
      }
    },
  };
}

/**
 * Install Hermes-safe UTF-8 helpers before any ts-proto `BinaryReader` /
 * `BinaryWriter` default constructors run.
 */
export function ensureProtoTextEncoding(): void {
  if (protoTextEncodingReady) {
    return;
  }
  const globals = globalThis as typeof globalThis & {
    [PROTO_TEXT_ENCODING_SYMBOL]?: ProtoTextEncoding;
  };
  if (globals[PROTO_TEXT_ENCODING_SYMBOL] == null) {
    const hasNativeTextCodec =
      typeof globalThis.TextEncoder === 'function' &&
      typeof globalThis.TextDecoder === 'function';
    globals[PROTO_TEXT_ENCODING_SYMBOL] = hasNativeTextCodec
      ? {
          encodeUtf8: (text) => new globalThis.TextEncoder!().encode(text),
          decodeUtf8: (bytes, strict) => {
            const decoder = strict
              ? new globalThis.TextDecoder!('utf-8', { fatal: true })
              : new globalThis.TextDecoder!();
            return decoder.decode(bytes);
          },
          checkUtf8(text) {
            try {
              encodeURIComponent(text);
              return true;
            } catch {
              return false;
            }
          },
        }
      : createProtoTextEncoding();
  }
  protoTextEncodingReady = true;
}

ensureProtoTextEncoding();

export function createProtoBinaryWriter(): BinaryWriterLike {
  ensureProtoTextEncoding();
  if (typeof BinaryWriter !== 'function') {
    throw new Error(
      'BinaryWriter is unavailable; check Metro resolveRequest for bufbuild wire CJS'
    );
  }
  return new BinaryWriter(utf8Encode);
}

/** Encode a ts-proto message to an ArrayBuffer for Nitro native bridges. */
export function encodeProtoMessage<T>(message: T, codec: ProtoEncoder<T>): ArrayBuffer {
  ensureProtoTextEncoding();
  const writer = createProtoBinaryWriter();
  return bytesToArrayBuffer(codec.encode(message, writer).finish());
}
