/**
 * RunAnywhere React Native SDK - Native Module Interface
 *
 * Uses Nitrogen HybridObjects for cross-platform native bindings.
 * The C++ HybridRunAnywhere implementation calls runanywhere-core C API.
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhere } from './specs/RunAnywhere.nitro';
import type { RunAnywhereFileSystem } from './specs/RunAnywhereFileSystem.nitro';
import type { RunAnywhereDeviceInfo } from './specs/RunAnywhereDeviceInfo.nitro';

// Simple internal logger for native package
const DEBUG = __DEV__;
const log = {
  debug: (msg: string) => DEBUG && console.log(`[NativeRunAnywhere] ${msg}`),
  error: (msg: string) => console.error(`[NativeRunAnywhere] ${msg}`),
};

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

  loadSTTModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;
  isSTTModelLoaded(): Promise<boolean>;
  unloadSTTModel(): Promise<boolean>;
  transcribe(
    audioBase64: string,
    sampleRate: number,
    language?: string
  ): Promise<string>;
  transcribeFile(filePath: string, language?: string): Promise<string>;
  supportsSTTStreaming(): Promise<boolean>;

  // ============================================================================
  // Text-to-Speech (TTS)
  // ============================================================================

  loadTTSModel(
    path: string,
    modelType: string,
    configJson?: string
  ): Promise<boolean>;
  isTTSModelLoaded(): Promise<boolean>;
  unloadTTSModel(): Promise<boolean>;
  synthesize(
    text: string,
    voiceId: string,
    speedRate: number,
    pitchShift: number
  ): Promise<string>;
  getTTSVoices(): Promise<string>;

  // ============================================================================
  // STT Streaming
  // ============================================================================

  startStreamingSTT(language?: string): Promise<boolean>;
  stopStreamingSTT(): Promise<boolean>;
  isStreamingSTT(): Promise<boolean>;

  // ============================================================================
  // TTS Additional
  // ============================================================================

  supportsTTSStreaming(): Promise<boolean>;
  synthesizeStream(
    text: string,
    voiceId: string,
    speedRate: number,
    pitchShift: number
  ): Promise<void>;
  cancelTTS(): Promise<boolean>;

  // ============================================================================
  // Structured Output
  // ============================================================================

  generateStructured(
    prompt: string,
    schema: string,
    optionsJson?: string
  ): Promise<string>;

  // ============================================================================
  // Voice Activity Detection (VAD)
  // ============================================================================

  loadVADModel(path: string, configJson?: string): Promise<boolean>;
  isVADModelLoaded(): Promise<boolean>;
  unloadVADModel(): Promise<boolean>;
  processVAD(audioBase64: string, optionsJson?: string): Promise<string>;
  resetVAD(): Promise<void>;

  // ============================================================================
  // Voice Agent
  // ============================================================================

  initializeVoiceAgent(configJson: string): Promise<boolean>;
  initializeVoiceAgentWithLoadedModels(): Promise<boolean>;
  isVoiceAgentReady(): Promise<boolean>;
  getVoiceAgentComponentStates(): Promise<string>;
  processVoiceTurn(audioBase64: string): Promise<string>;
  voiceAgentTranscribe(audioBase64: string): Promise<string>;
  voiceAgentGenerateResponse(prompt: string): Promise<string>;
  voiceAgentSynthesizeSpeech(text: string): Promise<string>;
  cleanupVoiceAgent(): Promise<void>;

  // ============================================================================
  // Model Assignment
  // ============================================================================

  assignModel(modelId: string, framework: string): Promise<boolean>;
  getModelAssignment(modelId: string): Promise<string>;
  clearModelAssignments(): Promise<void>;

  // ============================================================================
  // Model Registry (Additional)
  // ============================================================================

  getAvailableModels(): Promise<string>;
  isModelDownloaded(modelId: string): Promise<boolean>;
  getModelPath(modelId: string): Promise<string>;

  // ============================================================================
  // Download Service (Additional)
  // ============================================================================

  downloadModel(modelId: string, url: string, destPath: string): Promise<boolean>;

  // ============================================================================
  // Device Registration
  // ============================================================================

  registerDevice(environmentJson: string): Promise<boolean>;
  isDeviceRegistered(): Promise<boolean>;

  // ============================================================================
  // HTTP Client
  // ============================================================================

  configureHttp(baseUrl: string, apiKey: string): Promise<boolean>;
  httpPost(path: string, bodyJson: string): Promise<string>;
  httpGet(path: string): Promise<string>;

  // ============================================================================
  // Events
  // ============================================================================

  emitEvent(eventJson: string): Promise<void>;

  // ============================================================================
  // Storage
  // ============================================================================

  getStorageInfo(): Promise<string>;
  clearCache(): Promise<boolean>;
  deleteModel(modelId: string): Promise<boolean>;

  // ============================================================================
  // Secure Storage
  // ============================================================================

  secureStorageIsAvailable(): Promise<boolean>;
  secureStorageStore(key: string, value: string): Promise<boolean>;
  secureStorageRetrieve(key: string): Promise<string | null>;
  secureStorageDelete(key: string): Promise<boolean>;
  secureStorageExists(key: string): Promise<boolean>;

  // ============================================================================
  // Event Polling
  // ============================================================================

  pollEvents(): Promise<string>;
  clearEventQueue(): Promise<void>;

  // ============================================================================
  // Capability & Model Info
  // ============================================================================

  getCapabilities(): Promise<string>;
  supportsCapability(capability: string): Promise<boolean>;
  getModelInfo(modelId: string): Promise<string>;
  getDownloadedModels(): Promise<string>;

  // ============================================================================
  // Model Registry
  // ============================================================================

  discoverModels(): Promise<string>;
  getModel(modelId: string): Promise<string>;
  updateModel(modelId: string, updateJson: string): Promise<void>;
  removeModel(modelId: string): Promise<void>;
  addModelFromURL(modelId: string, url: string): Promise<string>;
  availableModels(): Promise<string>;

  // ============================================================================
  // Authentication
  // ============================================================================

  authenticate(apiKey: string): Promise<boolean>;
  getUserId(): Promise<string | null>;
  getOrganizationId(): Promise<string | null>;
  getDeviceId(): Promise<string | null>;
  getAccessToken(): Promise<string | null>;
  refreshAccessToken(): Promise<string>;
  isAuthenticated(): Promise<boolean>;
  clearAuthentication(): Promise<void>;
  loadStoredTokens(): Promise<boolean>;
  registerDevice(): Promise<boolean>;
  healthCheck(): Promise<boolean>;

  // ============================================================================
  // Configuration
  // ============================================================================

  getConfiguration(): Promise<string>;
  loadConfigurationOnLaunch(): Promise<string>;
  setConsumerConfiguration(configJson: string): Promise<void>;
  updateConfiguration(configJson: string): Promise<void>;
  syncConfigurationToCloud(): Promise<void>;
  clearConfigurationCache(): Promise<void>;
  getCurrentEnvironment(): Promise<string>;

  // ============================================================================
  // Download Service
  // ============================================================================

  startModelDownload(modelId: string): Promise<string>;
  cancelDownload(taskId: string): Promise<void>;
  pauseDownload(taskId: string): Promise<void>;
  resumeDownload(taskId: string): Promise<void>;
  pauseAllDownloads(): Promise<void>;
  resumeAllDownloads(): Promise<void>;
  cancelAllDownloads(): Promise<void>;
  getDownloadProgress(taskId: string): Promise<string>;
  configureDownloadService(configJson: string): Promise<void>;
  isDownloadServiceHealthy(): Promise<boolean>;
  getDownloadResumeData(taskId: string): Promise<string>;
  resumeDownloadWithData(taskId: string, resumeData: string): Promise<string>;

  // ============================================================================
  // Utilities
  // ============================================================================

  getLastError(): Promise<string>;
  extractArchive(archivePath: string, destPath: string): Promise<boolean>;
  getDeviceCapabilities(): Promise<string>;
  getMemoryUsage(): Promise<number>;

  // ============================================================================
  // Backend Registration
  // ============================================================================

  /**
   * Register the LlamaCPP backend with the C++ service registry.
   * Calls rac_backend_llamacpp_register() from runanywhere-core.
   */
  registerLlamaCppBackend(): Promise<boolean>;

  /**
   * Unregister the LlamaCPP backend from the C++ service registry.
   */
  unregisterLlamaCppBackend(): Promise<boolean>;

  /**
   * Register the ONNX backend with the C++ service registry.
   * Calls rac_backend_onnx_register() from runanywhere-core.
   */
  registerONNXBackend(): Promise<boolean>;

  /**
   * Unregister the ONNX backend from the C++ service registry.
   */
  unregisterONNXBackend(): Promise<boolean>;
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
  return NitroModules.createHybridObject<RunAnywhereFileSystem>(
    'RunAnywhereFileSystem'
  );
}

/**
 * Get the RunAnywhereDeviceInfo Nitrogen HybridObject
 */
function getRunAnywhereDeviceInfo(): RunAnywhereDeviceInfo {
  return NitroModules.createHybridObject<RunAnywhereDeviceInfo>(
    'RunAnywhereDeviceInfo'
  );
}

// Cached instances - lazily initialized
let _cachedModule: RunAnywhere | null = null;
let _cachedFileSystem: RunAnywhereFileSystem | null = null;
let _cachedDeviceInfo: RunAnywhereDeviceInfo | null = null;

/**
 * Native module instance using Nitrogen
 */
function getNativeModule(): NativeRunAnywhereModule {
  if (!_cachedModule) {
    _cachedModule = getRunAnywhere();
    log.debug('Created Nitrogen HybridObject');
  }
  return _cachedModule as unknown as NativeRunAnywhereModule;
}

/**
 * Native FileSystem module instance using Nitrogen
 */
function getNativeFileSystem(): RunAnywhereFileSystem {
  if (!_cachedFileSystem) {
    _cachedFileSystem = getRunAnywhereFileSystem();
    log.debug('Created FileSystem Nitrogen HybridObject');
  }
  return _cachedFileSystem;
}

/**
 * Native DeviceInfo module instance using Nitrogen
 */
function getNativeDeviceInfo(): RunAnywhereDeviceInfo {
  if (!_cachedDeviceInfo) {
    _cachedDeviceInfo = getRunAnywhereDeviceInfo();
    log.debug('Created DeviceInfo Nitrogen HybridObject');
  }
  return _cachedDeviceInfo;
}

/**
 * Lazy proxy for NativeRunAnywhere
 */
export const NativeRunAnywhere: NativeRunAnywhereModule = new Proxy(
  {} as NativeRunAnywhereModule,
  {
    get(_target, prop) {
      const module = getNativeModule();
      const value = (module as unknown as Record<string | symbol, unknown>)[
        prop
      ];
      if (typeof value === 'function') {
        return (value as (...args: unknown[]) => unknown).bind(module);
      }
      return value;
    },
  }
);

/**
 * Lazy proxy for NativeRunAnywhereFileSystem
 */
export const NativeRunAnywhereFileSystem: RunAnywhereFileSystem = new Proxy(
  {} as RunAnywhereFileSystem,
  {
    get(_target, prop) {
      const module = getNativeFileSystem();
      const value = (module as unknown as Record<string | symbol, unknown>)[
        prop
      ];
      if (typeof value === 'function') {
        return (value as (...args: unknown[]) => unknown).bind(module);
      }
      return value;
    },
  }
);

/**
 * Lazy proxy for NativeRunAnywhereDeviceInfo
 */
export const NativeRunAnywhereDeviceInfo: RunAnywhereDeviceInfo = new Proxy(
  {} as RunAnywhereDeviceInfo,
  {
    get(_target, prop) {
      const module = getNativeDeviceInfo();
      const value = (module as unknown as Record<string | symbol, unknown>)[
        prop
      ];
      if (typeof value === 'function') {
        return (value as (...args: unknown[]) => unknown).bind(module);
      }
      return value;
    },
  }
);

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
  return true;
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

/**
 * Require FileSystem module (throws if not available)
 */
export function requireFileSystemModule(): RunAnywhereFileSystem {
  try {
    return getNativeFileSystem();
  } catch (error) {
    throw new Error(
      '[RunAnywhere] FileSystem module is not available. ' + `Error: ${error}`
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
      '[RunAnywhere] DeviceInfo module is not available. ' + `Error: ${error}`
    );
  }
}
