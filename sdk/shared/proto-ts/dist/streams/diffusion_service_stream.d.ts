import type { DiffusionGenerationRequest } from "../diffusion_options";
import type { DiffusionStreamEvent } from "../diffusion_options";
export interface DiffusionStreamTransport {
    subscribe(req: DiffusionGenerationRequest, onMessage: (msg: DiffusionStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<DiffusionStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamDiffusion(transport: DiffusionStreamTransport, req: DiffusionGenerationRequest): AsyncIterable<DiffusionStreamEvent>;
