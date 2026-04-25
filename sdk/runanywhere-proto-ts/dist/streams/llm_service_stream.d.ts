import type { LLMGenerateRequest } from "../llm_service";
import type { LLMStreamEvent } from "../llm_service";
export interface LLMStreamTransport {
    subscribe(req: LLMGenerateRequest, onMessage: (msg: LLMStreamEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<LLMStreamEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function generateLLM(transport: LLMStreamTransport, req: LLMGenerateRequest): AsyncIterable<LLMStreamEvent>;
//# sourceMappingURL=llm_service_stream.d.ts.map