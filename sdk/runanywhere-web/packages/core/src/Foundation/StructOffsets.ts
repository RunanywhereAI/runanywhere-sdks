/**
 * RunAnywhere Web SDK - Struct Offset Types
 *
 * Core is now pure TypeScript. Struct offset loading happens in each
 * backend package's bridge (LlamaCppBridge, SherpaONNXBridge).
 *
 * This file only exports the offset interface types for use by
 * backend packages that need them.
 */

// ---------------------------------------------------------------------------
// Offset Interface Types (used by backend packages)
// ---------------------------------------------------------------------------

export interface ConfigOffsets { logLevel: number; }
export interface LLMOptionsOffsets { maxTokens: number; temperature: number; topP: number; systemPrompt: number; }
export interface LLMResultOffsets { text: number; promptTokens: number; completionTokens: number; }
export interface VLMImageOffsets { format: number; filePath: number; pixelData: number; base64Data: number; width: number; height: number; dataSize: number; }
export interface VLMOptionsOffsets { maxTokens: number; temperature: number; topP: number; streamingEnabled: number; systemPrompt: number; modelFamily: number; }
export interface VLMResultOffsets { text: number; promptTokens: number; imageTokens: number; completionTokens: number; totalTokens: number; timeToFirstTokenMs: number; imageEncodeTimeMs: number; totalTimeMs: number; tokensPerSecond: number; }
export interface StructuredOutputConfigOffsets { jsonSchema: number; includeSchemaInPrompt: number; }
export interface StructuredOutputValidationOffsets { isValid: number; errorMessage: number; extractedJson: number; }
export interface EmbeddingsOptionsOffsets { normalize: number; pooling: number; nThreads: number; }
export interface EmbeddingsResultOffsets { embeddings: number; numEmbeddings: number; dimension: number; processingTimeMs: number; totalTokens: number; }
export interface EmbeddingVectorOffsets { data: number; dimension: number; structSize: number; }
export interface DiffusionOptionsOffsets { prompt: number; negativePrompt: number; width: number; height: number; steps: number; guidanceScale: number; seed: number; scheduler: number; mode: number; denoiseStrength: number; reportIntermediate: number; progressStride: number; }
export interface DiffusionResultOffsets { imageData: number; imageSize: number; width: number; height: number; seedUsed: number; generationTimeMs: number; safetyFlagged: number; }

export interface AllOffsets {
  config: ConfigOffsets;
  llmOptions: LLMOptionsOffsets;
  llmResult: LLMResultOffsets;
  vlmImage: VLMImageOffsets;
  vlmOptions: VLMOptionsOffsets;
  vlmResult: VLMResultOffsets;
  structuredOutputConfig: StructuredOutputConfigOffsets;
  structuredOutputValidation: StructuredOutputValidationOffsets;
  embeddingsOptions: EmbeddingsOptionsOffsets;
  embeddingsResult: EmbeddingsResultOffsets;
  embeddingVector: EmbeddingVectorOffsets;
  diffusionOptions: DiffusionOptionsOffsets;
  diffusionResult: DiffusionResultOffsets;
}
