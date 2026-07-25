/**
 * Canonical SDK event stream extension.
 *
 * Native commons owns the SDKEvent queue/subscriptions; this file only
 * encodes/decodes generated proto-ts messages for RN callers.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import type { SDKEvent as SDKEventMessage } from '@runanywhere/proto-ts/sdk_events';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import { SDKException } from '../../../Foundation/Errors/SDKException';

export type { SDKEvent as ProtoSDKEvent } from '@runanywhere/proto-ts/sdk_events';

function encodeEvent(event: SDKEventMessage): ArrayBuffer {
  return encodeProtoMessage(event, SDKEvent);
}

function decodeEvent(buffer: ArrayBuffer): SDKEventMessage | null {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? null : SDKEvent.decode(bytes);
}

/**
 * Subscribe to native SDKEvent proto messages. Returns the native subscription
 * id, which is passed to {@link unsubscribeSDKEvents} to stop the stream.
 * Mirrors Swift `RunAnywhere.subscribeSDKEvents(_:) -> UInt64`.
 */
export async function subscribeSDKEvents(
  callback: (event: SDKEventMessage) => void
): Promise<number> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
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
    throw SDKException.generationFailedWith('Native SDKEvent subscription failed');
  }

  return subscriptionId;
}

/**
 * Unsubscribe a previously-registered SDKEvent handler by the subscription id
 * returned from {@link subscribeSDKEvents}. Mirrors Swift
 * `RunAnywhere.unsubscribeSDKEvents(_:)`. No-op when native is unavailable.
 */
export async function unsubscribeSDKEvents(
  subscriptionId: number
): Promise<void> {
  if (!isNativeModuleAvailable()) {
    return;
  }

  const native = requireNativeModule();
  await native.unsubscribeSDKEventsProto(subscriptionId);
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
