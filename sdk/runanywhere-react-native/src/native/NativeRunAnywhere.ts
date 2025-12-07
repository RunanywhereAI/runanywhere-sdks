/**
 * RunAnywhere React Native SDK - Native Module Interface
 *
 * Uses Nitrogen HybridObjects for cross-platform native bindings.
 * The C++ HybridRunAnywhere implementation calls runanywhere-core C API.
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhere } from '../specs/RunAnywhere.nitro';

/**
 * Native module interface
 * Defines all methods exposed by the Nitrogen HybridObject
 */
export interface NativeRunAnywhereModule {
  // ============================================================================
  // Backend Lifecycle
  // ============================================================================

  createBackend(name: string): Promise<boolean>;
  initialize(configJson: string): Promise<boolean>;
  destroy(): Promise<void>;
  isInitialized(): Promise<boolean>;
  getBackendInfo(): Promise<string>;

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  loadTextModel(path: string, configJson?: string): Promise<boolean>;
  isTextModelLoaded(): Promise<boolean>;
  unloadTextModel(): Promise<boolean>;
  generateText(prompt: string, optionsJson?: string): Promise<string>;
  generateTextStream(
    prompt: string,
    optionsJson: string,
    callback: (token: string, isComplete: boolean) => void
  ): Promise<string>;
  cancelGeneration(): Promise<boolean>;

  // ============================================================================
  // Speech-to-Text (STT)
  // ============================================================================

  loadSTTModel(path: string, modelType: string, configJson?: string): Promise<boolean>;
  isSTTModelLoaded(): Promise<boolean>;
  unloadSTTModel(): Promise<boolean>;
  transcribe(audioBase64: string, sampleRate: number, language?: string): Promise<string>;
  supportsSTTStreaming(): Promise<boolean>;

  // ============================================================================
  // Text-to-Speech (TTS)
  // ============================================================================

  loadTTSModel(path: string, modelType: string, configJson?: string): Promise<boolean>;
  isTTSModelLoaded(): Promise<boolean>;
  unloadTTSModel(): Promise<boolean>;
  synthesize(text: string, voiceId: string, speedRate: number, pitchShift: number): Promise<string>;
  getTTSVoices(): Promise<string>;

  // ============================================================================
  // Utilities
  // ============================================================================

  getLastError(): Promise<string>;
  extractArchive(archivePath: string, destPath: string): Promise<boolean>;
  getDeviceCapabilities(): Promise<string>;
  getMemoryUsage(): Promise<number>;
}

/**
 * Get the RunAnywhere Nitrogen HybridObject
 */
function getRunAnywhere(): RunAnywhere {
  return NitroModules.createHybridObject<RunAnywhere>('RunAnywhere');
}

// Cached instance
let _cachedModule: RunAnywhere | null = null;

/**
 * Native module instance using Nitrogen
 */
function getNativeModule(): NativeRunAnywhereModule {
  if (!_cachedModule) {
    _cachedModule = getRunAnywhere();
    console.log('[NativeRunAnywhere] Created Nitrogen HybridObject');
  }
  return _cachedModule as unknown as NativeRunAnywhereModule;
}

export const NativeRunAnywhere = getNativeModule();

/**
 * Check if native module is available
 */
export function isNativeModuleAvailable(): boolean {
  try {
    getNativeModule();
    return true;
  } catch {
    return false;
  }
}

/**
 * Check if using Nitrogen implementation
 */
export function isUsingNitrogen(): boolean {
  return true; // Always using Nitrogen now
}

/**
 * Require native module (throws if not available)
 */
export function requireNativeModule(): NativeRunAnywhereModule {
  try {
    return getNativeModule();
  } catch (error) {
    throw new Error(
      '[RunAnywhere] Native module is not available. ' +
        'Make sure Nitrogen is properly installed and you are running on a device or simulator. ' +
        `Error: ${error}`
    );
  }
}
