/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * The clean, event-based RunAnywhere SDK for React Native.
 * Single entry point with both event-driven and async/await patterns.
 *
 * This file contains core SDK initialization and state.
 * Specific capabilities are implemented in Extensions/:
 * - RunAnywhere+TextGeneration.ts - LLM text generation
 * - RunAnywhere+STT.ts - Speech-to-text
 * - RunAnywhere+TTS.ts - Text-to-speech
 * - RunAnywhere+VAD.ts - Voice activity detection
 * - RunAnywhere+VoiceSession.ts - Voice session & agent
 * - RunAnywhere+Storage.ts - Storage management
 * - RunAnywhere+Models.ts - Model registry & download
 * - RunAnywhere+StructuredOutput.ts - Structured output
 * - RunAnywhere+Logging.ts - Logging configuration
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { EventBus } from './Events';
import { requireNativeModule, isNativeModuleAvailable } from '@runanywhere/native';
import { SDKEnvironment, ModelCategory } from '../types';
import { ModelRegistry } from '../services/ModelRegistry';
import { ServiceContainer } from '../Foundation/DependencyInjection/ServiceContainer';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { DeviceIdentityService } from '../Foundation/DeviceIdentity/DeviceIdentityService';
import { SDKConstants } from '../Foundation/Constants/SDKConstants';

const logger = new SDKLogger('RunAnywhere');

import type {
  InitializationPhase,
  InitializationState,
  SDKInitParams,
} from '../Foundation/Initialization';
import {
  createInitialState,
  markCoreInitialized,
  markServicesInitializing,
  markServicesInitialized,
  markInitializationFailed,
  resetState,
} from '../Foundation/Initialization';
import type {
  GenerationOptions,
  SDKInitOptions,
  STTOptions,
  TTSConfiguration,
  ModelInfo,
  LLMFramework,
} from '../types';

// Import extensions
import * as TextGeneration from './Extensions/RunAnywhere+TextGeneration';
import * as STT from './Extensions/RunAnywhere+STT';
import * as TTS from './Extensions/RunAnywhere+TTS';
import * as VAD from './Extensions/RunAnywhere+VAD';
import * as VoiceSession from './Extensions/RunAnywhere+VoiceSession';
import * as Storage from './Extensions/RunAnywhere+Storage';
import * as Models from './Extensions/RunAnywhere+Models';
import * as StructuredOutput from './Extensions/RunAnywhere+StructuredOutput';
import * as Logging from './Extensions/RunAnywhere+Logging';

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();

interface SDKState {
  initialized: boolean;
  environment: SDKEnvironment | null;
  backendType: string | null;
}

const state: SDKState = {
  initialized: false,
  environment: null,
  backendType: null,
};

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
  // SDK State (Two-Phase Initialization)
  // ============================================================================

  get isSDKInitialized(): boolean {
    return initState.isCoreInitialized;
  },

  get areServicesReady(): boolean {
    return initState.hasCompletedServicesInit;
  },

  get isActive(): boolean {
    return initState.isCoreInitialized && initState.initParams !== null;
  },

  get initializationPhase(): InitializationPhase {
    return initState.phase;
  },

  get currentEnvironment(): SDKEnvironment | null {
    return initState.environment;
  },

  get deviceId(): string | null {
    return DeviceIdentityService.getCachedDeviceUUID();
  },

  async getDeviceId(): Promise<string> {
    return DeviceIdentityService.getPersistentDeviceUUID();
  },

  get supportsLLMStreaming(): boolean {
    return ServiceContainer.shared.llmCapability.supportsStreaming;
  },

  get version(): string {
    return SDKConstants.version;
  },

  get environment(): SDKEnvironment | null {
    return initState.environment;
  },

  // ============================================================================
  // Authentication Info
  // ============================================================================

  async getUserId(): Promise<string | null> {
    if (!initState.isCoreInitialized) return null;
    try {
      const { AuthenticationService } = await import(
        '../Data/Network/Services/AuthenticationService'
      );
      const authService = ServiceContainer.shared.authenticationService;
      if (!authService || !(authService instanceof AuthenticationService)) {
        return null;
      }
      return (
        authService as InstanceType<typeof AuthenticationService>
      ).getUserId();
    } catch {
      return null;
    }
  },

  async getOrganizationId(): Promise<string | null> {
    if (!initState.isCoreInitialized) return null;
    try {
      const { AuthenticationService } = await import(
        '../Data/Network/Services/AuthenticationService'
      );
      const authService = ServiceContainer.shared.authenticationService;
      if (!authService || !(authService instanceof AuthenticationService)) {
        return null;
      }
      return (
        authService as InstanceType<typeof AuthenticationService>
      ).getOrganizationId();
    } catch {
      return null;
    }
  },

  async isDeviceRegistered(): Promise<boolean> {
    const { DeviceRegistrationService } = await import(
      '../Infrastructure/Device'
    );
    return DeviceRegistrationService.shared.isRegistered();
  },

  // ============================================================================
  // SDK Initialization
  // ============================================================================

  async initialize(options: SDKInitOptions): Promise<void> {
    const environment = options.environment ?? SDKEnvironment.Production;
    const initParams: SDKInitParams = {
      apiKey: options.apiKey,
      baseURL: options.baseURL,
      environment,
    };

    EventBus.publish('Initialization', { type: 'started' });

    logger.info(' Phase 1: Core initialization starting...');
    const phase1Start = Date.now();

    let backendType: string | null = null;

    if (!isNativeModuleAvailable()) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        logger.warning(
          'Native module not available. Running in limited development mode.'
        );
        initState = markCoreInitialized(initState, initParams, null);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        this._startPhase2InBackground();
        return;
      }
      initState = markInitializationFailed(
        initState,
        new Error('Native module not available')
      );
      throw new Error('Native module not available');
    }

    const native = requireNativeModule();
    const backendName = 'llamacpp';

    try {
      const backendCreated = native.createBackend(backendName);
      if (!backendCreated) {
        if (__DEV__ || environment === SDKEnvironment.Development) {
          logger.warning('Failed to create backend, running in limited mode');
          initState = markCoreInitialized(initState, initParams, null);
          state.initialized = true;
          state.environment = environment;
          state.backendType = null;
          EventBus.publish('Initialization', { type: 'completed' });
          this._startPhase2InBackground();
          return;
        }
        initState = markInitializationFailed(
          initState,
          new Error('Failed to create backend')
        );
        throw new Error('Failed to create backend');
      }
      backendType = backendName;
      state.backendType = backendName;
    } catch (error) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        logger.warning(`Backend creation error: ${errorMessage}`);
        initState = markCoreInitialized(initState, initParams, null);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        this._startPhase2InBackground();
        return;
      }
      initState = markInitializationFailed(initState, error as Error);
      throw error;
    }

    try {
      const configJson = JSON.stringify({
        apiKey: options.apiKey,
        baseURL: options.baseURL,
        environment: environment,
      });

      const result = native.initialize(configJson);
      if (!result) {
        if (__DEV__ || environment === SDKEnvironment.Development) {
          logger.warning(
            'Native initialize returned false, continuing in dev mode'
          );
          initState = markCoreInitialized(initState, initParams, backendType);
          state.initialized = true;
          state.environment = environment;
          EventBus.publish('Initialization', { type: 'completed' });
          this._startPhase2InBackground();
          return;
        }
        initState = markInitializationFailed(
          initState,
          new Error('Failed to initialize SDK')
        );
        throw new Error('Failed to initialize SDK');
      }
    } catch (error) {
      if (__DEV__ || environment === SDKEnvironment.Development) {
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        logger.warning(`Initialize error: ${errorMessage}`);
        initState = markCoreInitialized(initState, initParams, backendType);
        state.initialized = true;
        state.environment = environment;
        EventBus.publish('Initialization', { type: 'completed' });
        this._startPhase2InBackground();
        return;
      }
      initState = markInitializationFailed(initState, error as Error);
      throw error;
    }

    const phase1Duration = Date.now() - phase1Start;
    logger.info(`Phase 1 complete (${phase1Duration}ms)`);

    initState = markCoreInitialized(initState, initParams, backendType);
    state.initialized = true;
    state.environment = environment;
    EventBus.publish('Initialization', { type: 'completed' });

    this._startPhase2InBackground();
  },

  _startPhase2InBackground(): void {
    logger.info(' Starting Phase 2 (services) in background...');
    setTimeout(async () => {
      try {
        await this.completeServicesInitialization();
        logger.info('Phase 2 complete (background)');
      } catch (error) {
        const errorMessage =
          error instanceof Error ? error.message : String(error);
        logger.warning(`Phase 2 failed (non-critical): ${errorMessage}`);
      }
    }, 0);
  },

  async completeServicesInitialization(): Promise<void> {
    if (initState.hasCompletedServicesInit) return;
    if (!initState.isCoreInitialized) {
      throw new Error('SDK not initialized. Call initialize() first.');
    }

    initState = markServicesInitializing(initState);
    const phase2Start = Date.now();

    if (initState.initParams) {
      const params = initState.initParams;
      const environment = initState.environment ?? SDKEnvironment.Production;

      logger.info(' Initializing API client...');
      try {
        ServiceContainer.shared.initializeAPIClient(
          {
            baseURL: params.baseURL ?? '',
            apiKey: params.apiKey ?? '',
            timeout: 30000,
          },
          environment,
          undefined
        );
        logger.info(' API client initialized');
      } catch (error) {
        logger.warning('Failed to initialize API client (non-critical):', {
          error,
        });
      }
    }

    logger.info('Registering framework providers...');
    try {
      const { LlamaCppProvider } = require('../Providers/LlamaCppProvider');
      LlamaCppProvider.register();
      logger.info('LlamaCPP provider registered');
    } catch (error) {
      logger.warning('Failed to register LlamaCPP provider:', { error });
    }

    try {
      const { registerONNXProviders } = require('../Providers/ONNXProvider');
      registerONNXProviders();
      logger.info('ONNX providers registered');
    } catch (error) {
      logger.warning('Failed to register ONNX providers:', { error });
    }

    try {
      await ModelRegistry.initialize();
      logger.info('Model Registry initialized successfully');
    } catch (error) {
      logger.warning('Model Registry initialization failed (non-critical):', {
        error,
      });
    }

    try {
      const apiClient = ServiceContainer.shared.apiClient;
      const environment = initState.environment ?? SDKEnvironment.Production;

      if (apiClient) {
        const { DeviceRegistrationService } = await import(
          '../Infrastructure/Device'
        );
        await DeviceRegistrationService.shared.registerIfNeeded(
          apiClient,
          environment
        );
        logger.info('Device registration check complete');
      }
    } catch (error) {
      logger.warning('Device registration failed (non-critical):', { error });
    }

    const phase2Duration = Date.now() - phase2Start;
    logger.info(`Phase 2 complete (${phase2Duration}ms)`);
    initState = markServicesInitialized(initState);
  },

  async ensureServicesReady(): Promise<void> {
    if (initState.hasCompletedServicesInit) return;
    await this.completeServicesInitialization();
  },

  async destroy(): Promise<void> {
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      await native.destroy();
    }
    ServiceContainer.shared.reset();
    initState = resetState();
    state.initialized = false;
    state.environment = null;
    state.backendType = null;
  },

  async reset(): Promise<void> {
    await this.destroy();
  },

  async isInitialized(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return state.initialized;
    const native = requireNativeModule();
    return native.isInitialized();
  },

  async getVersion(): Promise<string> {
    return SDKConstants.version;
  },

  // ============================================================================
  // Logging (Delegated to Extension)
  // ============================================================================

  setLogLevel: Logging.setLogLevel,
  onLog: Logging.onLog,
  addLogDestination: Logging.addLogDestination,
  removeLogDestination: Logging.removeLogDestination,

  // ============================================================================
  // Text Generation - LLM (Delegated to Extension)
  // ============================================================================

  loadModel: TextGeneration.loadModel,
  loadTextModel: TextGeneration.loadTextModel,
  isModelLoaded: TextGeneration.isModelLoaded,
  isTextModelLoaded: TextGeneration.isTextModelLoaded,
  unloadModel: TextGeneration.unloadModel,
  unloadTextModel: TextGeneration.unloadTextModel,
  chat: TextGeneration.chat,
  generate: TextGeneration.generate,
  generateStream: TextGeneration.generateStream,
  cancelGeneration: TextGeneration.cancelGeneration,

  // ============================================================================
  // Structured Output (Delegated to Extension)
  // ============================================================================

  generateStructured: StructuredOutput.generateStructured,

  // ============================================================================
  // Speech-to-Text (Delegated to Extension)
  // ============================================================================

  loadSTTModel: STT.loadSTTModel,
  isSTTModelLoaded: STT.isSTTModelLoaded,
  unloadSTTModel: STT.unloadSTTModel,
  transcribe: STT.transcribe,
  transcribeFile: STT.transcribeFile,
  startStreamingSTT: STT.startStreamingSTT,
  stopStreamingSTT: STT.stopStreamingSTT,
  isStreamingSTT: STT.isStreamingSTT,

  // ============================================================================
  // Text-to-Speech (Delegated to Extension)
  // ============================================================================

  loadTTSModel: TTS.loadTTSModel,
  isTTSModelLoaded: TTS.isTTSModelLoaded,
  unloadTTSModel: TTS.unloadTTSModel,
  synthesize: TTS.synthesize,
  getTTSVoices: TTS.getTTSVoices,
  cancelTTS: TTS.cancelTTS,

  // ============================================================================
  // Voice Activity Detection (Delegated to Extension)
  // ============================================================================

  loadVADModel: VAD.loadVADModel,
  isVADModelLoaded: VAD.isVADModelLoaded,
  processVAD: VAD.processVAD,

  // ============================================================================
  // Voice Session & Voice Agent (Delegated to Extension)
  // ============================================================================

  processVoiceTurn: VoiceSession.processVoiceTurn,
  startVoiceSession: VoiceSession.startVoiceSession,
  startVoiceSessionWithCallback: VoiceSession.startVoiceSessionWithCallback,

  // ============================================================================
  // Storage Management (Delegated to Extension)
  // ============================================================================

  getStorageInfo: Storage.getStorageInfo,
  clearCache: Storage.clearCache,
  cleanTempFiles: Storage.cleanTempFiles,
  getBaseDirectoryURL: Storage.getBaseDirectoryURL,

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

  async getCapabilities(): Promise<string[]> {
    if (!isNativeModuleAvailable()) return [];
    const native = requireNativeModule();
    const capabilitiesJson = await native.getCapabilities();
    try {
      const parsed = JSON.parse(capabilitiesJson);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  },

  async supportsCapability(capability: string): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const native = requireNativeModule();
    return native.supportsCapability(capability);
  },

  // ============================================================================
  // Model Registry (Delegated to Extension)
  // ============================================================================

  getAvailableModels: Models.getAvailableModels,
  getAvailableFrameworks: Models.getAvailableFrameworks,
  getModelsForFramework: Models.getModelsForFramework,
  getModelInfo: Models.getModelInfo,
  isModelDownloaded: Models.isModelDownloaded,
  getModelPath: Models.getModelPath,
  getDownloadedModels: Models.getDownloadedModels,

  // Model Assignments (with init state)
  async fetchModelAssignments(forceRefresh = false): Promise<ModelInfo[]> {
    return Models.fetchModelAssignments(
      forceRefresh,
      initState,
      this.ensureServicesReady.bind(this)
    );
  },

  async getModelsForCategory(category: ModelCategory): Promise<ModelInfo[]> {
    return Models.getModelsForCategory(
      category,
      initState,
      this.ensureServicesReady.bind(this)
    );
  },

  async clearModelAssignmentsCache(): Promise<void> {
    return Models.clearModelAssignmentsCache(initState);
  },

  registerModel: Models.registerModel,

  // ============================================================================
  // Model Download (Delegated to Extension)
  // ============================================================================

  downloadModel: Models.downloadModel,
  cancelDownload: Models.cancelDownload,
  deleteModel: Models.deleteModel,

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
export type { DownloadProgress } from './Extensions/RunAnywhere+Models';
