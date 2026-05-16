import type { TTSSynthesisRequest } from "../tts_options";
import type { TTSStreamEvent } from "../tts_options";
export interface TTSStreamTransport {
    subscribe(req: TTSSynthesisRequest, onMessage: (msg: TTSStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<TTSStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamTTS(transport: TTSStreamTransport, req: TTSSynthesisRequest): AsyncIterable<TTSStreamEvent>;
