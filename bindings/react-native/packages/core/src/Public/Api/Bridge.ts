/**
 * Shared preflight and proto plumbing for the public namespaces.
 */

import { isNativeModuleAvailable, requireNativeModule } from '../../native';
import { SDKException } from '../../Foundation/Errors/SDKException';
import { requireInitialized } from '../../Foundation/Initialization/InitializedGuard';
import { ensureServicesReady } from '../../Foundation/Initialization/ServicesReadyGuard';
import { arrayBufferToBytes } from '../../services/ProtoBytes';
import { encodeProtoMessage } from '../../services/ProtoWire';

/** The native core module, or a typed throw when it is not linked. */
export function native(): ReturnType<typeof requireNativeModule> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

/**
 * Run the guards every capability call shares: initialized SDK, linked native
 * module, and a ready services phase.
 *
 * @throws SDKException when the SDK is not initialized or native is missing.
 */
export async function preflight(): Promise<
  ReturnType<typeof requireNativeModule>
> {
  requireInitialized();
  const module = native();
  await ensureServicesReady();
  return module;
}

let requestCounter = 0;

/** Allocate a request id unique within this JS runtime. */
export function nextRequestId(prefix: string): string {
  requestCounter += 1;
  return `rn-${prefix}-${Date.now()}-${requestCounter}`;
}

/** Encode a generated proto message for the native bridge. */
export function encode<T>(
  message: T,
  codec: {
    encode(
      value: T,
      writer?: { finish(): Uint8Array }
    ): { finish(): Uint8Array };
  }
): ArrayBuffer {
  return encodeProtoMessage(message, codec);
}

/**
 * Decode a proto response, treating an empty buffer as a bridge failure.
 *
 * @throws SDKException when the native bridge returned no bytes.
 */
export function decode<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T },
  operation: string
): T {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed(operation);
  }
  return codec.decode(bytes);
}

/** Decode a proto response, returning `null` for an empty buffer. */
export function decodeOptional<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T }
): T | null {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? null : codec.decode(bytes);
}

/** Decode proto bytes delivered through a streaming callback. */
export function decodeEvent<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T }
): T {
  return codec.decode(arrayBufferToBytes(buffer));
}
