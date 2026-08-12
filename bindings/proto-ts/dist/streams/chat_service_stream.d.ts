import { type StreamTransport } from "./_streamFactory";
import type { ChatGenerationRequest } from "../chat";
import type { ChatStreamEvent } from "../chat";
export interface ChatStreamTransport extends StreamTransport<ChatGenerationRequest, ChatStreamEvent> {
}
export declare function streamChat(transport: ChatStreamTransport, req: ChatGenerationRequest): AsyncIterable<ChatStreamEvent>;
