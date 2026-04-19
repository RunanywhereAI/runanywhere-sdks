/**
 * @runanywhere/llamacpp - LlamaCPP Backend for RunAnywhere React Native SDK
 *
 * This package provides the LlamaCPP backend for on-device LLM inference.
 * It supports GGUF models and provides the same API as the iOS SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere, LLMFramework } from '@runanywhere/core';
 * import { LlamaCPP } from '@runanywhere/llamacpp';
 *
 * // Initialize core SDK
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Register LlamaCPP backend
 * LlamaCPP.register();
 *
 * // Register models via RunAnywhere (matching iOS pattern)
 * await RunAnywhere.registerModel({
 *   id: 'smollm2-360m-q8_0',
 *   name: 'SmolLM2 360M Q8_0',
 *   url: 'https://huggingface.co/.../SmolLM2-360M.Q8_0.gguf',
 *   framework: LLMFramework.LlamaCpp,
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
export { LlamaCppProvider, autoRegister } from './LlamaCppProvider';

// =============================================================================
// Native Module
// =============================================================================

export {
  NativeRunAnywhereLlama,
  getNativeLlamaModule,
  requireNativeLlamaModule,
  isNativeLlamaModuleAvailable,
} from './native/NativeRunAnywhereLlama';
export type { NativeRunAnywhereLlamaModule } from './native/NativeRunAnywhereLlama';

// =============================================================================
// VLM API
// =============================================================================

export {
  registerVLMBackend,
  loadVLMModel,
  isVLMModelLoaded,
  unloadVLMModel,
  describeImage,
  askAboutImage,
  processImage,
  processImageStream,
  cancelVLMGeneration,
} from './RunAnywhere+VLM';

// =============================================================================
// Nitrogen Spec Types
// =============================================================================

export type { RunAnywhereLlama } from './specs/RunAnywhereLlama.nitro';
