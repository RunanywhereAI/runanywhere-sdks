import { type StreamTransport } from "./_streamFactory";
import type { VADProcessRequest } from "../vad_options";
import type { VADStreamEvent } from "../vad_options";
export interface VADStreamTransport extends StreamTransport<VADProcessRequest, VADStreamEvent> {
}
export declare function streamVAD(transport: VADStreamTransport, req: VADProcessRequest): AsyncIterable<VADStreamEvent>;
