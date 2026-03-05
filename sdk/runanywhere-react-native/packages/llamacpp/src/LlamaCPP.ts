/**
 * @runanywhere/llamacpp - LlamaCPP Module
 *
 * LlamaCPP module wrapper for RunAnywhere React Native SDK.
 * Provides public API for module registration only.
 *
 * Model registration is done via RunAnywhere.registerModel() / RunAnywhere.registerMultiFileModel()
 * on the core SDK, matching the Swift SDK pattern where LlamaCPP only exposes
 * register(), unregister(), and canHandle().
 *
 * Reference: sdk/runanywhere-swift/Sources/LlamaCPPRuntime/LlamaCPP.swift
 */

import { LlamaCppProvider } from './LlamaCppProvider';
import {
  LLMFramework,
  SDKLogger,
} from '@runanywhere/core';

const log = new SDKLogger('LLM.LlamaCpp');

/**
 * LlamaCPP Module
 *
 * Matches iOS: public enum LlamaCPP: RunAnywhereModule
 *
 * Only provides backend registration. Model registration is done via
 * RunAnywhere.registerModel(framework: LLMFramework.LlamaCpp, ...) on the core SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { LlamaCPP } from '@runanywhere/llamacpp';
 * import { RunAnywhere, LLMFramework } from '@runanywhere/core';
 *
 * // Register LlamaCPP backend
 * LlamaCPP.register();
 *
 * // Register models via RunAnywhere (matching iOS pattern)
 * await RunAnywhere.registerModel({
 *   id: 'smollm2-360m-q8_0',
 *   name: 'SmolLM2 360M Q8_0',
 *   url: '...',
 *   framework: LLMFramework.LlamaCpp,
 *   memoryRequirement: 500_000_000
 * });
 * ```
 */
export const LlamaCPP = {
  /**
   * Module metadata
   * Matches iOS: static let moduleId, moduleName, inferenceFramework, capabilities
   */
  moduleId: 'llamacpp',
  moduleName: 'LlamaCPP',
  inferenceFramework: LLMFramework.LlamaCpp,
  capabilities: ['llm'] as const,
  defaultPriority: 100,

  /**
   * Register LlamaCPP module with the SDK
   *
   * Registers the LlamaCPP LLM and VLM providers with ServiceRegistry.
   *
   * Matches iOS: static func register(priority: Int = defaultPriority)
   */
  register(): void {
    log.debug('Registering LlamaCPP module');
    LlamaCppProvider.register();
    log.info('LlamaCPP module registered');
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
   * Check if this module can handle the given model
   * Matches iOS: static func canHandle(modelId: String?) -> Bool
   */
  canHandle(modelId?: string): boolean {
    return LlamaCppProvider.canHandle(modelId);
  },
};
