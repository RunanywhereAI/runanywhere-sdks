/**
 * @runanywhere/onnx - ONNX Runtime Module
 *
 * ONNX Runtime module wrapper for RunAnywhere React Native SDK.
 * Provides public API for module registration only.
 *
 * Model registration is done via RunAnywhere.registerModel() / RunAnywhere.registerMultiFileModel()
 * on the core SDK, matching the Swift SDK pattern where ONNX only exposes
 * register(), unregister(), and canHandle*().
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNX.swift
 */

import { ONNXProvider } from './ONNXProvider';
import {
  LLMFramework,
  SDKLogger,
} from '@runanywhere/core';

const logger = new SDKLogger('ONNX');

/**
 * ONNX Runtime Module
 *
 * Matches iOS: public enum ONNX: RunAnywhereModule
 *
 * Only provides backend registration. Model registration is done via
 * RunAnywhere.registerModel(framework: LLMFramework.ONNX, ...) on the core SDK.
 *
 * ## Usage
 *
 * ```typescript
 * import { ONNX } from '@runanywhere/onnx';
 * import { RunAnywhere, ModelCategory, LLMFramework } from '@runanywhere/core';
 *
 * // Register ONNX backend
 * await ONNX.register();
 *
 * // Register models via RunAnywhere (matching iOS pattern)
 * await RunAnywhere.registerModel({
 *   id: 'sherpa-onnx-whisper-tiny.en',
 *   name: 'Sherpa Whisper Tiny (ONNX)',
 *   url: '...',
 *   framework: LLMFramework.ONNX,
 *   modality: ModelCategory.SpeechRecognition,
 *   memoryRequirement: 75_000_000
 * });
 * ```
 */
export const ONNX = {
  /**
   * Module metadata
   * Matches iOS: static let moduleId, moduleName, inferenceFramework, capabilities
   */
  moduleId: 'onnx',
  moduleName: 'ONNX Runtime',
  inferenceFramework: LLMFramework.ONNX,
  capabilities: ['stt', 'tts', 'vad'] as const,
  defaultPriority: 100,

  /**
   * Register ONNX module with the SDK
   *
   * Registers both ONNX STT and TTS providers with ServiceRegistry,
   * enabling them to handle Sherpa-ONNX and Piper models.
   *
   * Matches iOS: static func register(priority: Int = defaultPriority)
   */
  async register(): Promise<void> {
    logger.info('Registering ONNX module (STT + TTS + VAD)');
    await ONNXProvider.register();
    logger.info('ONNX module registered');
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
   * Check if this module can handle STT for the given model
   * Matches iOS: static func canHandleSTT(modelId: String?) -> Bool
   */
  canHandleSTT(modelId?: string): boolean {
    return ONNXProvider.canHandleSTT(modelId);
  },

  /**
   * Check if this module can handle TTS for the given model
   * Matches iOS: static func canHandleTTS(modelId: String?) -> Bool
   */
  canHandleTTS(modelId?: string): boolean {
    return ONNXProvider.canHandleTTS(modelId);
  },

  /**
   * Check if this module can handle VAD for the given model
   * Matches iOS: static func canHandleVAD(modelId: String?) -> Bool
   */
  canHandleVAD(modelId?: string): boolean {
    return ONNXProvider.canHandleVAD(modelId);
  },
};
