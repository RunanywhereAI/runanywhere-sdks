import { type StreamTransport } from "./_streamFactory";
import type { DiffusionGenerationRequest } from "../diffusion_options";
import type { DiffusionStreamEvent } from "../diffusion_options";
export interface DiffusionStreamTransport extends StreamTransport<DiffusionGenerationRequest, DiffusionStreamEvent> {
}
export declare function streamDiffusion(transport: DiffusionStreamTransport, req: DiffusionGenerationRequest): AsyncIterable<DiffusionStreamEvent>;
