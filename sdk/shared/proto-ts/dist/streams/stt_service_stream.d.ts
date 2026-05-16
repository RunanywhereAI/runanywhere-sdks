import type { STTTranscriptionRequest } from "../stt_options";
import type { STTStreamEvent } from "../stt_options";
export interface STTStreamTransport {
    subscribe(req: STTTranscriptionRequest, onMessage: (msg: STTStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<STTStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamSTT(transport: STTStreamTransport, req: STTTranscriptionRequest): AsyncIterable<STTStreamEvent>;
