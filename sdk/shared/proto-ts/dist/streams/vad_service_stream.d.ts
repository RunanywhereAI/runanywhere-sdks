import type { VADProcessRequest } from "../vad_options";
import type { VADStreamEvent } from "../vad_options";
export interface VADStreamTransport {
    subscribe(req: VADProcessRequest, onMessage: (msg: VADStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<VADStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamVAD(transport: VADStreamTransport, req: VADProcessRequest): AsyncIterable<VADStreamEvent>;
