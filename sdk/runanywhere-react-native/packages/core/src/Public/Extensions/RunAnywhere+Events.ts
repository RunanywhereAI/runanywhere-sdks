/**
 * Canonical SDK event stream extension.
 *
 * Native commons owns the SDKEvent queue/subscriptions; this file only
 * encodes/decodes generated proto-ts messages for RN callers.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import type { SDKEvent as SDKEventMessage } from '@runanywhere/proto-ts/sdk_events';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../services/ProtoBytes';

export type { SDKEvent as ProtoSDKEvent } from '@runanywhere/proto-ts/sdk_events';

function encodeEvent(event: SDKEventMessage): ArrayBuffer {
  return bytesToArrayBuffer(SDKEvent.encode(event).finish());
}

function decodeEvent(buffer: ArrayBuffer): SDKEventMessage | null {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? null : SDKEvent.decode(bytes);
}

/**
 * Subscribe to native SDKEvent proto messages.
 */
export async function subscribeSDKEvents(
  callback: (event: SDKEventMessage) => void
): Promise<() => Promise<void>> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  const subscriptionId = await native.subscribeSDKEventsProto(
    (eventBytes: ArrayBuffer) => {
      const event = decodeEvent(eventBytes);
      if (event) {
        callback(event);
      }
    }
  );

  if (!subscriptionId) {
    throw new Error('Native SDKEvent subscription failed');
  }

  return async () => {
    await native.unsubscribeSDKEventsProto(subscriptionId);
  };
}

/**
 * Publish a generated SDKEvent through native commons.
 */
export async function publishSDKEvent(event: SDKEventMessage): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }

  const native = requireNativeModule();
  return native.publishSDKEventProto(encodeEvent(event));
}

/**
 * Poll the next queued SDKEvent from native commons.
 */
export async function pollSDKEvent(): Promise<SDKEventMessage | null> {
  if (!isNativeModuleAvailable()) {
    return null;
  }

  const native = requireNativeModule();
  return decodeEvent(await native.pollSDKEventProto());
}

/**
 * Publish a canonical failure event from native commons.
 */
export async function publishSDKFailure(options: {
  errorCode: number;
  message: string;
  component: string;
  operation: string;
  recoverable: boolean;
}): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }

  const native = requireNativeModule();
  return native.publishSDKFailureProto(
    options.errorCode,
    options.message,
    options.component,
    options.operation,
    options.recoverable
  );
}
