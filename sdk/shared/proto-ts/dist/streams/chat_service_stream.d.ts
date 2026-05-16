import type { ChatGenerationRequest } from "../chat";
import type { ChatStreamEvent } from "../chat";
export interface ChatStreamTransport {
    subscribe(req: ChatGenerationRequest, onMessage: (msg: ChatStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<ChatStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamChat(transport: ChatStreamTransport, req: ChatGenerationRequest): AsyncIterable<ChatStreamEvent>;
