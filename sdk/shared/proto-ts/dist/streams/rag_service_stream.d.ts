import { type StreamTransport } from "./_streamFactory";
import type { RAGQueryRequest } from "../rag";
import type { RAGStreamEvent } from "../rag";
export interface RAGStreamTransport extends StreamTransport<RAGQueryRequest, RAGStreamEvent> {
}
export declare function streamRAG(transport: RAGStreamTransport, req: RAGQueryRequest): AsyncIterable<RAGStreamEvent>;
