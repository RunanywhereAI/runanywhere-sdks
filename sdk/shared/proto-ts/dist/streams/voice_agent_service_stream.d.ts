import { type StreamTransport } from "./_streamFactory";
import type { VoiceAgentTurnRequest } from "../voice_agent_service";
import type { VoiceEvent } from "../voice_events";
export interface VoiceAgentStreamTransport extends StreamTransport<VoiceAgentTurnRequest, VoiceEvent> {
}
export declare function streamVoiceAgent(transport: VoiceAgentStreamTransport, req: VoiceAgentTurnRequest): AsyncIterable<VoiceEvent>;
