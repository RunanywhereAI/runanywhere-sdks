import type { StructuredOutputRequest } from "../structured_output";
import type { StructuredOutputStreamEvent } from "../structured_output";
export interface StructuredOutputStreamTransport {
    subscribe(req: StructuredOutputRequest, onMessage: (msg: StructuredOutputStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<StructuredOutputStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function generatestreamStructuredOutput(transport: StructuredOutputStreamTransport, req: StructuredOutputRequest): AsyncIterable<StructuredOutputStreamEvent>;
