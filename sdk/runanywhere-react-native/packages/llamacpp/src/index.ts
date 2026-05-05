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
 * import { RunAnywhere, InferenceFramework } from '@runanywhere/core';
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
 * await RunAnywhere.downloadModel('smollm2-360m-q8_0');
 * await RunAnywhere.loadModel('smollm2-360m-q8_0');
 * const result = await RunAnywhere.generate('Hello, world!');
 * ```
 *
 * @packageDocumentation
 */

// =============================================================================
// Main API
// =============================================================================

export { LlamaCPP } from './LlamaCPP';
export { LlamaCppProvider } from './LlamaCppProvider';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereLlama } from './specs/RunAnywhereLlama.nitro';
