/**
 * RunAnywhere React Native SDK - Native Module Interface
 *
 * Type definitions for the native module bridge.
 * These types define the interface between JS and native code.
 */

import { NativeModules, Platform } from 'react-native';
import type {
  GenerationOptions,
  GenerationResult,
  LLMFramework,
  ModelInfo,
  SDKEnvironment,
  STTOptions,
  STTResult,
  TTSConfiguration,
} from '../types';

/**
 * Native module interface
 * Defines all methods exposed by the native module
 */
export interface NativeRunAnywhereModule {
  // ============================================================================
  // Initialization
  // ============================================================================

  /**
   * Initialize the SDK
   */
  initialize(
    apiKey: string,
    baseURL: string,
    environment: SDKEnvironment
  ): Promise<void>;

  /**
   * Reset SDK state
   */
  reset(): Promise<void>;

  /**
   * Check if SDK is initialized
   */
  isInitialized(): Promise<boolean>;

  /**
   * Check if SDK is active
   */
  isActive(): Promise<boolean>;

  // ============================================================================
  // Identity
  // ============================================================================

  /**
   * Get current user ID
   */
  getUserId(): Promise<string | null>;

  /**
   * Get current organization ID
   */
  getOrganizationId(): Promise<string | null>;

  /**
   * Get device ID
   */
  getDeviceId(): Promise<string | null>;

  /**
   * Get SDK version
   */
  getSDKVersion(): Promise<string>;

  /**
   * Get current environment
   */
  getCurrentEnvironment(): Promise<SDKEnvironment | null>;

  /**
   * Check if device is registered
   */
  isDeviceRegistered(): Promise<boolean>;

  // ============================================================================
  // Text Generation
  // ============================================================================

  /**
   * Simple chat - returns text only
   */
  chat(prompt: string): Promise<string>;

  /**
   * Generate text with options and full result
   */
  generate(prompt: string, options?: GenerationOptions): Promise<GenerationResult>;

  /**
   * Start streaming generation
   * Returns a session ID; tokens come via events
   */
  generateStreamStart(prompt: string, options?: GenerationOptions): Promise<string>;

  /**
   * Cancel streaming generation
   */
  generateStreamCancel(sessionId: string): Promise<void>;

  // ============================================================================
  // Model Management
  // ============================================================================

  /**
   * Load a model by ID
   */
  loadModel(modelId: string): Promise<void>;

  /**
   * Get available models
   */
  availableModels(): Promise<ModelInfo[]>;

  /**
   * Get currently loaded model
   */
  currentModel(): Promise<ModelInfo | null>;

  /**
   * Download a model
   */
  downloadModel(modelId: string): Promise<void>;

  /**
   * Delete a downloaded model
   */
  deleteModel(modelId: string): Promise<void>;

  /**
   * Get available adapters for a model
   */
  availableAdapters(modelId: string): Promise<LLMFramework[]>;

  // ============================================================================
  // Voice Operations
  // ============================================================================

  /**
   * Transcribe audio data
   * @param audioBase64 - Base64 encoded audio data
   */
  transcribe(audioBase64: string, options?: STTOptions): Promise<STTResult>;

  /**
   * Load an STT model
   */
  loadSTTModel(modelId: string): Promise<void>;

  /**
   * Load a TTS model
   */
  loadTTSModel(modelId: string): Promise<void>;

  /**
   * Synthesize text to speech
   * @returns Base64 encoded audio data
   */
  synthesize(text: string, configuration?: TTSConfiguration): Promise<string>;

  // ============================================================================
  // Utilities
  // ============================================================================

  /**
   * Estimate token count for text
   */
  estimateTokenCount(text: string): Promise<number>;

  // ============================================================================
  // Constants (if module exports constants)
  // ============================================================================
  getConstants?(): {
    sdkVersion: string;
    platform: string;
  };
}

/**
 * Get the native module with proper typing
 */
function getNativeModule(): NativeRunAnywhereModule | null {
  const module = NativeModules.RunAnywhereModule;

  if (!module) {
    if (__DEV__) {
      console.warn(
        '[RunAnywhere] Native module not found. ' +
          'Make sure the native module is properly linked. ' +
          `Platform: ${Platform.OS}`
      );
    }
    return null;
  }

  return module as NativeRunAnywhereModule;
}

/**
 * Native module instance
 * May be null if native module is not available (e.g., in web or testing)
 */
export const NativeRunAnywhere = getNativeModule();

/**
 * Check if native module is available
 */
export function isNativeModuleAvailable(): boolean {
  return NativeRunAnywhere !== null;
}

/**
 * Require native module (throws if not available)
 */
export function requireNativeModule(): NativeRunAnywhereModule {
  if (!NativeRunAnywhere) {
    throw new Error(
      '[RunAnywhere] Native module is not available. ' +
        'Make sure the native module is properly linked and you are running on a device or simulator.'
    );
  }
  return NativeRunAnywhere;
}
