/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * Thin wrapper over native commons.
 * All business logic is in native C++ (runanywhere-commons).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { Platform } from 'react-native';
import { EventBus } from './Events';
import { requireNativeModule, isNativeModuleAvailable } from '../native';
import { SDKEnvironment } from '../types';
import { ModelRegistry } from '../services/ModelRegistry';
import { ServiceContainer } from '../Foundation/DependencyInjection/ServiceContainer';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { SDKConstants } from '../Foundation/Constants';
import { FileSystem } from '../services/FileSystem';
import {
  HTTPService,
  SDKEnvironment as NetworkSDKEnvironment,
  TelemetryService,
} from '../services/Network';

import type {
  InitializationState,
  SDKInitParams,
} from '../Foundation/Initialization';
import {
  createInitialState,
  markCoreInitialized,
  markServicesInitialized,
  markInitializationFailed,
  resetState,
} from '../Foundation/Initialization';
import type { ModelInfo, SDKInitOptions } from '../types';

// Import extensions
import * as TextGeneration from './Extensions/RunAnywhere+TextGeneration';
import * as STT from './Extensions/RunAnywhere+STT';
import * as TTS from './Extensions/RunAnywhere+TTS';
import * as VAD from './Extensions/RunAnywhere+VAD';
import * as Storage from './Extensions/RunAnywhere+Storage';
import * as Models from './Extensions/RunAnywhere+Models';
import * as Logging from './Extensions/RunAnywhere+Logging';
import * as VoiceAgent from './Extensions/RunAnywhere+VoiceAgent';
import * as VoiceSession from './Extensions/RunAnywhere+VoiceSession';
import * as StructuredOutput from './Extensions/RunAnywhere+StructuredOutput';
import * as Audio from './Extensions/RunAnywhere+Audio';

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();
let cachedDeviceId: string = '';

// ============================================================================
// Conversation Helper
// ============================================================================

/**
 * Simple conversation manager for multi-turn conversations
 */
export class Conversation {
  private messages: string[] = [];

  async send(message: string): Promise<string> {
    this.messages.push(`User: ${message}`);
    const contextPrompt = this.messages.join('\n') + '\nAssistant:';
    const result = await RunAnywhere.generate(contextPrompt);
    this.messages.push(`Assistant: ${result.text}`);
    return result.text;
  }

  get history(): string[] {
    return [...this.messages];
  }

  clear(): void {
    this.messages = [];
  }
}

// ============================================================================
// RunAnywhere SDK
// ============================================================================

/**
 * The RunAnywhere SDK for React Native
 */
export const RunAnywhere = {
  // ============================================================================
  // Event Access
  // ============================================================================

  events: EventBus,

  // ============================================================================
  // SDK State
  // ============================================================================

  get isSDKInitialized(): boolean {
    return initState.isCoreInitialized;
  },

  get areServicesReady(): boolean {
    return initState.hasCompletedServicesInit;
  },

  get currentEnvironment(): SDKEnvironment | null {
    return initState.environment;
  },

  get version(): string {
    return SDKConstants.version;
  },

  // ============================================================================
  // SDK Initialization
  // ============================================================================

  async initialize(options: SDKInitOptions): Promise<void> {
    const environment = options.environment ?? SDKEnvironment.Production;

    // Fail fast: API key is required for production/staging environments
    // Development mode uses C++ dev config (Supabase credentials) instead
    if (environment !== SDKEnvironment.Development && !options.apiKey) {
      const envName = environment === SDKEnvironment.Staging ? 'staging' : 'production';
      throw new Error(
        `API key is required for ${envName} environment. ` +
        `Pass apiKey in initialize() options or use SDKEnvironment.Development for local testing.`
      );
    }

    const initParams: SDKInitParams = {
      apiKey: options.apiKey,
      baseURL: options.baseURL,
      environment,
    };

    EventBus.publish('Initialization', { type: 'started' });
    logger.info('SDK initialization starting...');

    if (!isNativeModuleAvailable()) {
      logger.warning('Native module not available');
      initState = markInitializationFailed(
        initState,
        new Error('Native module not available')
      );
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();

    try {
      // Get documents path for model storage (matches Swift SDK's base directory setup)
      // Uses react-native-fs for the documents directory
      const documentsPath = FileSystem.isAvailable()
        ? FileSystem.getDocumentsDirectory()
        : '';

      // Configure network layer BEFORE native initialization
      // This ensures HTTP is ready when C++ callbacks need it
      const envString = environment === SDKEnvironment.Development ? 'development'
        : environment === SDKEnvironment.Staging ? 'staging'
        : 'production';

      // Map environment string to SDKEnvironment enum for HTTPService
      const networkEnv = environment === SDKEnvironment.Development
        ? NetworkSDKEnvironment.Development
        : environment === SDKEnvironment.Staging
        ? NetworkSDKEnvironment.Staging
        : NetworkSDKEnvironment.Production;

      // Configure HTTPService with network settings
      HTTPService.shared.configure({
        baseURL: options.baseURL || 'https://api.runanywhere.ai',
        apiKey: options.apiKey ?? '',
        environment: networkEnv,
      });

      // Configure dev mode if Supabase credentials provided
      if (options.supabaseURL && options.supabaseKey) {
        HTTPService.shared.configureDev({
          supabaseURL: options.supabaseURL,
          supabaseKey: options.supabaseKey,
        });
      }

      // For development mode, Supabase credentials will be passed to native
      if (environment === SDKEnvironment.Development && options.supabaseURL) {
        logger.debug('Development mode - Supabase config provided');
      }

      // Initialize with config
      // Note: Backend registration (llamacpp, onnx) is done by their respective packages
      const configJson = JSON.stringify({
        apiKey: options.apiKey,
        baseURL: options.baseURL,
        environment: envString,
        documentsPath: documentsPath, // Required for model paths (mirrors Swift SDK)
        sdkVersion: SDKConstants.version, // Centralized version for C++ layer
        supabaseURL: options.supabaseURL, // For development mode
        supabaseKey: options.supabaseKey, // For development mode
      });

      await native.initialize(configJson);

      // Initialize model registry
      await ModelRegistry.initialize();

      // Cache device ID early (uses secure storage / Keychain)
      try {
        cachedDeviceId = await native.getPersistentDeviceUUID();
        logger.debug(`Device ID cached: ${cachedDeviceId.substring(0, 8)}...`);
      } catch (e) {
        logger.warning('Failed to get persistent device UUID');
      }

      // Initialize telemetry with device ID
      TelemetryService.shared.configure(cachedDeviceId, networkEnv);
      TelemetryService.shared.trackSDKInit(envString, true);

      // For production/staging mode, authenticate with backend to get JWT tokens
      // This matches Swift SDK's CppBridge.Auth.authenticate(apiKey:) in setupHTTP()
      if (environment !== SDKEnvironment.Development && options.apiKey) {
        try {
          logger.info('Authenticating with backend (production/staging mode)...');
          const authenticated = await this._authenticateWithBackend(
            options.apiKey,
            options.baseURL || 'https://api.runanywhere.ai',
            cachedDeviceId
          );
          if (authenticated) {
            logger.info('Authentication successful - JWT tokens obtained');
          } else {
            logger.warning('Authentication failed - API requests may fail');
          }
        } catch (authErr) {
          logger.warning(`Authentication failed (non-fatal): ${authErr instanceof Error ? authErr.message : String(authErr)}`);
        }
      }

      // Trigger device registration (non-blocking, best-effort)
      // This matches Swift SDK's CppBridge.Device.registerIfNeeded(environment:)
      // Uses native C++ → platform HTTP (exactly like Swift)
      this._registerDeviceIfNeeded(environment, options.supabaseKey).catch(err => {
        logger.warning(`Device registration failed (non-fatal): ${err.message}`);
      });

      ServiceContainer.shared.markInitialized();
      initState = markCoreInitialized(initState, initParams, 'core');
      initState = markServicesInitialized(initState);

      logger.info('SDK initialized successfully');
      EventBus.publish('Initialization', { type: 'completed' });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`SDK initialization failed: ${msg}`);
      initState = markInitializationFailed(initState, error as Error);
      EventBus.publish('Initialization', { type: 'failed', error: msg });
      throw error;
    }
  },

  /**
   * Register device with backend if not already registered
   * Uses native C++ DeviceBridge + platform HTTP (URLSession/OkHttp)
   * Exactly matches Swift SDK's CppBridge.Device.registerIfNeeded(environment:)
   * @internal
   */
  /**
   * Authenticate with backend to get JWT access/refresh tokens
   * This matches Swift SDK's CppBridge.Auth.authenticate(apiKey:)
   * @internal
   */
  async _authenticateWithBackend(
    apiKey: string,
    baseURL: string,
    deviceId: string
  ): Promise<boolean> {
    try {
      const endpoint = '/api/v1/auth/sdk/authenticate';
      const fullUrl = baseURL.replace(/\/$/, '') + endpoint;

      // Use actual platform (ios/android) as backend only accepts these values
      // This matches how Swift sends 'ios' and Kotlin sends 'android'
      const platform = Platform.OS === 'ios' ? 'ios' : 'android';

      const requestBody = JSON.stringify({
        api_key: apiKey,
        device_id: deviceId,
        platform: platform,
        sdk_version: SDKConstants.version,
      });

      logger.debug(`Auth request to: ${fullUrl}`);

      const response = await fetch(fullUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: requestBody,
      });

      if (!response.ok) {
        const errorText = await response.text();
        logger.error(`Authentication failed: HTTP ${response.status} - ${errorText}`);
        return false;
      }

      const authResponse = await response.json() as {
        access_token: string;
        refresh_token: string;
        expires_in: number;
        device_id: string;
        organization_id: string;
        user_id?: string;
        token_type: string;
      };

      // Store tokens in HTTPService for subsequent requests
      HTTPService.shared.setToken(authResponse.access_token);

      // Store tokens in C++ AuthBridge for native HTTP requests (telemetry, device registration)
      try {
        const native = requireNativeModule();
        if (native && typeof native.setAuthTokens === 'function') {
          await native.setAuthTokens(JSON.stringify(authResponse));
          logger.debug('Auth tokens set in C++ AuthBridge');
        } else {
          logger.warning('setAuthTokens not available on native module - tokens stored in JS only');
        }
      } catch (nativeErr) {
        logger.warning(`Failed to set auth tokens in native: ${nativeErr}`);
        // Continue - tokens are still stored in HTTPService
      }

      // Store tokens in secure storage for persistence
      try {
        const { SecureStorageService } = await import('../Foundation/Security/SecureStorageService');
        await SecureStorageService.storeAuthTokens(
          authResponse.access_token,
          authResponse.refresh_token,
          authResponse.expires_in
        );
      } catch (storageErr) {
        logger.warning(`Failed to persist tokens: ${storageErr}`);
        // Continue - tokens are still in memory
      }

      logger.info(`Authentication successful! Token expires in ${authResponse.expires_in}s`);
      return true;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Authentication error: ${msg}`);
      return false;
    }
  },

  async _registerDeviceIfNeeded(
    environment: SDKEnvironment,
    supabaseKey?: string
  ): Promise<void> {
    const envString = environment === SDKEnvironment.Development ? 'development'
      : environment === SDKEnvironment.Staging ? 'staging'
      : 'production';

    try {
      const native = requireNativeModule();

      // Call native registerDevice which goes through:
      // JS → C++ DeviceBridge → rac_device_manager_register_if_needed → http_post callback → native HTTP
      // This exactly mirrors Swift's flow!
      const success = await native.registerDevice(JSON.stringify({
        environment: envString,
        supabaseKey: supabaseKey || '',
        buildToken: '', // TODO: Add build token support if needed
      }));

      if (success) {
        logger.info('Device registered successfully via native');
      } else {
        logger.warning('Device registration returned false');
      }
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.warning(`Device registration error: ${msg}`);
    }
  },

  async destroy(): Promise<void> {
    // Telemetry is handled by native layer - no JS-level shutdown needed
    TelemetryService.shared.setEnabled(false);

    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      await native.destroy();
    }
    ServiceContainer.shared.reset();
    initState = resetState();
  },

  async reset(): Promise<void> {
    await this.destroy();
  },

  async isInitialized(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const native = requireNativeModule();
    return native.isInitialized();
  },

  // ============================================================================
  // Authentication Info (Production/Staging only)
  // Matches Swift SDK: RunAnywhere.getUserId(), getOrganizationId(), etc.
  // ============================================================================

  /**
   * Get current user ID from authentication
   * @returns User ID if authenticated, empty string otherwise
   */
  async getUserId(): Promise<string> {
    if (!isNativeModuleAvailable()) return '';
    const native = requireNativeModule();
    const userId = await native.getUserId();
    return userId ?? '';
  },

  /**
   * Get current organization ID from authentication
   * @returns Organization ID if authenticated, empty string otherwise
   */
  async getOrganizationId(): Promise<string> {
    if (!isNativeModuleAvailable()) return '';
    const native = requireNativeModule();
    const orgId = await native.getOrganizationId();
    return orgId ?? '';
  },

  /**
   * Check if currently authenticated
   * @returns true if authenticated with valid token
   */
  async isAuthenticated(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const native = requireNativeModule();
    return native.isAuthenticated();
  },

  /**
   * Check if device is registered with backend
   */
  async isDeviceRegistered(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const native = requireNativeModule();
    return native.isDeviceRegistered();
  },

  /**
   * Clear device registration flag (for testing)
   * Forces re-registration on next SDK init
   */
  async clearDeviceRegistration(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const native = requireNativeModule();
    return native.clearDeviceRegistration();
  },

  /**
   * Get device ID (Keychain-persisted, survives reinstalls)
   * Note: This is async because it uses secure storage
   */
  get deviceId(): string {
    // Return cached value if available (set during init)
    return cachedDeviceId;
  },

  /**
   * Get device ID asynchronously (Keychain-persisted, survives reinstalls)
   */
  async getDeviceId(): Promise<string> {
    if (cachedDeviceId) {
      return cachedDeviceId;
    }
    try {
      const native = requireNativeModule();
      const uuid = await native.getPersistentDeviceUUID();
      cachedDeviceId = uuid;
      return uuid;
    } catch {
      return '';
    }
  },

  // ============================================================================
  // Logging (Delegated to Extension)
  // ============================================================================

  setLogLevel: Logging.setLogLevel,

  // ============================================================================
  // Text Generation - LLM (Delegated to Extension)
  // ============================================================================

  loadModel: TextGeneration.loadModel,
  isModelLoaded: TextGeneration.isModelLoaded,
  unloadModel: TextGeneration.unloadModel,
  chat: TextGeneration.chat,
  generate: TextGeneration.generate,
  generateStream: TextGeneration.generateStream,
  cancelGeneration: TextGeneration.cancelGeneration,

  // ============================================================================
  // Speech-to-Text (Delegated to Extension)
  // ============================================================================

  loadSTTModel: STT.loadSTTModel,
  isSTTModelLoaded: STT.isSTTModelLoaded,
  unloadSTTModel: STT.unloadSTTModel,
  transcribe: STT.transcribe,
  transcribeSimple: STT.transcribeSimple,
  transcribeBuffer: STT.transcribeBuffer,
  transcribeStream: STT.transcribeStream,
  transcribeFile: STT.transcribeFile,

  // ============================================================================
  // Text-to-Speech (Delegated to Extension)
  // ============================================================================

  loadTTSModel: TTS.loadTTSModel,
  loadTTSVoice: TTS.loadTTSVoice,
  unloadTTSVoice: TTS.unloadTTSVoice,
  isTTSModelLoaded: TTS.isTTSModelLoaded,
  isTTSVoiceLoaded: TTS.isTTSVoiceLoaded,
  unloadTTSModel: TTS.unloadTTSModel,
  synthesize: TTS.synthesize,
  synthesizeStream: TTS.synthesizeStream,
  speak: TTS.speak,
  isSpeaking: TTS.isSpeaking,
  stopSpeaking: TTS.stopSpeaking,
  availableTTSVoices: TTS.availableTTSVoices,
  stopSynthesis: TTS.stopSynthesis,

  // ============================================================================
  // Voice Activity Detection (Delegated to Extension)
  // ============================================================================

  initializeVAD: VAD.initializeVAD,
  isVADReady: VAD.isVADReady,
  loadVADModel: VAD.loadVADModel,
  isVADModelLoaded: VAD.isVADModelLoaded,
  unloadVADModel: VAD.unloadVADModel,
  detectSpeech: VAD.detectSpeech,
  processVAD: VAD.processVAD,
  startVAD: VAD.startVAD,
  stopVAD: VAD.stopVAD,
  resetVAD: VAD.resetVAD,
  setVADSpeechActivityCallback: VAD.setVADSpeechActivityCallback,
  setVADAudioBufferCallback: VAD.setVADAudioBufferCallback,
  cleanupVAD: VAD.cleanupVAD,
  getVADState: VAD.getVADState,

  // ============================================================================
  // Voice Agent (Delegated to Extension)
  // ============================================================================

  initializeVoiceAgent: VoiceAgent.initializeVoiceAgent,
  initializeVoiceAgentWithLoadedModels: VoiceAgent.initializeVoiceAgentWithLoadedModels,
  isVoiceAgentReady: VoiceAgent.isVoiceAgentReady,
  getVoiceAgentComponentStates: VoiceAgent.getVoiceAgentComponentStates,
  areAllVoiceComponentsReady: VoiceAgent.areAllVoiceComponentsReady,
  processVoiceTurn: VoiceAgent.processVoiceTurn,
  voiceAgentTranscribe: VoiceAgent.voiceAgentTranscribe,
  voiceAgentGenerateResponse: VoiceAgent.voiceAgentGenerateResponse,
  voiceAgentSynthesizeSpeech: VoiceAgent.voiceAgentSynthesizeSpeech,
  cleanupVoiceAgent: VoiceAgent.cleanupVoiceAgent,

  // ============================================================================
  // Voice Session (Delegated to Extension)
  // ============================================================================

  startVoiceSession: VoiceSession.startVoiceSession,
  startVoiceSessionWithCallback: VoiceSession.startVoiceSessionWithCallback,
  createVoiceSession: VoiceSession.createVoiceSession,

  // ============================================================================
  // Structured Output (Delegated to Extension)
  // ============================================================================

  generateStructured: StructuredOutput.generateStructured,
  generateStructuredStream: StructuredOutput.generateStructuredStream,
  extractEntities: StructuredOutput.extractEntities,
  classify: StructuredOutput.classify,

  // ============================================================================
  // Storage Management (Delegated to Extension)
  // ============================================================================

  getStorageInfo: Storage.getStorageInfo,
  clearCache: Storage.clearCache,

  // ============================================================================
  // Model Registry (Delegated to Extension)
  // ============================================================================

  getAvailableModels: Models.getAvailableModels,
  getModelInfo: Models.getModelInfo,
  isModelDownloaded: Models.isModelDownloaded,
  downloadModel: Models.downloadModel,
  cancelDownload: Models.cancelDownload,
  deleteModel: Models.deleteModel,

  // ============================================================================
  // Utilities
  // ============================================================================

  async getLastError(): Promise<string> {
    if (!isNativeModuleAvailable()) return '';
    const native = requireNativeModule();
    return native.getLastError();
  },

  async getBackendInfo(): Promise<Record<string, unknown>> {
    if (!isNativeModuleAvailable()) return {};
    const native = requireNativeModule();
    const infoJson = await native.getBackendInfo();
    try {
      return JSON.parse(infoJson);
    } catch {
      return {};
    }
  },

  /**
   * Get SDK version
   * @returns Version string
   */
  async getVersion(): Promise<string> {
    // Return centralized SDK version constant
    return SDKConstants.version;
  },

  /**
   * Get available capabilities
   * @returns Array of capability strings (llm, stt, tts, vad)
   */
  async getCapabilities(): Promise<string[]> {
    const caps: string[] = ['core'];
    // Check which backends are available
    try {
      if (await this.isModelLoaded()) caps.push('llm');
      if (await this.isSTTModelLoaded()) caps.push('stt');
      if (await this.isTTSModelLoaded()) caps.push('tts');
      if (await this.isVADModelLoaded()) caps.push('vad');
    } catch {
      // Ignore errors - these methods may not be available
    }
    return caps;
  },

  /**
   * Get downloaded models
   * @returns Array of model IDs
   */
  getDownloadedModels: Models.getDownloadedModels,

  /**
   * Clean temporary files
   */
  async cleanTempFiles(): Promise<boolean> {
    // Delegate to storage clearCache for now
    await this.clearCache();
    return true;
  },

  // ============================================================================
  // Audio Utilities (Delegated to Extension)
  // ============================================================================

  /** Audio recording and playback utilities */
  Audio: {
    requestPermission: Audio.requestAudioPermission,
    startRecording: Audio.startRecording,
    stopRecording: Audio.stopRecording,
    cancelRecording: Audio.cancelRecording,
    playAudio: Audio.playAudio,
    stopPlayback: Audio.stopPlayback,
    pausePlayback: Audio.pausePlayback,
    resumePlayback: Audio.resumePlayback,
    createWavFromPCMFloat32: Audio.createWavFromPCMFloat32,
    cleanup: Audio.cleanup,
    formatDuration: Audio.formatDuration,
    SAMPLE_RATE: Audio.AUDIO_SAMPLE_RATE,
    TTS_SAMPLE_RATE: Audio.TTS_SAMPLE_RATE,
  },

  // ============================================================================
  // Factory Methods
  // ============================================================================

  conversation(): Conversation {
    return new Conversation();
  },
};

// ============================================================================
// Type Exports
// ============================================================================

export type { ModelInfo } from '../types/models';
export type { DownloadProgress } from '../services/DownloadService';
