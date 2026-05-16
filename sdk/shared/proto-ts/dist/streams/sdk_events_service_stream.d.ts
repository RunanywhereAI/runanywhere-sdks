import type { SDKEventSubscribeRequest } from "../sdk_events";
import type { SDKEvent } from "../sdk_events";
export interface SDKEventsStreamTransport {
    subscribe(req: SDKEventSubscribeRequest, onMessage: (msg: SDKEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<SDKEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function subscribeSDKEvents(transport: SDKEventsStreamTransport, req: SDKEventSubscribeRequest): AsyncIterable<SDKEvent>;
