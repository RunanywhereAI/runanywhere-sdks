import { type StreamTransport } from "./_streamFactory";
import type { LLMGenerateRequest } from "../llm_service";
import type { LLMStreamEvent } from "../llm_service";
export interface LLMStreamTransport extends StreamTransport<LLMGenerateRequest, LLMStreamEvent> {
}
export declare function generateLLM(transport: LLMStreamTransport, req: LLMGenerateRequest): AsyncIterable<LLMStreamEvent>;
