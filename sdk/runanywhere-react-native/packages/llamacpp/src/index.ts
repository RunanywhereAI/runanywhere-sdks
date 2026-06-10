/**
 * @runanywhere/llamacpp - LlamaCPP Backend for RunAnywhere React Native SDK
 *
 * This package registers the LlamaCPP native providers. Public model
 * lifecycle, generation, VLM, structured-output, and LoRA APIs live in
 * @runanywhere/core.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/core';
 * import { InferenceFramework, ModelCategory } from '@runanywhere/proto-ts/model_types';
 * import { ModelLoadRequest } from '@runanywhere/proto-ts/model_types';
 * import { LlamaCPP } from '@runanywhere/llamacpp';
 *
 * // Initialize core SDK
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Register LlamaCPP backend providers
 * await LlamaCPP.register();
 *
 * // Register models via RunAnywhere (matching iOS pattern)
 * await RunAnywhere.registerModel({
 *   id: 'smollm2-360m-q8_0',
 *   name: 'SmolLM2 360M Q8_0',
 *   url: 'https://huggingface.co/.../SmolLM2-360M.Q8_0.gguf',
 *   framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
 *   memoryRequirement: 500_000_000
 * });
 *
 * // Download and use
 * const download = RunAnywhere.downloadModel('smollm2-360m-q8_0')[Symbol.asyncIterator]();
 * while (!(await download.next()).done) {}
 * await RunAnywhere.loadModel(ModelLoadRequest.fromPartial({
 *   modelId: 'smollm2-360m-q8_0',
 *   category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
 * }));
 * const result = await RunAnywhere.generate('Hello, world!');
 * ```
 *
 * @packageDocumentation
 */

// =============================================================================
// Main API
// =============================================================================

export { LlamaCPP } from './LlamaCPP';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereLlama } from './specs/RunAnywhereLlama.nitro';
