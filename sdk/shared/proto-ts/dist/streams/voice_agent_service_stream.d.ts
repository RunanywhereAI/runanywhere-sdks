import { type StreamTransport } from "./_streamFactory";
import type { VoiceAgentRequest } from "../voice_agent_service";
import type { VoiceEvent } from "../voice_events";
export interface VoiceAgentStreamTransport extends StreamTransport<VoiceAgentRequest, VoiceEvent> {
}
export declare function streamVoiceAgent(transport: VoiceAgentStreamTransport, req: VoiceAgentRequest): AsyncIterable<VoiceEvent>;
