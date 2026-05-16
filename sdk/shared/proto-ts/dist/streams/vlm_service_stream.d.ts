import type { VLMGenerationRequest } from "../vlm_options";
import type { VLMStreamEvent } from "../vlm_options";
export interface VLMStreamTransport {
    subscribe(req: VLMGenerationRequest, onMessage: (msg: VLMStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<VLMStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamVLM(transport: VLMStreamTransport, req: VLMGenerationRequest): AsyncIterable<VLMStreamEvent>;
