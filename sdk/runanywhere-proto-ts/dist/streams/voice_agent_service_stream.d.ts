import type { VoiceAgentRequest } from "../voice_agent_service";
import type { VoiceEvent } from "../voice_events";
export interface VoiceAgentStreamTransport {
    subscribe(req: VoiceAgentRequest, onMessage: (msg: VoiceEvent) => void, onError: (err: Error) => void, onDone: () => void): () => void;
}
/**
 * Wrap the platform `transport.subscribe` callback into an
 * `AsyncIterable<VoiceEvent>`. Cancellation is propagated by
 * `break`-ing out of `for await` (the iterator's `return()` calls the
 * transport's cancel function).
 */
export declare function streamVoiceAgent(transport: VoiceAgentStreamTransport, req: VoiceAgentRequest): AsyncIterable<VoiceEvent>;
//# sourceMappingURL=voice_agent_service_stream.d.ts.map