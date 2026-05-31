/**
 * @runanywhere/llamacpp - LlamaCPP Module
 *
 * LlamaCPP module wrapper for RunAnywhere React Native SDK.
 * Provides public API for module registration only.
 *
 * Model registration is done via RunAnywhere.registerModel() / RunAnywhere.registerMultiFileModel()
 * on the core SDK, matching the Swift SDK pattern where LlamaCPP only exposes
 * register() and unregister().
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPP.swift
 */

import { LlamaCppProvider } from './LlamaCppProvider';
import { SDKLogger } from '@runanywhere/core/internal';

const log = new SDKLogger('LLM.LlamaCpp');

/**
 * LlamaCPP Module
 *
 * Matches iOS: public enum LlamaCPP: RunAnywhereModule
 *
 * Only provides backend registration. Model registration is done via
 * RunAnywhere.registerModel() on the core SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { LlamaCPP } from '@runanywhere/llamacpp';
 * import { RunAnywhere } from '@runanywhere/core';
 * // Register LlamaCPP backend
 * await LlamaCPP.register();
 *
 * // Register models via RunAnywhere (matching iOS pattern)
 * await RunAnywhere.registerModel({
 *   id: 'smollm2-360m-q8_0',
 *   name: 'SmolLM2 360M Q8_0',
 *   url: '...',
 *   framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
 *   memoryRequirement: 500_000_000
 * });
 * ```
 */
export const LlamaCPP = {
  /**
   * Register LlamaCPP module with the SDK
   *
   * Registers the LlamaCPP LLM and VLM providers with ServiceRegistry.
   *
   * Matches iOS: static func register(priority: Int = defaultPriority)
   */
  async register(): Promise<boolean> {
    log.debug('Registering LlamaCPP module');
    const registered = await LlamaCppProvider.register();
    if (registered) {
      log.info('LlamaCPP module registered');
    }
    return registered;
  },

  /**
   * Unregister LlamaCPP module from the SDK
   *
   * Matches iOS: static func unregister()
   */
  async unregister(): Promise<boolean> {
    log.info('Unregistering LlamaCPP module');
    return LlamaCppProvider.unregister();
  },

  /**
   * Check if this module is registered with the native backend registry.
   */
  async isRegistered(): Promise<boolean> {
    return LlamaCppProvider.isRegistered();
  },
};
