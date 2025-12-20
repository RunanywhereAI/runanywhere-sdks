/**
 * RunAnywhere React Native SDK - Native Module Interface
 *
 * Uses Nitrogen HybridObjects for cross-platform native bindings.
 * The C++ HybridRunAnywhere implementation calls runanywhere-core C API.
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhere } from '../specs/RunAnywhere.nitro';
import type { RunAnywhereFileSystem } from '../specs/RunAnywhereFileSystem.nitro';
import type { RunAnywhereDeviceInfo } from '../specs/RunAnywhereDeviceInfo.nitro';

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
  generate(prompt: string, optionsJson?: string): Promise<string>;
  generateStream(
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
  transcribeFile(filePath: string, language?: string): Promise<string>;
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
  // STT Streaming
  // ============================================================================

  /**
   * Start streaming STT transcription
   * @param language - Optional language code
   */
  startStreamingSTT(language?: string): Promise<boolean>;

  /**
   * Stop streaming STT transcription
   */
  stopStreamingSTT(): Promise<boolean>;

  /**
   * Check if streaming STT is currently active
   */
  isStreamingSTT(): Promise<boolean>;

  // ============================================================================
  // TTS Additional
  // ============================================================================

  /**
   * Check if TTS streaming is supported
   */
  supportsTTSStreaming(): Promise<boolean>;

  /**
   * Stream TTS synthesis
   * @param text - Text to synthesize
   * @param voiceId - Voice identifier
   * @param speedRate - Speech rate
   * @param pitchShift - Pitch adjustment
   */
  synthesizeStream(
    text: string,
    voiceId: string,
    speedRate: number,
    pitchShift: number
  ): Promise<void>;

  /**
   * Cancel current TTS synthesis
   */
  cancelTTS(): Promise<boolean>;

  // ============================================================================
  // Voice Activity Detection (VAD)
  // ============================================================================

  /**
   * Load a VAD model
   * @param modelId - Model identifier
   * @param configJson - JSON configuration
   */
  loadVADModel(modelId: string, configJson?: string): Promise<boolean>;

  /**
   * Check if VAD model is loaded
   */
  isVADModelLoaded(): Promise<boolean>;

  /**
   * Reset VAD state
   */
  resetVAD(): Promise<void>;

  /**
   * Process audio through VAD
   * @param audioData - Base64 encoded audio data
   * @param sampleRate - Audio sample rate
   * @returns JSON result with isSpeech and probability
   */
  processVAD(audioData: string, sampleRate: number): Promise<string>;

  /**
   * Detect speech segments in audio
   * @param audioData - Base64 encoded audio data
   * @param sampleRate - Audio sample rate
   * @returns JSON array of segments
   */
  detectVADSegments(audioData: string, sampleRate: number): Promise<string>;

  // ============================================================================
  // Secure Storage
  // ============================================================================

  /**
   * Check if secure storage is available
   */
  secureStorageIsAvailable(): Promise<boolean>;

  /**
   * Store a value in secure storage
   * @param key - Storage key
   * @param value - Value to store
   */
  secureStorageStore(key: string, value: string): Promise<boolean>;

  /**
   * Retrieve a value from secure storage
   * @param key - Storage key
   * @returns Stored value or null
   */
  secureStorageRetrieve(key: string): Promise<string | null>;

  /**
   * Delete a value from secure storage
   * @param key - Storage key
   */
  secureStorageDelete(key: string): Promise<boolean>;

  /**
   * Check if a key exists in secure storage
   * @param key - Storage key
   */
  secureStorageExists(key: string): Promise<boolean>;

  // ============================================================================
  // Event Polling
  // ============================================================================

  /**
   * Poll for queued native events
   * @returns JSON array of events
   */
  pollEvents(): Promise<string>;

  /**
   * Clear the event queue
   */
  clearEventQueue(): Promise<void>;

  // ============================================================================
  // Capability & Model Info
  // ============================================================================

  /**
   * Get device capabilities
   * @returns JSON with capability information
   */
  getCapabilities(): Promise<string>;

  /**
   * Check if a specific capability is supported
   * @param capability - Capability name
   */
  supportsCapability(capability: string): Promise<boolean>;

  /**
   * Get model information by ID
   * @param modelId - Model identifier
   * @returns JSON model info
   */
  getModelInfo(modelId: string): Promise<string>;

  /**
   * Get list of downloaded models
   * @returns JSON array of model info
   */
  getDownloadedModels(): Promise<string>;

  // ============================================================================
  // Model Registry
  // ============================================================================

  /**
   * Discover available models
   * @returns JSON array of model info
   */
  discoverModels(): Promise<string>;

  /**
   * Get a specific model by ID
   * @param modelId - Model ID
   * @returns JSON model info
   */
  getModel(modelId: string): Promise<string>;

  /**
   * Update a model
   * @param modelId - Model ID
   * @param updateJson - JSON update data
   */
  updateModel(modelId: string, updateJson: string): Promise<void>;

  /**
   * Remove a model
   * @param modelId - Model ID
   */
  removeModel(modelId: string): Promise<void>;

  /**
   * Add a model from URL
   * @param modelId - Model ID
   * @param url - Model URL
   * @returns Task ID
   */
  addModelFromURL(modelId: string, url: string): Promise<string>;

  /**
   * Get available models
   * @returns JSON array of available models
   */
  availableModels(): Promise<string>;

  // ============================================================================
  // Authentication
  // ============================================================================

  /**
   * Authenticate with API key
   * @param apiKey - API key for authentication
   */
  authenticate(apiKey: string): Promise<boolean>;

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
   * Get access token
   */
  getAccessToken(): Promise<string | null>;

  /**
   * Refresh access token
   */
  refreshAccessToken(): Promise<string>;

  /**
   * Check if authenticated
   */
  isAuthenticated(): Promise<boolean>;

  /**
   * Clear authentication
   */
  clearAuthentication(): Promise<void>;

  /**
   * Load stored tokens
   */
  loadStoredTokens(): Promise<boolean>;

  /**
   * Register device
   */
  registerDevice(): Promise<boolean>;

  /**
   * Health check
   */
  healthCheck(): Promise<boolean>;

  // ============================================================================
  // Configuration
  // ============================================================================

  /**
   * Get current configuration
   * @returns JSON configuration data
   */
  getConfiguration(): Promise<string>;

  /**
   * Load configuration on launch
   * @returns JSON configuration data
   */
  loadConfigurationOnLaunch(): Promise<string>;

  /**
   * Set consumer configuration
   * @param configJson - JSON configuration
   */
  setConsumerConfiguration(configJson: string): Promise<void>;

  /**
   * Update configuration
   * @param configJson - JSON configuration updates
   */
  updateConfiguration(configJson: string): Promise<void>;

  /**
   * Sync configuration to cloud
   */
  syncConfigurationToCloud(): Promise<void>;

  /**
   * Clear configuration cache
   */
  clearConfigurationCache(): Promise<void>;

  /**
   * Get current environment
   */
  getCurrentEnvironment(): Promise<string>;

  // ============================================================================
  // Download Service
  // ============================================================================

  /**
   * Start model download
   * @param modelId - Model ID to download
   * @returns Task ID
   */
  startModelDownload(modelId: string): Promise<string>;

  /**
   * Cancel download
   * @param taskId - Task ID to cancel
   */
  cancelDownload(taskId: string): Promise<void>;

  /**
   * Pause download
   * @param taskId - Task ID to pause
   */
  pauseDownload(taskId: string): Promise<void>;

  /**
   * Resume download
   * @param taskId - Task ID to resume
   */
  resumeDownload(taskId: string): Promise<void>;

  /**
   * Pause all downloads
   */
  pauseAllDownloads(): Promise<void>;

  /**
   * Resume all downloads
   */
  resumeAllDownloads(): Promise<void>;

  /**
   * Cancel all downloads
   */
  cancelAllDownloads(): Promise<void>;

  /**
   * Get download progress
   * @param taskId - Task ID
   * @returns JSON progress info
   */
  getDownloadProgress(taskId: string): Promise<string>;

  /**
   * Configure download service
   * @param configJson - JSON configuration
   */
  configureDownloadService(configJson: string): Promise<void>;

  /**
   * Check if download service is healthy
   */
  isDownloadServiceHealthy(): Promise<boolean>;

  /**
   * Get download resume data
   * @param taskId - Task ID
   */
  getDownloadResumeData(taskId: string): Promise<string>;

  /**
   * Resume download with data
   * @param taskId - Task ID
   * @param resumeData - Resume data JSON
   */
  resumeDownloadWithData(taskId: string, resumeData: string): Promise<string>;

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

/**
 * Get the RunAnywhereFileSystem Nitrogen HybridObject
 */
function getRunAnywhereFileSystem(): RunAnywhereFileSystem {
  return NitroModules.createHybridObject<RunAnywhereFileSystem>('RunAnywhereFileSystem');
}

/**
 * Get the RunAnywhereDeviceInfo Nitrogen HybridObject
 */
function getRunAnywhereDeviceInfo(): RunAnywhereDeviceInfo {
  return NitroModules.createHybridObject<RunAnywhereDeviceInfo>('RunAnywhereDeviceInfo');
}

// Cached instances - lazily initialized to avoid accessing native modules
// before React Native's JS runtime is fully initialized (bridgeless mode)
let _cachedModule: RunAnywhere | null = null;
let _cachedFileSystem: RunAnywhereFileSystem | null = null;
let _cachedDeviceInfo: RunAnywhereDeviceInfo | null = null;

/**
 * Native module instance using Nitrogen
 * Lazily creates the HybridObject on first access
 */
function getNativeModule(): NativeRunAnywhereModule {
  if (!_cachedModule) {
    _cachedModule = getRunAnywhere();
    console.log('[NativeRunAnywhere] Created Nitrogen HybridObject');
  }
  return _cachedModule as unknown as NativeRunAnywhereModule;
}

/**
 * Native FileSystem module instance using Nitrogen
 * Lazily creates the HybridObject on first access
 */
function getNativeFileSystem(): RunAnywhereFileSystem {
  if (!_cachedFileSystem) {
    _cachedFileSystem = getRunAnywhereFileSystem();
    console.log('[NativeRunAnywhereFileSystem] Created Nitrogen HybridObject');
  }
  return _cachedFileSystem;
}

/**
 * Native DeviceInfo module instance using Nitrogen
 * Lazily creates the HybridObject on first access
 */
function getNativeDeviceInfo(): RunAnywhereDeviceInfo {
  if (!_cachedDeviceInfo) {
    _cachedDeviceInfo = getRunAnywhereDeviceInfo();
    console.log('[NativeRunAnywhereDeviceInfo] Created Nitrogen HybridObject');
  }
  return _cachedDeviceInfo;
}

/**
 * Lazy proxy for NativeRunAnywhere
 * Defers HybridObject creation until first property access to avoid
 * accessing native modules before React Native is fully initialized
 */
export const NativeRunAnywhere: NativeRunAnywhereModule = new Proxy({} as NativeRunAnywhereModule, {
  get(_target, prop) {
    const module = getNativeModule();
    const value = (module as any)[prop];
    if (typeof value === 'function') {
      return value.bind(module);
    }
    return value;
  },
});

/**
 * Lazy proxy for NativeRunAnywhereFileSystem
 * Defers HybridObject creation until first property access
 */
export const NativeRunAnywhereFileSystem: RunAnywhereFileSystem = new Proxy({} as RunAnywhereFileSystem, {
  get(_target, prop) {
    const module = getNativeFileSystem();
    const value = (module as any)[prop];
    if (typeof value === 'function') {
      return value.bind(module);
    }
    return value;
  },
});

/**
 * Lazy proxy for NativeRunAnywhereDeviceInfo
 * Defers HybridObject creation until first property access
 */
export const NativeRunAnywhereDeviceInfo: RunAnywhereDeviceInfo = new Proxy({} as RunAnywhereDeviceInfo, {
  get(_target, prop) {
    const module = getNativeDeviceInfo();
    const value = (module as any)[prop];
    if (typeof value === 'function') {
      return value.bind(module);
    }
    return value;
  },
});

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
 * Returns the main RunAnywhere module for backward compatibility
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

/**
 * Require FileSystem module (throws if not available)
 */
export function requireFileSystemModule(): RunAnywhereFileSystem {
  try {
    return getNativeFileSystem();
  } catch (error) {
    throw new Error(
      '[RunAnywhere] FileSystem module is not available. ' +
        `Error: ${error}`
    );
  }
}

/**
 * Require DeviceInfo module (throws if not available)
 */
export function requireDeviceInfoModule(): RunAnywhereDeviceInfo {
  try {
    return getNativeDeviceInfo();
  } catch (error) {
    throw new Error(
      '[RunAnywhere] DeviceInfo module is not available. ' +
        `Error: ${error}`
    );
  }
}
