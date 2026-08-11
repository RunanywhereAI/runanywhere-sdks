// proto-abi.ts — the typed seam over the addon's proto-byte entry points.
//
// Mirrors Swift's `NativeProtoABI`: a request message is serialized, handed to a
// `rac_*_proto` symbol, and the reply bytes are decoded into the response
// message. Nothing above this file handles raw bytes, and nothing below it
// handles SDK types.

import { asSDKException } from '../errors';
import { bridgeStream } from './iter';

/** The encode/decode pair ts-proto emits for every generated message. */
export interface ProtoMessageType<T> {
  encode(message: T): { finish(): Uint8Array };
  decode(input: Uint8Array): T;
}

/** An addon entry point taking serialized request bytes and resolving reply bytes. */
export type ProtoUnaryCall = (request: Uint8Array) => Promise<Uint8Array>;

/** An addon entry point streaming serialized event bytes until it resolves. */
export type ProtoStreamCall = (
  request: Uint8Array,
  onEvent: (event: Uint8Array) => void
) => Promise<void>;

function serialize<T>(type: ProtoMessageType<T>, message: T): Uint8Array {
  try {
    return type.encode(message).finish();
  } catch (error) {
    throw asSDKException(error);
  }
}

function deserialize<T>(type: ProtoMessageType<T>, bytes: Uint8Array): T {
  try {
    return type.decode(bytes);
  } catch (error) {
    throw asSDKException(error);
  }
}

/** Call a proto entry point and decode its reply. */
export async function invokeProto<Request, Response>(
  call: ProtoUnaryCall,
  requestType: ProtoMessageType<Request>,
  request: Request,
  responseType: ProtoMessageType<Response>
): Promise<Response> {
  let reply: Uint8Array;
  try {
    reply = await call(serialize(requestType, request));
  } catch (error) {
    throw asSDKException(error);
  }
  return deserialize(responseType, reply);
}

/** Call a proto entry point whose reply carries no payload. */
export async function invokeProtoVoid<Request>(
  call: ProtoUnaryCall,
  requestType: ProtoMessageType<Request>,
  request: Request
): Promise<void> {
  try {
    await call(serialize(requestType, request));
  } catch (error) {
    throw asSDKException(error);
  }
}

/**
 * Stream a proto entry point's events as an AsyncIterable. `cancel` runs when the
 * consumer breaks out of the loop, so the native side stops producing.
 */
export function streamProto<Request, Event>(
  call: ProtoStreamCall,
  requestType: ProtoMessageType<Request>,
  request: Request,
  eventType: ProtoMessageType<Event>,
  cancel?: () => void | Promise<void>
): AsyncIterableIterator<Event> {
  return bridgeStream<Event>(
    (sink) =>
      call(serialize(requestType, request), (bytes) => {
        sink.push(deserialize(eventType, bytes));
      }),
    cancel
  );
}
