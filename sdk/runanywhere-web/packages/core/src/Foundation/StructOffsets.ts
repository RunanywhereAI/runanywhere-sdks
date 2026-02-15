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
 * Usage:
 *   import { Offsets, loadOffsets } from '../Foundation/StructOffsets';
 *
 *   // Called once during SDK init (after WASM load):
 *   loadOffsets(wasmModule);
 *
 *   // Then anywhere:
 *   m.setValue(optPtr + Offsets.llmOptions.temperature, 0.8, 'float');
 */

/* eslint-disable @typescript-eslint/no-explicit-any */

// ---------------------------------------------------------------------------
// Cached offset tables
// ---------------------------------------------------------------------------

export interface ConfigOffsets {
  logLevel: number;
}

export interface LLMOptionsOffsets {
  maxTokens: number;
  temperature: number;
  topP: number;
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

let _offsets: AllOffsets | null = null;

/**
 * Get the cached struct offsets. Throws if `loadOffsets()` hasn't been called.
 */
export function getOffsets(): AllOffsets {
  if (!_offsets) {
    throw new Error('StructOffsets not loaded — call loadOffsets(module) after WASM init');
  }
  return _offsets;
}

/**
 * Convenience re-export so callers can write `Offsets.vlmResult.text`.
 */
export const Offsets: AllOffsets = new Proxy({} as AllOffsets, {
  get(_target, prop) {
    return getOffsets()[prop as keyof AllOffsets];
  },
});

/**
 * Read all struct field offsets from the WASM module and cache them.
 * Must be called exactly once, after the WASM module is loaded.
 *
 * @param m - The Emscripten WASM module instance
 */
export function loadOffsets(m: any): void {
  // Helper: safely call an offset function, returning 0 if it doesn't exist
  // (e.g. when a backend wasn't compiled in).
  const off = (name: string): number => {
    const fn = m[`_rac_wasm_offsetof_${name}`];
    return typeof fn === 'function' ? fn() : 0;
  };

  const sz = (name: string): number => {
    const fn = m[`_rac_wasm_sizeof_${name}`];
    return typeof fn === 'function' ? fn() : 0;
  };

  _offsets = {
    config: {
      logLevel: off('config_log_level'),
    },

    llmOptions: {
      maxTokens: off('llm_options_max_tokens'),
      temperature: off('llm_options_temperature'),
      topP: off('llm_options_top_p'),
    },

    llmResult: {
      text: off('llm_result_text'),
      promptTokens: off('llm_result_prompt_tokens'),
      completionTokens: off('llm_result_completion_tokens'),
    },

    vlmImage: {
      format: off('vlm_image_format'),
      filePath: off('vlm_image_file_path'),
      pixelData: off('vlm_image_pixel_data'),
      base64Data: off('vlm_image_base64_data'),
      width: off('vlm_image_width'),
      height: off('vlm_image_height'),
      dataSize: off('vlm_image_data_size'),
    },

    vlmOptions: {
      maxTokens: off('vlm_options_max_tokens'),
      temperature: off('vlm_options_temperature'),
      topP: off('vlm_options_top_p'),
      streamingEnabled: off('vlm_options_streaming_enabled'),
      systemPrompt: off('vlm_options_system_prompt'),
      modelFamily: off('vlm_options_model_family'),
    },

    vlmResult: {
      text: off('vlm_result_text'),
      promptTokens: off('vlm_result_prompt_tokens'),
      imageTokens: off('vlm_result_image_tokens'),
      completionTokens: off('vlm_result_completion_tokens'),
      totalTokens: off('vlm_result_total_tokens'),
      timeToFirstTokenMs: off('vlm_result_time_to_first_token_ms'),
      imageEncodeTimeMs: off('vlm_result_image_encode_time_ms'),
      totalTimeMs: off('vlm_result_total_time_ms'),
      tokensPerSecond: off('vlm_result_tokens_per_second'),
    },

    structuredOutputConfig: {
      jsonSchema: off('structured_output_config_json_schema'),
      includeSchemaInPrompt: off('structured_output_config_include_schema'),
    },

    structuredOutputValidation: {
      isValid: off('structured_output_validation_is_valid'),
      errorMessage: off('structured_output_validation_error_message'),
      extractedJson: off('structured_output_validation_extracted_json'),
    },

    embeddingsOptions: {
      normalize: off('embeddings_options_normalize'),
      pooling: off('embeddings_options_pooling'),
      nThreads: off('embeddings_options_n_threads'),
    },

    embeddingsResult: {
      embeddings: off('embeddings_result_embeddings'),
      numEmbeddings: off('embeddings_result_num_embeddings'),
      dimension: off('embeddings_result_dimension'),
      processingTimeMs: off('embeddings_result_processing_time_ms'),
      totalTokens: off('embeddings_result_total_tokens'),
    },

    embeddingVector: {
      data: off('embedding_vector_data'),
      dimension: off('embedding_vector_dimension'),
      structSize: sz('embedding_vector'),
    },

    diffusionOptions: {
      prompt: off('diffusion_options_prompt'),
      negativePrompt: off('diffusion_options_negative_prompt'),
      width: off('diffusion_options_width'),
      height: off('diffusion_options_height'),
      steps: off('diffusion_options_steps'),
      guidanceScale: off('diffusion_options_guidance_scale'),
      seed: off('diffusion_options_seed'),
      scheduler: off('diffusion_options_scheduler'),
      mode: off('diffusion_options_mode'),
      denoiseStrength: off('diffusion_options_denoise_strength'),
      reportIntermediate: off('diffusion_options_report_intermediate'),
      progressStride: off('diffusion_options_progress_stride'),
    },

    diffusionResult: {
      imageData: off('diffusion_result_image_data'),
      imageSize: off('diffusion_result_image_size'),
      width: off('diffusion_result_width'),
      height: off('diffusion_result_height'),
      seedUsed: off('diffusion_result_seed_used'),
      generationTimeMs: off('diffusion_result_generation_time_ms'),
      safetyFlagged: off('diffusion_result_safety_flagged'),
    },
  };
}

/**
 * Load offsets for a standalone WASM module (e.g. in a Web Worker).
 * Returns the offsets directly instead of storing them in the singleton.
 * Useful when the Worker has its own WASM instance.
 */
export function loadOffsetsFromModule(m: any): AllOffsets {
  loadOffsets(m);
  return _offsets!;
}
