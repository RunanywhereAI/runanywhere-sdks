/**
 * @runanywhere/web-llamacpp
 *
 * LlamaCpp backend for the RunAnywhere Web SDK.
 * Provides on-device LLM, VLM, tool calling, structured output,
 * embeddings, and diffusion capabilities via llama.cpp compiled to WASM.
 *
 * @packageDocumentation
 *
 * @example
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/web';
 * import { LlamaCPP } from '@runanywhere/web-llamacpp';
 *
 * await RunAnywhere.initialize();
 * await LlamaCPP.register();
 *
 * // Now TextGeneration, VLM, etc. are available
 * const result = await TextGeneration.generate('Hello!', { maxTokens: 100 });
 * ```
 */

// Module facade & provider
export { LlamaCPP, autoRegister } from './LlamaCPP';
export type { LlamaCPPRegisterOptions } from './LlamaCPP';
export { LlamaCppProvider } from './LlamaCppProvider';

// Foundation (WASM bridge — exposed for advanced URL override)
export { LlamaCppBridge } from './Foundation/LlamaCppBridge';
export type { LlamaCppModule } from './Foundation/LlamaCppBridge';

// Extensions (backend-specific implementations)
export { TextGeneration } from './Extensions/RunAnywhere+TextGeneration';
export { VLM, VLMModelFamily } from './Extensions/RunAnywhere+VLM';
export { ToolCalling, ToolCallFormat, toToolValue, fromToolValue, getStringArg, getNumberArg } from './Extensions/RunAnywhere+ToolCalling';
export type {
  ToolValue, ToolParameterType, ToolParameter, ToolDefinition,
  ToolCall, ToolResult, ToolCallingOptions, ToolCallingResult, ToolExecutor,
} from './Extensions/RunAnywhere+ToolCalling';
export { StructuredOutput } from './Extensions/RunAnywhere+StructuredOutput';
export type { StructuredOutputConfig, StructuredOutputValidation } from './Extensions/RunAnywhere+StructuredOutput';
export { Diffusion } from './Extensions/RunAnywhere+Diffusion';
export { DiffusionScheduler, DiffusionModelVariant, DiffusionMode } from './Extensions/RunAnywhere+Diffusion';
export type { DiffusionGenerationOptions, DiffusionGenerationResult, DiffusionProgressCallback } from './Extensions/RunAnywhere+Diffusion';
export { Embeddings } from './Extensions/RunAnywhere+Embeddings';
export { EmbeddingsNormalize, EmbeddingsPooling } from './Extensions/RunAnywhere+Embeddings';
export type { EmbeddingVector, EmbeddingsResult, EmbeddingsOptions } from './Extensions/RunAnywhere+Embeddings';

// Telemetry & Analytics
export { TelemetryService, getOrCreateDeviceId } from './Foundation/TelemetryService';

// Infrastructure
export { VLMWorkerBridge } from './Infrastructure/VLMWorkerBridge';
export type {
  VLMWorkerResult, VLMLoadModelParams, VLMProcessOptions,
  VLMWorkerCommand, VLMWorkerResponse, ProgressListener,
} from './Infrastructure/VLMWorkerBridge';
export { startVLMWorkerRuntime } from './Infrastructure/VLMWorkerRuntime';
