/**
 * @runanywhere/llamacpp - LlamaCPP Backend for RunAnywhere React Native SDK
 *
 * This package provides the LlamaCPP backend for on-device LLM inference.
 * It supports GGUF models and provides the same API as the iOS SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { RunAnywhere } from '@runanywhere/core';
 * import { LlamaCPP } from '@runanywhere/llamacpp';
 *
 * // Initialize SDK
 * await RunAnywhere.initialize({ apiKey: 'your-key' });
 *
 * // Register LlamaCPP module
 * LlamaCPP.register();
 *
 * // Add a model
 * LlamaCPP.addModel({
 *   id: 'smollm2-360m-q8_0',
 *   name: 'SmolLM2 360M Q8_0',
 *   url: 'https://huggingface.co/.../SmolLM2-360M.Q8_0.gguf',
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

export { LlamaCPP, type LlamaCPPModelOptions } from './LlamaCPP';
export { LlamaCppProvider, type LlamaCppConfiguration } from './LlamaCppProvider';
