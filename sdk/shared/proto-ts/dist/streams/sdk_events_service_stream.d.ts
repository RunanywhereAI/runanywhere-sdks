import { type StreamTransport } from "./_streamFactory";
import type { SDKEventSubscribeRequest } from "../sdk_events";
import type { SDKEvent } from "../sdk_events";
export interface SDKEventsStreamTransport extends StreamTransport<SDKEventSubscribeRequest, SDKEvent> {
}
export declare function subscribeSDKEvents(transport: SDKEventsStreamTransport, req: SDKEventSubscribeRequest): AsyncIterable<SDKEvent>;
