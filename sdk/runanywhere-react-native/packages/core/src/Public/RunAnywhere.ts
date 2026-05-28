/**
 * RunAnywhere React Native SDK - Main Entry Point
 *
 * Thin wrapper over native commons.
 * All business logic is in native C++ (runanywhere-commons).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../native';
import { initializeNitroModulesGlobally } from '../native/NitroModulesGlobalInit';
import { ensureProtoTextEncoding } from '../services/ProtoWire';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';
import { SDKConstants } from '../Foundation/Constants/SDKConstants';
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
import type { SDKInitOptions } from '../types/models';
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
import * as SDKEvents from './Extensions/Events/RunAnywhere+SDKEvents';
import * as Lifecycle from './Extensions/Models/RunAnywhere+ModelLifecycle';
import * as Logging from './Extensions/RunAnywhere+Logging';
import { pluginLoader as PluginLoaderCapability } from './Extensions/RunAnywhere+PluginLoader';
import * as VoiceAgent from './Extensions/VoiceAgent/RunAnywhere+VoiceAgent';
import * as StructuredOutput from './Extensions/LLM/RunAnywhere+StructuredOutput';
import * as ToolCalling from './Extensions/LLM/RunAnywhere+ToolCalling';
import * as RAG from './Extensions/RAG/RunAnywhere+RAG';
import * as VLM from './Extensions/VLM/RunAnywhere+VisionLanguage';
import { lora as LoRACapability } from './Extensions/LLM/RunAnywhere+LoRA';
import { solutions as SolutionsCapability } from './Extensions/Solutions/RunAnywhere+Solutions';
import * as ModelManagement from './Extensions/Models/RunAnywhere+ModelRegistry';
import { Hardware as HardwareNamespace } from './Extensions/RunAnywhere+Hardware';
import { formatFramework } from './Helpers/formatFramework';
import { EventBus } from './Events/EventBus';

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();
let servicesInitPromise: Promise<void> | null = null;

type NativePhase2Module = {
  completeServicesInitialization?: () => Promise<unknown>;
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

  events: EventBus.shared,

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
    ensureProtoTextEncoding();

    try {
      await initializeNitroModulesGlobally();
    } catch (error) {
      logger.warning('NitroModules global initialization failed', { error });
    }

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

  async reset(): Promise<void> {
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      await native.destroy();
    }
    initState = resetState();
    servicesInitPromise = null;
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
  //
  // Platform shape (RN vs Swift):
  //   These getters are async on React Native because every call has to
  //   cross the JS<->native bridge. Nitro Modules' proto-bytes methods
  //   (`getUserId`, `getOrganizationId`, `isAuthenticated`,
  //   `isDeviceRegistered`, `getDeviceId`, `getPersistentDeviceUUID`)
  //   return `Promise<...>`; JS cannot observe the resolved C++ state
  //   synchronously the way Swift can read `CppBridge.State.userId` /
  //   `CppBridge.Auth.isAuthenticated` directly. The Swift surface
  //   exposes these as plain `String?` / `Bool` properties because the
  //   bridge is in-process and lock-free on read; the RN bridge is
  //   asynchronous by construction. The semantics (when the value
  //   becomes non-empty / true, what falsy means) match exactly — only
  //   the call shape differs.
  //
  // Swift reference:
  //   sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift:66,82-91
  // ============================================================================

  /**
   * Get current user ID from authentication.
   *
   * Matches Swift `RunAnywhere.getUserId() -> String?`. RN returns
   * `Promise<string>` instead of `String?` because the user-id read
   * crosses the Nitro JS<->C++ bridge; resolves to `''` when there is
   * no authenticated user.
   *
   * @returns User ID if authenticated, empty string otherwise
   */
  async getUserId(): Promise<string> {
    if (!isNativeModuleAvailable()) return '';
    const native = requireNativeModule();
    const userId = await native.getUserId();
    return userId ?? '';
  },

  /**
   * Get current organization ID from authentication.
   *
   * Matches Swift `RunAnywhere.getOrganizationId() -> String?`. RN
   * returns `Promise<string>` (rather than `String?`) because the read
   * crosses the Nitro JS<->C++ bridge; resolves to `''` when there is
   * no authenticated org.
   *
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
   * Matches Swift `RunAnywhere.isAuthenticated: Bool` (sync property).
   * On RN this is `Promise<boolean>` because authentication state lives
   * in native C++ behind the Nitro async bridge; JS cannot read it
   * synchronously.
   */
  get isAuthenticated(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return Promise.resolve(false);
    const native = requireNativeModule();
    return native.isAuthenticated();
  },

  /**
   * Check if device is registered with backend.
   *
   * Matches Swift `RunAnywhere.isDeviceRegistered() -> Bool` (sync).
   * RN returns `Promise<boolean>` because device-registration state is
   * read across the Nitro async bridge.
   */
  async isDeviceRegistered(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const native = requireNativeModule();
    return native.isDeviceRegistered();
  },

  /**
   * Get device ID from native device state.
   *
   * Matches Swift `RunAnywhere.deviceId: String` (sync property). RN
   * returns `Promise<string>` because the value lives in
   * Keychain/Keystore behind the Nitro async bridge; falls back to the
   * persistent device UUID and finally `''` if neither is resolvable.
   */
  async getDeviceId(): Promise<string> {
    if (!isNativeModuleAvailable()) return '';
    const native = requireNativeModule();
    return (await native.getDeviceId()) || (await native.getPersistentDeviceUUID()) || '';
  },

  /**
   * Device ID (Keychain/Keystore-persisted, survives reinstalls).
   *
   * RN-only property accessor — matches Swift's sync
   * `RunAnywhere.deviceId: String` in semantics, but returns
   * `Promise<string>` because RN resolves this through the Nitro async
   * native bridge. Identical to calling `getDeviceId()`.
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
  // Text Generation - LLM (Swift-shaped public extension)
  // ============================================================================

  generate: TextGeneration.generate,
  generateStream: TextGeneration.generateStream,
  cancelGeneration: TextGeneration.cancelGeneration,

  // ============================================================================
  // Speech-to-Text (Swift-shaped public extension)
  // ============================================================================

  transcribe: STT.transcribe,
  transcribeStream: STT.transcribeStream,

  // ============================================================================
  // Text-to-Speech (Swift-shaped public extension)
  // ============================================================================

  synthesize: TTS.synthesize,
  synthesizeStream: TTS.synthesizeStream,
  stopSynthesis: TTS.stopSynthesis,
  speak: TTS.speak,
  stopSpeaking: TTS.stopSpeaking,

  // ============================================================================
  // Voice Activity Detection (Swift-shaped public extension)
  // ============================================================================

  detectVoiceActivity: VAD.detectVoiceActivity,
  streamVAD: VAD.streamVAD,
  resetVAD: VAD.resetVAD,

  // ============================================================================
  // Voice Agent (Swift-shaped public extension)
  // ============================================================================

  initializeVoiceAgent: VoiceAgent.initializeVoiceAgent,
  initializeVoiceAgentWithLoadedModels: VoiceAgent.initializeVoiceAgentWithLoadedModels,
  defaultVADModelID: VoiceAgent.defaultVADModelID,
  ensureDefaultVAD: VoiceAgent.ensureDefaultVAD,
  getVoiceAgentComponentStates: VoiceAgent.getVoiceAgentComponentStates,
  processVoiceTurn: VoiceAgent.processVoiceTurn,
  streamVoiceAgent: VoiceAgent.streamVoiceAgent,
  cleanupVoiceAgent: VoiceAgent.cleanupVoiceAgent,

  // ============================================================================
  // Structured Output (Swift-shaped public extension)
  // ============================================================================

  generateStructured: StructuredOutput.generateStructured,
  generateStructuredStream: StructuredOutput.generateStructuredStream,
  generateWithStructuredOutput: StructuredOutput.generateWithStructuredOutput,
  extractStructuredOutput: StructuredOutput.extractStructuredOutput,

  // ============================================================================
  // Tool Calling (Swift-shaped public extension)
  // ============================================================================

  registerTool: ToolCalling.registerTool,
  unregisterTool: ToolCalling.unregisterTool,
  getRegisteredTools: ToolCalling.getRegisteredTools,
  clearTools: ToolCalling.clearTools,
  executeTool: ToolCalling.executeTool,
  generateWithTools: ToolCalling.generateWithTools,

  // ============================================================================
  // Vision Language Model (Swift-shaped public extension)
  // ============================================================================

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

  // ============================================================================
  // Hardware namespace (CANONICAL_API §14)
  // ============================================================================

  hardware: HardwareNamespace,

  // ============================================================================
  // Display helpers (proxies for commons C ABI tables)
  // ============================================================================

  formatFramework,

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
  loadModel: Lifecycle.loadModel,
  unloadModel: Lifecycle.unloadModel,
  currentModel: Lifecycle.currentModel,
  modelInfoForCategory: Lifecycle.modelInfoForCategory,
  componentLifecycleSnapshot: Lifecycle.componentLifecycleSnapshot,

};
