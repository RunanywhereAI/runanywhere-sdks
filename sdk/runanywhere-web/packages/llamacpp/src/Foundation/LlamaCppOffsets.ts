/**
 * LlamaCppOffsets - Cached struct offset access for the llama.cpp WASM module
 *
 * Provides the same `Offsets.llmOptions.temperature` access pattern that the
 * old core WASMBridge had, but backed by LlamaCppBridge.shared.wasmOffsetOf().
 *
 * Offsets are loaded lazily on first access and cached thereafter.
 */

import type {
  AllOffsets,
  ConfigOffsets,
  LLMOptionsOffsets,
  LLMResultOffsets,
  VLMImageOffsets,
  VLMOptionsOffsets,
  VLMResultOffsets,
  StructuredOutputConfigOffsets,
  StructuredOutputValidationOffsets,
  EmbeddingsOptionsOffsets,
  EmbeddingsResultOffsets,
  EmbeddingVectorOffsets,
  DiffusionOptionsOffsets,
  DiffusionResultOffsets,
} from '@runanywhere/web';

import { LlamaCppBridge } from './LlamaCppBridge';

// ---------------------------------------------------------------------------
// Internal: load offset group from LlamaCppBridge
// ---------------------------------------------------------------------------

function off(name: string): number {
  return LlamaCppBridge.shared.wasmOffsetOf(name);
}

function loadConfigOffsets(): ConfigOffsets {
  return { logLevel: off('config_log_level') };
}

function loadLLMOptionsOffsets(): LLMOptionsOffsets {
  return {
    maxTokens: off('llm_options_max_tokens'),
    temperature: off('llm_options_temperature'),
    topP: off('llm_options_top_p'),
    systemPrompt: off('llm_options_system_prompt'),
  };
}

function loadLLMResultOffsets(): LLMResultOffsets {
  return {
    text: off('llm_result_text'),
    promptTokens: off('llm_result_prompt_tokens'),
    completionTokens: off('llm_result_completion_tokens'),
  };
}

function loadVLMImageOffsets(): VLMImageOffsets {
  return {
    format: off('vlm_image_format'),
    filePath: off('vlm_image_file_path'),
    pixelData: off('vlm_image_pixel_data'),
    base64Data: off('vlm_image_base64_data'),
    width: off('vlm_image_width'),
    height: off('vlm_image_height'),
    dataSize: off('vlm_image_data_size'),
  };
}

function loadVLMOptionsOffsets(): VLMOptionsOffsets {
  return {
    maxTokens: off('vlm_options_max_tokens'),
    temperature: off('vlm_options_temperature'),
    topP: off('vlm_options_top_p'),
    streamingEnabled: off('vlm_options_streaming_enabled'),
    systemPrompt: off('vlm_options_system_prompt'),
    modelFamily: off('vlm_options_model_family'),
  };
}

function loadVLMResultOffsets(): VLMResultOffsets {
  return {
    text: off('vlm_result_text'),
    promptTokens: off('vlm_result_prompt_tokens'),
    imageTokens: off('vlm_result_image_tokens'),
    completionTokens: off('vlm_result_completion_tokens'),
    totalTokens: off('vlm_result_total_tokens'),
    timeToFirstTokenMs: off('vlm_result_time_to_first_token_ms'),
    imageEncodeTimeMs: off('vlm_result_image_encode_time_ms'),
    totalTimeMs: off('vlm_result_total_time_ms'),
    tokensPerSecond: off('vlm_result_tokens_per_second'),
  };
}

function loadStructuredOutputConfigOffsets(): StructuredOutputConfigOffsets {
  return {
    jsonSchema: off('structured_output_config_json_schema'),
    includeSchemaInPrompt: off('structured_output_config_include_schema_in_prompt'),
  };
}

function loadStructuredOutputValidationOffsets(): StructuredOutputValidationOffsets {
  return {
    isValid: off('structured_output_validation_is_valid'),
    errorMessage: off('structured_output_validation_error_message'),
    extractedJson: off('structured_output_validation_extracted_json'),
  };
}

function loadEmbeddingsOptionsOffsets(): EmbeddingsOptionsOffsets {
  return {
    normalize: off('embeddings_options_normalize'),
    pooling: off('embeddings_options_pooling'),
    nThreads: off('embeddings_options_n_threads'),
  };
}

function loadEmbeddingsResultOffsets(): EmbeddingsResultOffsets {
  return {
    embeddings: off('embeddings_result_embeddings'),
    numEmbeddings: off('embeddings_result_num_embeddings'),
    dimension: off('embeddings_result_dimension'),
    processingTimeMs: off('embeddings_result_processing_time_ms'),
    totalTokens: off('embeddings_result_total_tokens'),
  };
}

function loadEmbeddingVectorOffsets(): EmbeddingVectorOffsets {
  return {
    data: off('embedding_vector_data'),
    dimension: off('embedding_vector_dimension'),
    structSize: LlamaCppBridge.shared.wasmSizeOf('embedding_vector'),
  };
}

function loadDiffusionOptionsOffsets(): DiffusionOptionsOffsets {
  return {
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
  };
}

function loadDiffusionResultOffsets(): DiffusionResultOffsets {
  return {
    imageData: off('diffusion_result_image_data'),
    imageSize: off('diffusion_result_image_size'),
    width: off('diffusion_result_width'),
    height: off('diffusion_result_height'),
    seedUsed: off('diffusion_result_seed_used'),
    generationTimeMs: off('diffusion_result_generation_time_ms'),
    safetyFlagged: off('diffusion_result_safety_flagged'),
  };
}

// ---------------------------------------------------------------------------
// Cached Offsets Singleton
// ---------------------------------------------------------------------------

let _cached: AllOffsets | null = null;

/**
 * Load all struct offsets from the LlamaCppBridge WASM module.
 * Results are cached after the first call.
 *
 * Must be called after LlamaCppBridge.shared.ensureLoaded().
 */
export function loadOffsets(): AllOffsets {
  if (_cached) return _cached;

  _cached = {
    config: loadConfigOffsets(),
    llmOptions: loadLLMOptionsOffsets(),
    llmResult: loadLLMResultOffsets(),
    vlmImage: loadVLMImageOffsets(),
    vlmOptions: loadVLMOptionsOffsets(),
    vlmResult: loadVLMResultOffsets(),
    structuredOutputConfig: loadStructuredOutputConfigOffsets(),
    structuredOutputValidation: loadStructuredOutputValidationOffsets(),
    embeddingsOptions: loadEmbeddingsOptionsOffsets(),
    embeddingsResult: loadEmbeddingsResultOffsets(),
    embeddingVector: loadEmbeddingVectorOffsets(),
    diffusionOptions: loadDiffusionOptionsOffsets(),
    diffusionResult: loadDiffusionResultOffsets(),
  };

  return _cached;
}

/**
 * Get the cached offsets. Throws if loadOffsets() hasn't been called yet.
 */
export function getOffsets(): AllOffsets {
  if (!_cached) {
    // Auto-load if bridge is available
    if (LlamaCppBridge.shared.isLoaded) {
      return loadOffsets();
    }
    throw new Error('LlamaCpp offsets not loaded. Call loadOffsets() after LlamaCppBridge is loaded.');
  }
  return _cached;
}

/**
 * Convenience alias: `Offsets` provides the same access pattern as the old
 * core `Offsets` global, e.g. `Offsets.llmOptions.temperature`.
 *
 * Lazily loads offsets on first property access.
 */
export const Offsets: AllOffsets = new Proxy({} as AllOffsets, {
  get(_target, prop: string) {
    return getOffsets()[prop as keyof AllOffsets];
  },
});

/**
 * Reset the cached offsets (for testing or when the bridge is reloaded).
 */
export function resetOffsets(): void {
  _cached = null;
}
