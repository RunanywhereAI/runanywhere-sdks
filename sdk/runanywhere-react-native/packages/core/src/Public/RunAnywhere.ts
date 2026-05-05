/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * Thin wrapper over native commons.
 * All business logic is in native C++ (runanywhere-commons).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { Platform } from 'react-native';
import { requireNativeModule, isNativeModuleAvailable } from '../native';
import { SDKEnvironment } from '../types';
import { ServiceContainer } from '../Foundation/DependencyInjection/ServiceContainer';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { SDKConstants } from '../Foundation/Constants';
import { SecureStorageService } from '../Foundation/Security/SecureStorageService';
import { TelemetryService } from '../services/Network';
import {
  DEFAULT_BASE_URL,
  hasUsableBackendConfig,
  hasUsableSupabaseConfig,
  isUsableCredential,
} from '../services/Network/NetworkConfiguration';

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
import type { SDKInitOptions } from '../types';
import {
  EventCategory,
  EventDestination,
  EventSeverity,
  InitializationStage,
  SDKComponent,
  SDKEvent as SDKEventCodec,
} from '@runanywhere/proto-ts/sdk_events';

// Import extensions
import * as TextGeneration from './Extensions/RunAnywhere+TextGeneration';
import type { ThinkingExtractionResult } from './Extensions/RunAnywhere+TextGeneration';
import * as STT from './Extensions/RunAnywhere+STT';
import * as TTS from './Extensions/RunAnywhere+TTS';
import * as VAD from './Extensions/RunAnywhere+VAD';
import * as Storage from './Extensions/RunAnywhere+Storage';
import * as SDKEvents from './Extensions/RunAnywhere+Events';
import * as Lifecycle from './Extensions/RunAnywhere+Lifecycle';
import * as Logging from './Extensions/RunAnywhere+Logging';
import * as VoiceAgent from './Extensions/RunAnywhere+VoiceAgent';
// v3.1: RunAnywhere+VoiceSession.ts deleted — use VoiceAgentStreamAdapter.
import * as StructuredOutput from './Extensions/RunAnywhere+StructuredOutput';
import * as Audio from './Extensions/RunAnywhere+Audio';
import * as ToolCalling from './Extensions/RunAnywhere+ToolCalling';
import * as RAG from './Extensions/RunAnywhere+RAG';
import * as VLM from './Extensions/RunAnywhere+VisionLanguage';
import { lora as LoRACapability } from './Extensions/RunAnywhere+LoRA';
import { solutions as SolutionsCapability } from './Extensions/RunAnywhere+Solutions';
import { startLiveTranscription } from './Sessions/LiveTranscriptionSession';
import * as VLMModels from './Extensions/RunAnywhere+VLMModels';
import * as ModelManagement from './Extensions/RunAnywhere+ModelManagement';
import { Hardware as HardwareNamespace } from './Extensions/RunAnywhere+Hardware';

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();
let cachedDeviceId: string = '';

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
        ? EventSeverity.EVENT_SEVERITY_ERROR
        : EventSeverity.EVENT_SEVERITY_INFO,
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

  events: sdkEventSurface,

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
    const environment = options.environment ?? SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
    const effectiveBaseURL = options.baseURL?.trim() || DEFAULT_BASE_URL;
    const effectiveApiKey = isUsableCredential(options.apiKey)
      ? options.apiKey!.trim()
      : '';

    // Fail fast: API key is required for production/staging environments
    // Development mode uses C++ dev config (Supabase credentials) instead
    if (
      environment !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT &&
      !hasUsableBackendConfig({ baseURL: effectiveBaseURL, apiKey: effectiveApiKey })
    ) {
      const envName = environment === SDKEnvironment.SDK_ENVIRONMENT_STAGING ? 'staging' : 'production';
      throw new Error(
        `Usable API key and baseURL are required for ${envName} environment. ` +
        'Pass real apiKey/baseURL values or use SDKEnvironment.Development for local testing.'
      );
    }

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
      // HTTP transport is owned by native C++ (rac_http_client_*). The JS
      // layer only needs to stash the base URL / API key with the native
      // HTTPBridge so downstream native consumers (DeviceBridge, telemetry)
      // resolve the right endpoint.
      const envString = environment === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT ? 'development'
        : environment === SDKEnvironment.SDK_ENVIRONMENT_STAGING ? 'staging'
          : 'production';

      if (environment !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
        await native.configureHttp(
          effectiveBaseURL,
          effectiveApiKey
        );
      }

      if (
        environment === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT &&
        hasUsableSupabaseConfig(options)
      ) {
        logger.debug('Development mode - Supabase config provided');
      }

      // Initialize with config
      // Note: Backend registration (llamacpp, onnx) is done by their respective packages
      // Document paths are owned by the native platform adapter (sandbox layout).
      const configJson = JSON.stringify({
        apiKey: effectiveApiKey,
        baseURL: effectiveBaseURL,
        environment: envString,
        sdkVersion: SDKConstants.version, // Centralized version for C++ layer
        supabaseURL: options.supabaseURL, // For development mode
        supabaseKey: options.supabaseKey, // For development mode
      });

      await native.initialize(configJson);

      // Cache device ID early (uses secure storage / Keychain)
      try {
        cachedDeviceId = await native.getPersistentDeviceUUID();
        logger.debug(`Device ID cached: ${cachedDeviceId.substring(0, 8)}...`);
      } catch (e) {
        logger.warning('Failed to get persistent device UUID');
      }

      // Initialize telemetry with device ID
      TelemetryService.shared.configure(cachedDeviceId, environment);
      TelemetryService.shared.trackSDKInit(envString, true);

      // For production/staging mode, authenticate with backend to get JWT tokens
      // This matches Swift SDK's CppBridge.Auth.authenticate(apiKey:) in setupHTTP()
      if (environment !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT && effectiveApiKey) {
        try {
          logger.info('Authenticating with backend (production/staging mode)...');
          const authenticated = await this._authenticateWithBackend(
            effectiveApiKey,
            effectiveBaseURL,
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

      // Resolve build token: explicit option wins over RUNANYWHERE_BUILD_TOKEN.
      // For production/staging we require a real token (either source). Native
      // C++ has a baked-in dev fallback used only when environment === development,
      // so dev mode may proceed with an undefined token.
      const resolvedBuildToken = this._resolveBuildToken(options.buildToken);
      if (!resolvedBuildToken && environment !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
        const envName = environment === SDKEnvironment.SDK_ENVIRONMENT_STAGING ? 'staging' : 'production';
        throw new Error(
          `Usable build token is required for ${envName} environment. ` +
          'Pass `buildToken` in initialize() options or set the ' +
          '`RUNANYWHERE_BUILD_TOKEN` environment variable at build time.'
        );
      }

      // Trigger device registration (non-blocking, best-effort)
      // This matches Swift SDK's CppBridge.Device.registerIfNeeded(environment:)
      // Uses native C++ → platform HTTP (exactly like Swift)
      this._registerDeviceIfNeeded(environment, options.supabaseKey, resolvedBuildToken).catch(err => {
        logger.warning(`Device registration failed (non-fatal): ${err.message}`);
      });

      ServiceContainer.shared.markInitialized();
      initState = markCoreInitialized(initState, initParams, 'core');
      initState = markServicesInitialized(initState);

      logger.info('SDK initialized successfully');
      publishInitializationEvent(InitializationStage.INITIALIZATION_STAGE_COMPLETED);
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

  /**
   * Authenticate with backend to get JWT access/refresh tokens.
   *
   * Delegates the full round-trip (request build + HTTP transport via
   * rac_http_client_* + AuthBridge state update) to native C++. This
   * mirrors Swift's HTTPClientAdapter and Kotlin's CppBridgeAuth so there
   * is a single HTTP code path across all SDKs.
   * @internal
   */
  async _authenticateWithBackend(
    apiKey: string,
    baseURL: string,
    deviceId: string
  ): Promise<boolean> {
    try {
      const platform = Platform.OS === 'ios' ? 'ios' : 'android';
      const native = requireNativeModule();

      logger.debug(`Auth request to: ${baseURL.replace(/\/$/, '')}/api/v1/auth/sdk/authenticate`);

      const responseJson = await native.authAuthenticate(
        apiKey,
        baseURL,
        deviceId,
        platform,
        SDKConstants.version,
      );

      let authResponse: {
        access_token: string;
        refresh_token: string;
        expires_in: number;
        device_id: string;
        organization_id: string;
        user_id?: string;
        token_type: string;
      };
      try {
        authResponse = JSON.parse(responseJson);
      } catch (parseErr) {
        logger.error(`Auth response parse failed: ${parseErr}`);
        return false;
      }

      try {
        await SecureStorageService.storeAuthTokens(
          authResponse.access_token,
          authResponse.refresh_token,
          authResponse.expires_in,
        );
      } catch (storageErr) {
        logger.warning(`Failed to persist tokens: ${storageErr}`);
      }

      logger.info(`Authentication successful! Token expires in ${authResponse.expires_in}s`);
      return true;
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Authentication error: ${msg}`);
      return false;
    }
  },

  /**
   * Resolve the build token from explicit option or environment variable.
   * Returns `undefined` when no token is available — callers must decide
   * whether that is acceptable (only `SDKEnvironment.Development` is, via the
   * native C++ baked-in dev fallback).
   * @internal
   */
  _resolveBuildToken(explicit?: string): string | undefined {
    if (isUsableCredential(explicit)) return explicit!.trim();
    const fromEnv =
      typeof process !== 'undefined' && process.env
        ? process.env.RUNANYWHERE_BUILD_TOKEN
        : undefined;
    return isUsableCredential(fromEnv) ? fromEnv!.trim() : undefined;
  },

  /**
   * Register device with backend if not already registered.
   * Uses native C++ DeviceBridge + shared rac_http_client_* transport.
   * Exactly matches Swift SDK's CppBridge.Device.registerIfNeeded(environment:)
   * @internal
   */
  async _registerDeviceIfNeeded(
    environment: SDKEnvironment,
    supabaseKey?: string,
    buildToken?: string
  ): Promise<void> {
    const envString = environment === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT ? 'development'
      : environment === SDKEnvironment.SDK_ENVIRONMENT_STAGING ? 'staging'
        : 'production';

    // Defensive: non-dev must have a token (initialize() already enforces this,
    // but guard here too so we never silently register with an empty token).
    if (!buildToken && environment !== SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
      logger.debug('Skipping telemetry/device registration: no usable config');
      return;
    }

    try {
      const native = requireNativeModule();

      // Call native registerDevice which goes through:
      // JS → C++ DeviceBridge → rac_device_manager_register_if_needed
      // → http_post callback → rac_http_client_*.
      // This exactly mirrors Swift's flow!
      // Empty `buildToken` is only emitted in development mode so native can
      // apply its baked-in dev fallback.
      const success = await native.registerDevice(JSON.stringify({
        environment: envString,
        supabaseKey: supabaseKey ?? '',
        buildToken: buildToken ?? '',
      }));

      if (success) {
        logger.debug('Device registration request completed via native');
      } else {
        logger.debug('Skipping telemetry/device registration: no usable config');
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

  /**
   * Whether the SDK is fully active (core initialised AND services ready).
   *
   * Matches Swift: `RunAnywhere.isActive`.
   */
  get isActive(): boolean {
    return initState.isCoreInitialized && initState.hasCompletedServicesInit;
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

    if (!isNativeModuleAvailable()) {
      throw new Error('Native module not available');
    }

    try {
      const native = requireNativeModule();

      // Best-effort device registration retry. Build token resolution is
      // identical to the original `initialize()` path.
      const env = initState.environment ?? SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
      const buildToken = this._resolveBuildToken();
      try {
        await this._registerDeviceIfNeeded(env, undefined, buildToken);
      } catch (e) {
        logger.warning(
          `Device registration retry failed (non-fatal): ${e instanceof Error ? e.message : String(e)}`
        );
      }

      ServiceContainer.shared.markInitialized();
      initState = markServicesInitialized(initState);
      // Touch native to keep the bridge warm; ignore returned bool here.
      void native.isInitialized();
      logger.info('Services initialisation completed.');
      publishInitializationEvent(InitializationStage.INITIALIZATION_STAGE_COMPLETED);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(`Services initialisation failed: ${msg}`);
      publishInitializationEvent(
        InitializationStage.INITIALIZATION_STAGE_FAILED,
        msg
      );
      throw error;
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
   * Get device ID (Keychain-persisted, survives reinstalls).
   *
   * Cached during `initialize()`. Empty string until then.
   */
  get deviceId(): string {
    return cachedDeviceId;
  },

  // ============================================================================
  // Logging (Delegated to Extension)
  // ============================================================================

  setLogLevel: Logging.setLogLevel,

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
  // Thinking token utilities (§3)
  extractThinkingTokens: TextGeneration.extractThinkingTokens,
  stripThinkingTokens: TextGeneration.stripThinkingTokens,
  splitThinkingAndResponse: TextGeneration.splitThinkingAndResponse,

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
  // Model Management (Delegated to Extension) — Swift / Kotlin / Flutter / Web parity
  // ============================================================================

  registerModel: ModelManagement.registerModel,
  registerMultiFileModel: ModelManagement.registerMultiFileModel,
  getAvailableModels: ModelManagement.getAvailableModels,
  getDownloadedModels: ModelManagement.getDownloadedModels,
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
  checkStorageAvailability: Storage.checkStorageAvailability,
  planStorageDelete: Storage.planStorageDelete,
  deleteStorage: Storage.deleteStorage,
  clearCache: Storage.clearCache,

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
  // VLM Model Overloads (mirrors Swift +VLMModels)
  // ============================================================================

  loadVLMModelByInfo: VLMModels.loadVLMModel,

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

export type { ModelInfo } from '@runanywhere/proto-ts/model_types';
export type { DownloadProgress } from '@runanywhere/proto-ts/download_service';
