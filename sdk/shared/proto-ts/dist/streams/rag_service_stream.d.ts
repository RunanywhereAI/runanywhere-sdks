import type { RAGQueryRequest } from "../rag";
import type { RAGStreamEvent } from "../rag";
export interface RAGStreamTransport {
    subscribe(req: RAGQueryRequest, onMessage: (msg: RAGStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<RAGStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamRAG(transport: RAGStreamTransport, req: RAGQueryRequest): AsyncIterable<RAGStreamEvent>;
