import { type StreamTransport } from "./_streamFactory";
import type { StructuredOutputRequest } from "../structured_output";
import type { StructuredOutputStreamEvent } from "../structured_output";
export interface StructuredOutputStreamTransport extends StreamTransport<StructuredOutputRequest, StructuredOutputStreamEvent> {
}
export declare function generatestreamStructuredOutput(transport: StructuredOutputStreamTransport, req: StructuredOutputRequest): AsyncIterable<StructuredOutputStreamEvent>;
