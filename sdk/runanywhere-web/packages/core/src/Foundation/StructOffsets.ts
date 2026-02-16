/**
 * RunAnywhere Web SDK - WASM Struct Field Offsets
 *
 * C struct field offsets depend on alignment, padding, pointer size (wasm32
 * vs wasm64) and compiler flags. Hard-coding them in TypeScript is fragile
 * and leads to silent data corruption when the C layout changes.
 *
 * This module queries `rac_wasm_offsetof_*()` helpers (compiled via
 * `offsetof()` in wasm_exports.cpp) exactly once after the WASM module is
 * loaded, and caches the results for the lifetime of the page.
 *
 * The offset system is extensible: backend packages (llamacpp, onnx) can
 * register additional offsets via `mergeOffsets()`.
 *
 * Usage:
 *   import { Offsets, loadOffsets } from '@runanywhere/web';
 *
 *   // Called once during SDK init (after WASM load):
 *   loadOffsets(wasmModule);
 *
 *   // Then anywhere:
 *   m.setValue(optPtr + Offsets.config.logLevel, 2, 'i32');
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

// ---------------------------------------------------------------------------
// Core Offset Interfaces (always available)
// ---------------------------------------------------------------------------

export interface ConfigOffsets {
  logLevel: number;
}

// ---------------------------------------------------------------------------
// LlamaCPP Offset Interfaces (available after @runanywhere/web-llamacpp registers)
// ---------------------------------------------------------------------------

export interface LLMOptionsOffsets {
  maxTokens: number;
  temperature: number;
  topP: number;
  systemPrompt: number;
}

export interface LLMResultOffsets {
  text: number;
  promptTokens: number;
  completionTokens: number;
}

export interface VLMImageOffsets {
  format: number;
  filePath: number;
  pixelData: number;
  base64Data: number;
  width: number;
  height: number;
  dataSize: number;
}

export interface VLMOptionsOffsets {
  maxTokens: number;
  temperature: number;
  topP: number;
  streamingEnabled: number;
  systemPrompt: number;
  modelFamily: number;
}

export interface VLMResultOffsets {
  text: number;
  promptTokens: number;
  imageTokens: number;
  completionTokens: number;
  totalTokens: number;
  timeToFirstTokenMs: number;
  imageEncodeTimeMs: number;
  totalTimeMs: number;
  tokensPerSecond: number;
}

export interface StructuredOutputConfigOffsets {
  jsonSchema: number;
  includeSchemaInPrompt: number;
}

export interface StructuredOutputValidationOffsets {
  isValid: number;
  errorMessage: number;
  extractedJson: number;
}

export interface EmbeddingsOptionsOffsets {
  normalize: number;
  pooling: number;
  nThreads: number;
}

export interface EmbeddingsResultOffsets {
  embeddings: number;
  numEmbeddings: number;
  dimension: number;
  processingTimeMs: number;
  totalTokens: number;
}

export interface EmbeddingVectorOffsets {
  data: number;
  dimension: number;
  structSize: number;
}

export interface DiffusionOptionsOffsets {
  prompt: number;
  negativePrompt: number;
  width: number;
  height: number;
  steps: number;
  guidanceScale: number;
  seed: number;
  scheduler: number;
  mode: number;
  denoiseStrength: number;
  reportIntermediate: number;
  progressStride: number;
}

export interface DiffusionResultOffsets {
  imageData: number;
  imageSize: number;
  width: number;
  height: number;
  seedUsed: number;
  generationTimeMs: number;
  safetyFlagged: number;
}

// ---------------------------------------------------------------------------
// Composite Offset Type
// ---------------------------------------------------------------------------

/** All possible offsets. Core provides `config`; backend packages add the rest. */
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

// ---------------------------------------------------------------------------
// Singleton
// ---------------------------------------------------------------------------

let _offsets: Partial<AllOffsets> = {};

/**
 * Get the cached struct offsets.
 * Returns the merged offsets from core + all registered backends.
 */
export function getOffsets(): AllOffsets {
  return _offsets as AllOffsets;
}

/**
 * Convenience re-export so callers can write `Offsets.vlmResult.text`.
 * Returns a Proxy that dynamically resolves from the cached offset store.
 */
export const Offsets: AllOffsets = new Proxy({} as AllOffsets, {
  get(_target, prop) {
    return getOffsets()[prop as keyof AllOffsets];
  },
});

// ---------------------------------------------------------------------------
// WASM offset helpers (exported for backend packages)
// ---------------------------------------------------------------------------

/**
 * Safely call a `_rac_wasm_offsetof_*` function. Returns 0 if the
 * function doesn't exist (e.g. backend not compiled in).
 */
export function wasmOffsetOf(m: any, name: string): number {
  const fn = m[`_rac_wasm_offsetof_${name}`];
  return typeof fn === 'function' ? fn() : 0;
}

/**
 * Safely call a `_rac_wasm_sizeof_*` function. Returns 0 if the
 * function doesn't exist.
 */
export function wasmSizeOf(m: any, name: string): number {
  const fn = m[`_rac_wasm_sizeof_${name}`];
  return typeof fn === 'function' ? fn() : 0;
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

/**
 * Load core struct field offsets from the WASM module.
 * Called once during SDK init (after WASM load).
 *
 * @param m - The Emscripten WASM module instance
 */
export function loadOffsets(m: any): void {
  _offsets = {
    ..._offsets,
    config: {
      logLevel: wasmOffsetOf(m, 'config_log_level'),
    },
  };
}

/**
 * Merge additional offsets from a backend package.
 * Called by backend providers during registration.
 *
 * @param offsets - Partial offset tables to merge
 */
export function mergeOffsets(offsets: Partial<AllOffsets>): void {
  _offsets = { ..._offsets, ...offsets };
}

/**
 * Load offsets for a standalone WASM module (e.g. in a Web Worker).
 * Returns the offsets directly instead of storing them in the singleton.
 * Useful when the Worker has its own WASM instance.
 */
export function loadOffsetsFromModule(m: any): AllOffsets {
  loadOffsets(m);
  // Also load all llama.cpp offsets for the worker (VLM Worker needs these)
  loadLlamaCppOffsetsInto(m);
  return _offsets as AllOffsets;
}

/**
 * Load llama.cpp-specific offsets into the singleton.
 * Called by LlamaCppProvider.register() and loadOffsetsFromModule().
 */
export function loadLlamaCppOffsetsInto(m: any): void {
  mergeOffsets({
    llmOptions: {
      maxTokens: wasmOffsetOf(m, 'llm_options_max_tokens'),
      temperature: wasmOffsetOf(m, 'llm_options_temperature'),
      topP: wasmOffsetOf(m, 'llm_options_top_p'),
      systemPrompt: wasmOffsetOf(m, 'llm_options_system_prompt'),
    },

    llmResult: {
      text: wasmOffsetOf(m, 'llm_result_text'),
      promptTokens: wasmOffsetOf(m, 'llm_result_prompt_tokens'),
      completionTokens: wasmOffsetOf(m, 'llm_result_completion_tokens'),
    },

    vlmImage: {
      format: wasmOffsetOf(m, 'vlm_image_format'),
      filePath: wasmOffsetOf(m, 'vlm_image_file_path'),
      pixelData: wasmOffsetOf(m, 'vlm_image_pixel_data'),
      base64Data: wasmOffsetOf(m, 'vlm_image_base64_data'),
      width: wasmOffsetOf(m, 'vlm_image_width'),
      height: wasmOffsetOf(m, 'vlm_image_height'),
      dataSize: wasmOffsetOf(m, 'vlm_image_data_size'),
    },

    vlmOptions: {
      maxTokens: wasmOffsetOf(m, 'vlm_options_max_tokens'),
      temperature: wasmOffsetOf(m, 'vlm_options_temperature'),
      topP: wasmOffsetOf(m, 'vlm_options_top_p'),
      streamingEnabled: wasmOffsetOf(m, 'vlm_options_streaming_enabled'),
      systemPrompt: wasmOffsetOf(m, 'vlm_options_system_prompt'),
      modelFamily: wasmOffsetOf(m, 'vlm_options_model_family'),
    },

    vlmResult: {
      text: wasmOffsetOf(m, 'vlm_result_text'),
      promptTokens: wasmOffsetOf(m, 'vlm_result_prompt_tokens'),
      imageTokens: wasmOffsetOf(m, 'vlm_result_image_tokens'),
      completionTokens: wasmOffsetOf(m, 'vlm_result_completion_tokens'),
      totalTokens: wasmOffsetOf(m, 'vlm_result_total_tokens'),
      timeToFirstTokenMs: wasmOffsetOf(m, 'vlm_result_time_to_first_token_ms'),
      imageEncodeTimeMs: wasmOffsetOf(m, 'vlm_result_image_encode_time_ms'),
      totalTimeMs: wasmOffsetOf(m, 'vlm_result_total_time_ms'),
      tokensPerSecond: wasmOffsetOf(m, 'vlm_result_tokens_per_second'),
    },

    structuredOutputConfig: {
      jsonSchema: wasmOffsetOf(m, 'structured_output_config_json_schema'),
      includeSchemaInPrompt: wasmOffsetOf(m, 'structured_output_config_include_schema'),
    },

    structuredOutputValidation: {
      isValid: wasmOffsetOf(m, 'structured_output_validation_is_valid'),
      errorMessage: wasmOffsetOf(m, 'structured_output_validation_error_message'),
      extractedJson: wasmOffsetOf(m, 'structured_output_validation_extracted_json'),
    },

    embeddingsOptions: {
      normalize: wasmOffsetOf(m, 'embeddings_options_normalize'),
      pooling: wasmOffsetOf(m, 'embeddings_options_pooling'),
      nThreads: wasmOffsetOf(m, 'embeddings_options_n_threads'),
    },

    embeddingsResult: {
      embeddings: wasmOffsetOf(m, 'embeddings_result_embeddings'),
      numEmbeddings: wasmOffsetOf(m, 'embeddings_result_num_embeddings'),
      dimension: wasmOffsetOf(m, 'embeddings_result_dimension'),
      processingTimeMs: wasmOffsetOf(m, 'embeddings_result_processing_time_ms'),
      totalTokens: wasmOffsetOf(m, 'embeddings_result_total_tokens'),
    },

    embeddingVector: {
      data: wasmOffsetOf(m, 'embedding_vector_data'),
      dimension: wasmOffsetOf(m, 'embedding_vector_dimension'),
      structSize: wasmSizeOf(m, 'embedding_vector'),
    },

    diffusionOptions: {
      prompt: wasmOffsetOf(m, 'diffusion_options_prompt'),
      negativePrompt: wasmOffsetOf(m, 'diffusion_options_negative_prompt'),
      width: wasmOffsetOf(m, 'diffusion_options_width'),
      height: wasmOffsetOf(m, 'diffusion_options_height'),
      steps: wasmOffsetOf(m, 'diffusion_options_steps'),
      guidanceScale: wasmOffsetOf(m, 'diffusion_options_guidance_scale'),
      seed: wasmOffsetOf(m, 'diffusion_options_seed'),
      scheduler: wasmOffsetOf(m, 'diffusion_options_scheduler'),
      mode: wasmOffsetOf(m, 'diffusion_options_mode'),
      denoiseStrength: wasmOffsetOf(m, 'diffusion_options_denoise_strength'),
      reportIntermediate: wasmOffsetOf(m, 'diffusion_options_report_intermediate'),
      progressStride: wasmOffsetOf(m, 'diffusion_options_progress_stride'),
    },

    diffusionResult: {
      imageData: wasmOffsetOf(m, 'diffusion_result_image_data'),
      imageSize: wasmOffsetOf(m, 'diffusion_result_image_size'),
      width: wasmOffsetOf(m, 'diffusion_result_width'),
      height: wasmOffsetOf(m, 'diffusion_result_height'),
      seedUsed: wasmOffsetOf(m, 'diffusion_result_seed_used'),
      generationTimeMs: wasmOffsetOf(m, 'diffusion_result_generation_time_ms'),
      safetyFlagged: wasmOffsetOf(m, 'diffusion_result_safety_flagged'),
    },
  });
}
