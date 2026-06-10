import { type StreamTransport } from "./_streamFactory";
import type { VLMGenerationRequest } from "../vlm_options";
import type { VLMStreamEvent } from "../vlm_options";
export interface VLMStreamTransport extends StreamTransport<VLMGenerationRequest, VLMStreamEvent> {
}
export declare function streamVLM(transport: VLMStreamTransport, req: VLMGenerationRequest): AsyncIterable<VLMStreamEvent>;
