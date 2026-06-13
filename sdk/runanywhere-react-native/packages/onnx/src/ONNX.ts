/**
 * @runanywhere/onnx - ONNX Runtime Module
 *
 * ONNX Runtime module wrapper for RunAnywhere React Native SDK.
 * Provides public API for module registration only.
 *
 * Model registration is done via RunAnywhere.registerModel() / RunAnywhere.registerMultiFileModel()
 * on the core SDK, matching the Swift SDK pattern where ONNX only exposes
 * register() and unregister().
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNX.swift
 */

import { ONNXProvider } from './ONNXProvider';
import { SDKLogger } from '@runanywhere/core/internal';

const logger = new SDKLogger('ONNX');

/**
 * ONNX Runtime Module
 *
 * Matches iOS: public enum ONNX: RunAnywhereModule
 *
 * Only provides backend registration. Model registration is done via
 * RunAnywhere.registerModel(framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX, ...) on the core SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { ONNX } from '@runanywhere/onnx';
 * import { RunAnywhere } from '@runanywhere/core';
 * import { ModelCategory, InferenceFramework } from '@runanywhere/proto-ts/model_types';
 *
 * // Register ONNX backend providers
 * await ONNX.register();
 *
 * // Register models via RunAnywhere (matching iOS pattern)
 * await RunAnywhere.registerModel({
 *   id: 'sherpa-onnx-whisper-tiny.en',
 *   name: 'Sherpa Whisper Tiny (ONNX)',
 *   url: '...',
 *   framework: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
 *   modality: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
 *   memoryRequirement: 75_000_000
 * });
 * ```
 */
export const ONNX = {
  // Module-metadata constants (moduleId / moduleName / inferenceFramework /
  // capabilities / defaultPriority) were removed: the Swift source of truth
  // (Sources/ONNXRuntime/ONNX.swift) no longer declares them and nothing
  // consumed them here.

  /**
   * Register ONNX module with the SDK
   *
   * Registers both ONNX STT and TTS providers with ServiceRegistry,
   * enabling them to handle Sherpa-ONNX and Piper models.
   *
   * Matches iOS: static func register(priority: Int = 100)
   */
  async register(): Promise<boolean> {
    logger.info('Registering ONNX module (STT + TTS + VAD)');
    const registered = await ONNXProvider.register();
    if (registered) {
      logger.info('ONNX module registered');
    }
    return registered;
  },

  /**
   * Unregister ONNX module from the SDK
   *
   * Matches iOS: static func unregister()
   */
  async unregister(): Promise<boolean> {
    logger.info('Unregistering ONNX module');
    return ONNXProvider.unregister();
  },

  /**
   * Check if this module is registered with the native backend registry.
   */
  async isRegistered(): Promise<boolean> {
    return ONNXProvider.isRegistered();
  },
};
