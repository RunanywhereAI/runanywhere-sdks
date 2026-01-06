/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * Thin wrapper over native commons.
 * All business logic is in native C++ (runanywhere-commons).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { EventBus } from './Events';
import { requireNativeModule, isNativeModuleAvailable, requireDeviceInfoModule } from '@runanywhere/native';
import { SDKEnvironment } from '../types';
import { ModelRegistry } from '../services/ModelRegistry';
import { ServiceContainer } from '../Foundation/DependencyInjection/ServiceContainer';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

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

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();

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
    return '0.2.0';
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
      // Create backend
      const backendCreated = native.createBackend('llamacpp');
      if (!backendCreated) {
        logger.warning('Failed to create backend');
      }

      // Initialize with config
      const configJson = JSON.stringify({
        apiKey: options.apiKey,
        baseURL: options.baseURL,
        environment: environment,
      });

      native.initialize(configJson);

      // Store API config
      ServiceContainer.shared.setAPIConfig(options.apiKey, environment);

      // Initialize model registry
      await ModelRegistry.initialize();

      initState = markCoreInitialized(initState, initParams, 'llamacpp');
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

  async destroy(): Promise<void> {
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
   * Get device ID (Keychain-persisted, survives reinstalls)
   */
  get deviceId(): string {
    try {
      const deviceInfo = requireDeviceInfoModule();
      // Device info module returns an object with getDeviceIdSync or similar
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const info = deviceInfo as any;
      return info.deviceId ?? info.getDeviceIdSync?.() ?? info.uniqueId ?? '';
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
