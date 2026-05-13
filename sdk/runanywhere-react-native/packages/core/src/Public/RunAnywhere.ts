/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * Thin wrapper over native commons.
 * All business logic is in native C++ (runanywhere-commons).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../native';
import { SDKEnvironment } from '../types';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { SDKConstants } from '../Foundation/Constants';
import {
  DEFAULT_BASE_URL,
  isUsableCredential,
} from '../services/Network/NetworkConfiguration';

import type {
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
import type { SDKInitOptions } from '../types';
import {
  EventDestination,
  InitializationStage,
  SDKComponent,
  SDKEvent as SDKEventCodec,
} from '@runanywhere/proto-ts/sdk_events';
import { EventCategory } from '@runanywhere/proto-ts/component_types';
import { ErrorSeverity } from '@runanywhere/proto-ts/errors';

// Import extensions
import * as TextGeneration from './Extensions/LLM/RunAnywhere+TextGeneration';
import * as STT from './Extensions/STT/RunAnywhere+STT';
import * as TTS from './Extensions/TTS/RunAnywhere+TTS';
import * as VAD from './Extensions/VAD/RunAnywhere+VAD';
import * as Storage from './Extensions/Storage/RunAnywhere+Storage';
import * as SDKEvents from './Events/RunAnywhere+SDKEvents';
import * as Lifecycle from './Extensions/Models/RunAnywhere+ModelLifecycle';
import * as Logging from './Extensions/RunAnywhere+Logging';
import { pluginLoader as PluginLoaderCapability } from './Extensions/RunAnywhere+PluginLoader';
import * as VoiceAgent from './Extensions/VoiceAgent/RunAnywhere+VoiceAgent';
// v3.1: RunAnywhere+VoiceSession.ts deleted — use VoiceAgentStreamAdapter.
import * as StructuredOutput from './Extensions/LLM/RunAnywhere+StructuredOutput';
import * as Audio from './Extensions/RunAnywhere+Audio';
import * as ToolCalling from './Extensions/LLM/RunAnywhere+ToolCalling';
import * as RAG from './Extensions/RAG/RunAnywhere+RAG';
import * as VLM from './Extensions/VLM/RunAnywhere+VisionLanguage';
import { lora as LoRACapability } from './Extensions/LLM/RunAnywhere+LoRA';
import { solutions as SolutionsCapability } from './Extensions/Solutions/RunAnywhere+Solutions';
import { startLiveTranscription } from './Sessions/LiveTranscriptionSession';
import * as VLMModels from './Extensions/VLM/RunAnywhere+VLMModels';
import * as ModelManagement from './Extensions/Models/RunAnywhere+ModelRegistry';
import { Hardware as HardwareNamespace } from './Extensions/RunAnywhere+Hardware';

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();
let servicesInitPromise: Promise<void> | null = null;

type NativePhase2Module = {
  completeServicesInitialization?: () => Promise<unknown>;
  initializeServices?: () => Promise<unknown>;
  sdkInitPhase2?: () => Promise<unknown>;
  sdkInitPhase2Proto?: () => Promise<unknown>;
};

const sdkEventSurface = {
  subscribe: SDKEvents.subscribeSDKEvents,
  publish: SDKEvents.publishSDKEvent,
  poll: SDKEvents.pollSDKEvent,
  publishFailure: SDKEvents.publishSDKFailure,
};

function publishInitializationEvent(
  stage: InitializationStage,
  error = ''
): void {
  void SDKEvents.publishSDKEvent(
    SDKEventCodec.fromPartial({
      timestampMs: Date.now(),
      severity: error
        ? ErrorSeverity.ERROR_SEVERITY_ERROR
        : ErrorSeverity.ERROR_SEVERITY_INFO,
      category: EventCategory.EVENT_CATEGORY_INITIALIZATION,
      component: SDKComponent.SDK_COMPONENT_UNSPECIFIED,
      id: `rn-init-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      destination: EventDestination.EVENT_DESTINATION_ALL,
      operationId: 'sdk.initialize',
      source: 'react_native',
      initialization: {
        stage,
        source: 'react_native',
        error,
        version: SDKConstants.version,
      },
    })
  ).catch(() => undefined);
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

  events: sdkEventSurface,

  // ============================================================================
  // SDK State
  // ============================================================================

  get isInitialized(): boolean {
    return initState.isCoreInitialized;
  },

  get areServicesReady(): boolean {
    return initState.hasCompletedServicesInit;
  },

  get environment(): SDKEnvironment | null {
    return initState.environment;
  },

  get version(): string {
    return SDKConstants.version;
  },

  // ============================================================================
  // SDK Initialization
  // ============================================================================

  async initialize(options: SDKInitOptions = {}): Promise<void> {
    const environment = options.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    const effectiveBaseURL = options.baseURL?.trim() || DEFAULT_BASE_URL;
    const effectiveApiKey = isUsableCredential(options.apiKey)
      ? options.apiKey!.trim()
      : '';

    const initParams: SDKInitParams = {
      apiKey: effectiveApiKey,
      baseURL: effectiveBaseURL,
      environment,
    };

    publishInitializationEvent(InitializationStage.INITIALIZATION_STAGE_STARTED);
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
      const envString = environment === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT ? 'development'
        : environment === SDKEnvironment.SDK_ENVIRONMENT_STAGING ? 'staging'
          : 'production';

      // RN still crosses an async native bridge for Phase 1. The work belongs
      // to native commons; TypeScript only builds the call-site config.
      const configJson = JSON.stringify({
        apiKey: effectiveApiKey,
        baseURL: effectiveBaseURL,
        environment: envString,
        sdkVersion: SDKConstants.version,
        supabaseURL: options.supabaseURL,
        supabaseKey: options.supabaseKey,
        buildToken: options.buildToken,
      });

      const initialized = await native.initialize(configJson);
      if (initialized === false) {
        throw new Error('Native SDK initialization failed');
      }

      initState = markCoreInitialized(initState, initParams, 'core');

      logger.info('SDK initialized successfully');
      publishInitializationEvent(InitializationStage.INITIALIZATION_STAGE_COMPLETED);

      servicesInitPromise = null;
      void this.completeServicesInitialization().catch(err => {
        logger.warning(
          `Phase 2 services initialization failed (non-fatal): ${
            err instanceof Error ? err.message : String(err)
          }`
        );
      });
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`SDK initialization failed: ${msg}`);
      initState = markInitializationFailed(initState, error as Error);
      publishInitializationEvent(
        InitializationStage.INITIALIZATION_STAGE_FAILED,
        msg
      );
      throw error;
    }
  },

  async destroy(): Promise<void> {
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      await native.destroy();
    }
    initState = resetState();
    servicesInitPromise = null;
  },

  async reset(): Promise<void> {
    await this.destroy();
  },

  /**
   * Whether the SDK has completed core initialization.
   *
   * Matches Swift: `RunAnywhere.isActive`.
   */
  get isActive(): boolean {
    return initState.isCoreInitialized && initState.environment !== null;
  },

  /**
   * Retry just the Phase-2 (services) initialisation. Useful after a
   * transient connectivity failure where Phase 1 (core) succeeded but
   * services init failed or was skipped.
   *
   * Matches Swift: `RunAnywhere.completeServicesInitialization()`.
   */
  async completeServicesInitialization(): Promise<void> {
    if (!initState.isCoreInitialized) {
      throw new Error(
        'completeServicesInitialization() requires the SDK core to be initialised. Call initialize() first.'
      );
    }
    if (initState.hasCompletedServicesInit) {
      logger.debug('Services already initialised; nothing to do.');
      return;
    }

    if (servicesInitPromise) {
      return servicesInitPromise;
    }

    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    servicesInitPromise = (async () => {
      const native = requireNativeModule();
      const nativePhase2 = native as NativePhase2Module;

      initState = markServicesInitializing(initState);

      let phase2Result: unknown = undefined;
      if (typeof nativePhase2.completeServicesInitialization === 'function') {
        phase2Result = await nativePhase2.completeServicesInitialization.call(native);
      } else if (typeof nativePhase2.sdkInitPhase2Proto === 'function') {
        phase2Result = await nativePhase2.sdkInitPhase2Proto.call(native);
      } else if (typeof nativePhase2.sdkInitPhase2 === 'function') {
        phase2Result = await nativePhase2.sdkInitPhase2.call(native);
      } else if (typeof nativePhase2.initializeServices === 'function') {
        phase2Result = await nativePhase2.initializeServices.call(native);
      } else {
        const initialized = await native.isInitialized();
        if (!initialized) {
          throw new Error('Native core is not initialized');
        }
        logger.debug('Native phase 2 bridge not available; core native init is already complete.');
      }
      if (phase2Result === false) {
        throw new Error('Native services initialization failed');
      }

      initState = markServicesInitialized(initState);
      logger.info('Services initialisation completed.');
      publishInitializationEvent(InitializationStage.INITIALIZATION_STAGE_COMPLETED);
    })();

    try {
      await servicesInitPromise;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Services initialisation failed: ${msg}`);
      publishInitializationEvent(
        InitializationStage.INITIALIZATION_STAGE_FAILED,
        msg
      );
      throw error;
    } finally {
      servicesInitPromise = null;
    }
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
   * Check if currently authenticated.
   *
   * Matches Swift: `RunAnywhere.isAuthenticated`, delegated to native auth state.
   */
  get isAuthenticated(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return Promise.resolve(false);
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
   * Get device ID from native device state.
   */
  async getDeviceId(): Promise<string> {
    if (!isNativeModuleAvailable()) return '';
    const native = requireNativeModule();
    return (await native.getDeviceId()) || (await native.getPersistentDeviceUUID()) || '';
  },

  /**
   * Device ID (Keychain/Keystore-persisted, survives reinstalls).
   * RN resolves this through the async native bridge.
   */
  get deviceId(): Promise<string> {
    return this.getDeviceId();
  },

  // ============================================================================
  // Logging (Delegated to Extension)
  // ============================================================================

  configureLogging: Logging.configureLogging,
  setLocalLoggingEnabled: Logging.setLocalLoggingEnabled,
  setLogLevel: Logging.setLogLevel,
  setSentryLoggingEnabled: Logging.setSentryLoggingEnabled,
  addLogDestination: Logging.addLogDestination,
  setDebugMode: Logging.setDebugMode,
  flushLogs: Logging.flushLogs,

  // ============================================================================
  // Plugin Loader — canonical RunAnywhere.pluginLoader namespace
  // ============================================================================

  pluginLoader: PluginLoaderCapability,

  // ============================================================================
  // Text Generation - LLM (Delegated to Extension)
  //
  // Loading is lifecycle-driven (`loadModelLifecycle(modelId)`); these
  // surfaces only expose state introspection + inference + cancel.
  // ============================================================================

  isModelLoaded: TextGeneration.isModelLoaded,
  unloadModel: TextGeneration.unloadModel,
  // Canonical spec names (§3)
  unloadLLMModel: TextGeneration.unloadModel,
  isLLMModelLoaded: TextGeneration.isModelLoaded,
  chat: TextGeneration.chat,
  generate: TextGeneration.generate,
  generateStream: TextGeneration.generateStream,
  cancelGeneration: TextGeneration.cancelGeneration,
  // Introspection — canonical: `currentLLMModel()` only.
  currentLLMModel: TextGeneration.currentLLMModel,

  // ============================================================================
  // Speech-to-Text (Delegated to Extension)
  // ============================================================================

  isSTTModelLoaded: STT.isSTTModelLoaded,
  unloadSTTModel: STT.unloadSTTModel,
  transcribe: STT.transcribe,
  transcribeSimple: STT.transcribeSimple,
  transcribeBuffer: STT.transcribeBuffer,
  transcribeStream: STT.transcribeStream,
  transcribeFile: STT.transcribeFile,
  // Introspection (matches Swift: currentSTTModel)
  currentSTTModel: STT.currentSTTModel,
  // Live transcription session (matches Swift: startLiveTranscription)
  startLiveTranscription,

  // ============================================================================
  // Text-to-Speech (Delegated to Extension)
  // ============================================================================

  isTTSModelLoaded: TTS.isTTSModelLoaded,
  isTTSVoiceLoaded: TTS.isTTSVoiceLoaded,
  unloadTTSModel: TTS.unloadTTSModel,
  synthesize: TTS.synthesize,
  synthesizeStream: TTS.synthesizeStream,
  synthesizeStreamAsync: TTS.synthesizeStreamAsync,
  speak: TTS.speak,
  isSpeaking: TTS.isSpeaking,
  stopSpeaking: TTS.stopSpeaking,
  availableTTSVoices: TTS.availableTTSVoices,
  stopSynthesis: TTS.stopSynthesis,
  // Introspection (matches Swift: currentTTSModel / currentTTSVoiceId)
  currentTTSModel: TTS.currentTTSModel,

  // ============================================================================
  // Voice Activity Detection (Delegated to Extension)
  // ============================================================================

  isVADModelLoaded: VAD.isVADModelLoaded,
  unloadVADModel: VAD.unloadVADModel,
  detectSpeech: VAD.detectSpeech,
  detectVoiceActivity: VAD.detectVoiceActivity,
  processVAD: VAD.processVAD,
  resetVAD: VAD.resetVAD,
  // VAD activity stream (§6) — proto-byte canonical
  streamVADActivity: VAD.streamVADActivity,
  // VAD statistics (§6)
  getVADStatistics: VAD.getVADStatistics,
  // VAD streaming (§6)
  streamVAD: VAD.streamVAD,

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
  voiceAgentSynthesizeSpeech: VoiceAgent.voiceAgentSynthesizeSpeech,
  // Phase 1 / B4 fix: forwarder for the v3.1 Nitro `getVoiceAgentHandle()`
  // method. The sample VoiceAssistantScreen calls `RunAnywhere.getVoiceAgentHandle()`
  // to feed VoiceAgentStreamAdapter; previously missing from this facade.
  getVoiceAgentHandle: VoiceAgent.getVoiceAgentHandle,
  cleanupVoiceAgent: VoiceAgent.cleanupVoiceAgent,
  // Canonical public streaming surface — callers never need to import the adapter.
  streamVoiceAgent: VoiceAgent.streamVoiceAgent,

  // v3.1: Voice Session methods DELETED. Use VoiceAgentStreamAdapter
  // for streaming; compose STT/LLM/TTS directly for one-shot turns.

  // ============================================================================
  // Structured Output (Delegated to Extension)
  // ============================================================================

  generateStructured: StructuredOutput.generateStructured,
  generateStructuredStream: StructuredOutput.generateStructuredStream,
  // Extract structured data from existing text (§3)
  extractStructuredOutput: StructuredOutput.extractStructuredOutput,
  extractEntities: StructuredOutput.extractEntities,
  classify: StructuredOutput.classify,

  // ============================================================================
  // Tool Calling (Delegated to Extension)
  // ============================================================================

  registerTool: ToolCalling.registerTool,
  unregisterTool: ToolCalling.unregisterTool,
  getRegisteredTools: ToolCalling.getRegisteredTools,
  clearTools: ToolCalling.clearTools,
  executeTool: ToolCalling.executeTool,
  formatToolsForPromptAsync: ToolCalling.formatToolsForPromptAsync,
  generateWithTools: ToolCalling.generateWithTools,
  continueWithToolResult: ToolCalling.continueWithToolResult,

  // ============================================================================
  // Vision Language Model (Delegated to Extension)
  // ============================================================================

  registerVLMBackend: VLM.registerVLMBackend,
  loadVLMModel: VLM.loadVLMModel,
  loadVLMModelById: VLM.loadVLMModelById,
  isVLMModelLoaded: VLM.isVLMModelLoaded,
  unloadVLMModel: VLM.unloadVLMModel,
  describeImage: VLM.describeImage,
  askAboutImage: VLM.askAboutImage,
  processImage: VLM.processImage,
  processImageStream: VLM.processImageStream,
  cancelVLMGeneration: VLM.cancelVLMGeneration,

  // ============================================================================
  // LoRA Adapters — canonical `RunAnywhere.lora.*` namespace
  // Matches Swift: RunAnywhere+LoRA.swift
  // ============================================================================

  lora: LoRACapability,

  // ============================================================================
  // RAG Pipeline (Delegated to Extension)
  // ============================================================================

  ragCreatePipeline: RAG.ragCreatePipeline,
  ragDestroyPipeline: RAG.ragDestroyPipeline,
  ragIngest: RAG.ragIngest,
  ragAddDocumentsBatch: RAG.ragAddDocumentsBatch,
  ragQuery: RAG.ragQuery,
  ragClearDocuments: RAG.ragClearDocuments,
  ragGetDocumentCount: RAG.ragGetDocumentCount,
  ragGetStatistics: RAG.ragGetStatistics,

  // ============================================================================
  // Solutions (T4.7 / T4.8) — proto/YAML-driven L5 pipeline runtime.
  // Capability shape: `RunAnywhere.solutions.run({ config | configBytes | yaml })`
  // returns a `SolutionHandle` with start / stop / cancel / feed / closeInput /
  // destroy verbs. Mirrors the namespace exposed by every other RunAnywhere SDK.
  // ============================================================================

  solutions: SolutionsCapability,

  // ============================================================================
  // Model Management (Delegated to Extension) — Swift parity
  // ============================================================================

  registerModel: ModelManagement.registerModel,
  registerMultiFileModel: ModelManagement.registerMultiFileModel,
  listModels: ModelManagement.listModels,
  queryModels: ModelManagement.queryModels,
  getModel: ModelManagement.getModel,
  downloadedModels: ModelManagement.downloadedModels,
  importModel: ModelManagement.importModel,
  downloadModel: ModelManagement.downloadModel,
  cancelDownload: ModelManagement.cancelDownload,
  deleteModel: ModelManagement.deleteModel,
  loadModel: ModelManagement.loadModel,

  // ============================================================================
  // Hardware namespace (CANONICAL_API §14)
  // ============================================================================

  hardware: HardwareNamespace,

  // ============================================================================
  // Storage Management (Delegated to Extension)
  // ============================================================================

  getStorageInfo: Storage.getStorageInfo,
  getStorageInfoProto: Storage.getStorageInfoProto,
  deleteStorage: Storage.deleteStorage,
  clearCache: Storage.clearCache,
  cleanTempFiles: Storage.cleanTempFiles,

  // ============================================================================
  // Canonical SDK Events / Lifecycle (proto-byte native truth)
  // ============================================================================

  subscribeSDKEvents: SDKEvents.subscribeSDKEvents,
  publishSDKEvent: SDKEvents.publishSDKEvent,
  pollSDKEvent: SDKEvents.pollSDKEvent,
  publishSDKFailure: SDKEvents.publishSDKFailure,
  loadModelLifecycle: Lifecycle.loadModelLifecycle,
  unloadModelLifecycle: Lifecycle.unloadModelLifecycle,
  getCurrentModel: Lifecycle.getCurrentModel,
  getComponentLifecycleSnapshot: Lifecycle.getComponentLifecycleSnapshot,

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
  // VLM Model Overloads (mirrors Swift +VLMModels)
  // ============================================================================

  loadVLMModelByInfo: VLMModels.loadVLMModel,

};

// ============================================================================
// Type Exports
// ============================================================================

export type { ModelInfo } from '@runanywhere/proto-ts/model_types';
export type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
