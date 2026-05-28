import { type StreamTransport } from "./_streamFactory";
import type { TTSSynthesisRequest } from "../tts_options";
import type { TTSStreamEvent } from "../tts_options";
export interface TTSStreamTransport extends StreamTransport<TTSSynthesisRequest, TTSStreamEvent> {
}
export declare function streamTTS(transport: TTSStreamTransport, req: TTSSynthesisRequest): AsyncIterable<TTSStreamEvent>;
