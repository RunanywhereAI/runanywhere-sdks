import { type StreamTransport } from "./_streamFactory";
import type { STTTranscriptionRequest } from "../stt_options";
import type { STTStreamEvent } from "../stt_options";
export interface STTStreamTransport extends StreamTransport<STTTranscriptionRequest, STTStreamEvent> {
}
export declare function streamSTT(transport: STTStreamTransport, req: STTTranscriptionRequest): AsyncIterable<STTStreamEvent>;
