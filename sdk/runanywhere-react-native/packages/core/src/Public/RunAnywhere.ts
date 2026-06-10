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
import {
  SdkInitEnvironment,
  SdkInitPhase1Request,
  SdkInitPhase2Request,
  SdkInitResult,
} from '@runanywhere/proto-ts/sdk_init';
import type {
  SdkInitPhase1Request as SdkInitPhase1RequestMessage,
  SdkInitPhase2Request as SdkInitPhase2RequestMessage,
} from '@runanywhere/proto-ts/sdk_init';

import type { InitializationState } from '../Foundation/Initialization';
import {
  createInitialState,
  markCoreInitialized,
  markServicesInitializing,
  markServicesInitialized,
  markHTTPSetupResult,
  markInitializationFailed,
  resetState,
} from '../Foundation/Initialization/InitializationState';
import { registerServicesReadyGuard } from '../Foundation/Initialization/ServicesReadyGuard';
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
import { embeddings as EmbeddingsCapability } from './Extensions/Embeddings/RunAnywhere+Embeddings';
import { AudioConvert } from './Extensions/Audio/RunAnywhere+AudioConvert';
import * as ModelManagement from './Extensions/Models/RunAnywhere+ModelRegistry';
import { formatFramework } from './Helpers/formatFramework';
import { EventBus } from './Events/EventBus';
import { SDKException } from '../Foundation/Errors/SDKException';

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();
let servicesInitPromise: Promise<void> | null = null;
// In-flight Phase 1 promise shared across concurrent initialize() callers.
// Mirrors Swift's `guard !isInitializedFlag else { return }` + Kotlin's `synchronized` guard.
let initializingPromise: Promise<void> | null = null;

type NativePhase2Module = {
  completeServicesInitialization?: () => Promise<unknown>;
};

/**
 * Decode the serialized `RASdkInitResult` returned by the native phase-2 /
 * HTTP-retry bridge. Mirrors Swift, which reads `hasCompletedHttpSetup ||
 * httpConfigured` and `httpApplicable` from the same proto.
 *
 * Returns `null` for the offline/deferred outcomes: an empty buffer (the
 * packaged commons lacks the symbol) or an unrecognized payload. A literal
 * `true` from a stale packaged native still resolving the legacy boolean is
 * preserved as fully-configured.
 */
function decodeSdkInitResultPayload(
  payload: unknown
): { httpConfigured: boolean; httpApplicable: boolean } | null {
  if (payload instanceof ArrayBuffer) {
    if (payload.byteLength === 0) {
      return null;
    }
    const decoded = SdkInitResult.decode(new Uint8Array(payload));
    return {
      httpConfigured: decoded.hasCompletedHttpSetup || decoded.httpConfigured,
      httpApplicable: decoded.httpApplicable,
    };
  }
  if (payload === true) {
    return { httpConfigured: true, httpApplicable: true };
  }
  return null;
}

function mapSdkInitEnvironment(environment: SDKEnvironment): SdkInitEnvironment {
  switch (environment) {
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_STAGING;
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_PRODUCTION;
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
    case SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED:
    default:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT;
  }
}

function environmentToConfigString(environment: SDKEnvironment): string {
  switch (environment) {
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return 'staging';
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return 'production';
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
    case SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED:
    default:
      return 'development';
  }
}

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
    // Idempotency guard — mirrors Swift `guard !isInitializedFlag else { return }`.
    if (initState.isCoreInitialized) return;
    // Re-entrancy guard — concurrent callers share the in-flight Phase 1 promise
    // instead of racing through init and double-emitting lifecycle events.
    if (initializingPromise) return initializingPromise;

    initializingPromise = (async () => {
      try {
        const environment = options.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
        const effectiveBaseURL = options.baseURL?.trim() || DEFAULT_BASE_URL;
        const effectiveApiKey = isUsableCredential(options.apiKey)
          ? options.apiKey!.trim()
          : '';
        const phase1Request: SdkInitPhase1RequestMessage = SdkInitPhase1Request.create();
        phase1Request.environment = mapSdkInitEnvironment(environment);
        phase1Request.apiKey = effectiveApiKey;
        phase1Request.baseUrl = effectiveBaseURL;
        phase1Request.deviceId = '';
        phase1Request.platform = SDKConstants.platform;
        phase1Request.sdkVersion = SDKConstants.version;

        const phase2Request: SdkInitPhase2RequestMessage = SdkInitPhase2Request.create();
        phase2Request.buildToken = options.buildToken?.trim() ?? '';
        phase2Request.forceRefreshAssignments = options.forceRefreshAssignments ?? false;
        phase2Request.flushTelemetry = options.flushTelemetry ?? true;
        phase2Request.discoverDownloadedModels = options.discoverDownloadedModels ?? true;
        phase2Request.rescanLocalModels = options.rescanLocalModels ?? true;

        const initParams: SDKInitOptions = {
          apiKey: phase1Request.apiKey,
          baseURL: phase1Request.baseUrl,
          environment,
          buildToken: phase2Request.buildToken,
          forceRefreshAssignments: phase2Request.forceRefreshAssignments,
          flushTelemetry: phase2Request.flushTelemetry,
          discoverDownloadedModels: phase2Request.discoverDownloadedModels,
          rescanLocalModels: phase2Request.rescanLocalModels,
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
          const nativeUnavailableError = SDKException.nativeModuleUnavailable();
          initState = markInitializationFailed(initState, nativeUnavailableError);
          throw nativeUnavailableError;
        }

        const native = requireNativeModule();

        try {
          // RN still crosses an async native bridge for Phase 1. The generated
          // proto request objects are the call-site envelope; native fills the
          // platform-owned device id before invoking the commons proto ABI.
          const configJson = JSON.stringify({
            apiKey: phase1Request.apiKey,
            baseURL: phase1Request.baseUrl,
            environment: environmentToConfigString(environment),
            platform: phase1Request.platform,
            sdkVersion: phase1Request.sdkVersion,
            buildToken: phase2Request.buildToken,
            forceRefreshAssignments: phase2Request.forceRefreshAssignments,
            flushTelemetry: phase2Request.flushTelemetry,
            discoverDownloadedModels: phase2Request.discoverDownloadedModels,
            rescanLocalModels: phase2Request.rescanLocalModels,
          });

          const initialized = await native.initialize(configJson);
          if (initialized === false) {
            throw SDKException.notInitialized('Native SDK initialization failed');
          }

          initState = markCoreInitialized(initState, initParams, 'core');

          logger.info('SDK initialized successfully');
          publishInitializationEvent(InitializationStage.INITIALIZATION_STAGE_COMPLETED);

          // completeServicesInitialization() manages servicesInitPromise internally.
          // Do NOT wipe it here — an unconditional null would destroy any in-flight
          // Phase 2 promise from a concurrent ensureServicesReady caller.
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
      } finally {
        initializingPromise = null;
      }
    })();

    return initializingPromise;
  },

  async reset(): Promise<void> {
    // Clear local state BEFORE destroying native — mirrors Swift's order:
    // clear flags first, then `await CppBridge.shutdown()`. This ensures any
    // in-flight Phase 2 awaiter sees the reset state rather than hitting a
    // dead bridge (RAC_ERROR_NOT_INITIALIZED).
    initState = resetState();
    servicesInitPromise = null;
    initializingPromise = null;
    if (isNativeModuleAvailable()) {
      const native = requireNativeModule();
      await native.destroy();
    }
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
      throw SDKException.notInitialized(
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
      throw SDKException.nativeModuleUnavailable();
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
          throw SDKException.notInitialized('Native core is not initialized');
        }
        logger.debug('Native phase 2 bridge not available; core native init is already complete.');
      }
      const decoded = decodeSdkInitResultPayload(phase2Result);
      const httpConfigured = decoded?.httpConfigured ?? false;
      const httpApplicable = decoded?.httpApplicable ?? true;

      initState = markServicesInitialized(initState, httpConfigured, httpApplicable);
      if (httpConfigured) {
        logger.info('Services initialisation completed.');
      } else if (!httpApplicable) {
        logger.info('Services initialisation completed (HTTP setup not applicable for this configuration).');
      } else {
        logger.info('Services initialisation completed (HTTP/auth deferred — will retry on next online call).');
      }
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
   * `Promise<string | null>` instead of `String?` because the user-id read
   * crosses the Nitro JS<->C++ bridge; resolves to `null` when there is
   * no authenticated user, preserving the 3-state contract (authenticated /
   * unauthenticated / unknown).
   *
   * @returns User ID if authenticated, null otherwise
   */
  async getUserId(): Promise<string | null> {
    if (!isNativeModuleAvailable()) return null;
    const native = requireNativeModule();
    const userId = await native.getUserId();
    return userId != null && userId !== '' ? userId : null;
  },

  /**
   * Get current organization ID from authentication.
   *
   * Matches Swift `RunAnywhere.getOrganizationId() -> String?`. RN
   * returns `Promise<string | null>` (rather than `String?`) because the read
   * crosses the Nitro JS<->C++ bridge; resolves to `null` when there is
   * no authenticated org.
   *
   * @returns Organization ID if authenticated, null otherwise
   */
  async getOrganizationId(): Promise<string | null> {
    if (!isNativeModuleAvailable()) return null;
    const native = requireNativeModule();
    const orgId = await native.getOrganizationId();
    return orgId != null && orgId !== '' ? orgId : null;
  },

  /**
   * Check if currently authenticated.
   *
   * Matches Swift `RunAnywhere.isAuthenticated: Bool` (sync property).
   * On RN this is a method returning `Promise<boolean>` because authentication
   * state lives in native C++ behind the Nitro async bridge; JS cannot read it
   * synchronously. Using a method (not a getter-returning-Promise) avoids the
   * property-returning-Promise antipattern.
   */
  async isAuthenticated(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
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
  aggregateStream: TextGeneration.aggregateStream,
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
  defaultVoiceAgentComposeConfig: VoiceAgent.defaultVoiceAgentComposeConfig,
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
  ragDocumentCount: RAG.ragDocumentCount,
  ragGetStatistics: RAG.ragGetStatistics,
  ragResolvedConfiguration: RAG.ragResolvedConfiguration,

  // ============================================================================
  // Solutions (T4.7 / T4.8) — proto/YAML-driven L5 pipeline runtime.
  // Capability shape: `RunAnywhere.solutions.run({ config | configBytes | yaml })`
  // returns a `SolutionHandle` with start / stop / cancel / feed / closeInput /
  // destroy verbs. Mirrors the namespace exposed by every other RunAnywhere SDK.
  // ============================================================================

  solutions: SolutionsCapability,

  // ============================================================================
  // Embeddings — canonical `RunAnywhere.embeddings.*` namespace
  // Matches Swift: RunAnywhere+Embeddings.swift
  // ============================================================================

  embeddings: EmbeddingsCapability,

  // ============================================================================
  // Audio conversion helpers (PCM16 → Float32 / WAV)
  // Matches Swift: RAAudioConvert.swift
  // ============================================================================

  pcm16ToFloat32: AudioConvert.pcm16ToFloat32,
  pcm16ToFloat32Samples: AudioConvert.pcm16ToFloat32Samples,
  pcm16ToWav: AudioConvert.pcm16ToWav,

  // ============================================================================
  // Model Management (Delegated to Extension) — Swift parity
  // ============================================================================

  registerModel: ModelManagement.registerModel,
  registerModelFromUrl: ModelManagement.registerModelFromUrl,
  registerMultiFileModel: ModelManagement.registerMultiFileModel,
  registerArchiveModel: ModelManagement.registerArchiveModel,
  listModels: ModelManagement.listModels,
  queryModels: ModelManagement.queryModels,
  getModel: ModelManagement.getModel,
  downloadedModels: ModelManagement.downloadedModels,
  importModel: ModelManagement.importModel,
  downloadModel: ModelManagement.downloadModel,
  downloadModelStream: ModelManagement.downloadModelStream,
  refreshModelRegistry: ModelManagement.refreshModelRegistry,
  getDefaultFramework: ModelManagement.getDefaultFramework,

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

// ============================================================================
// Internal Phase-2 guard — mirrors Swift RunAnywhere.ensureServicesReady() and
// Kotlin RunAnywhere.ensureServicesReady(). Three branches:
//   1. Fast path: services + HTTP both done → return immediately (O(1)).
//   2. Recovery path: services done, HTTP failed (offline init) → retry HTTP
//      without re-running Phase 2. Keeps local-model inference alive after an
//      offline boot while re-authenticating transparently once online.
//   3. Cold-start path: Phase 2 not yet run → completeServicesInitialization().
// ============================================================================

async function retryHTTPSetupInternal(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    return;
  }
  const native = requireNativeModule();
  logger.debug('Retrying HTTP/auth setup...');
  try {
    const retryResult: unknown = await native.retryHTTPSetupProto();
    const decoded = decodeSdkInitResultPayload(retryResult);
    if (decoded) {
      initState = markHTTPSetupResult(
        initState,
        decoded.httpConfigured,
        decoded.httpApplicable
      );
      if (decoded.httpConfigured) {
        logger.info('HTTP/Auth setup succeeded on retry.');
      } else if (!decoded.httpApplicable) {
        logger.info('HTTP setup not applicable for this configuration; retries stopped.');
      }
      return;
    }
    logger.debug('HTTP/Auth retry did not complete; commons reported deferred setup.');
  } catch (error) {
    logger.debug(
      `HTTP/Auth retry failed (still offline?): ${
        error instanceof Error ? error.message : String(error)
      }`
    );
  }
}

async function ensureServicesReadyInternal(): Promise<void> {
  const services = initState.hasCompletedServicesInit;
  const http = initState.hasCompletedHTTPSetup;
  const applicable = initState.httpSetupApplicable;
  if (services && (http || !applicable)) {
    return;
  }
  if (services && !http && applicable) {
    await retryHTTPSetupInternal();
    return;
  }
  await RunAnywhere.completeServicesInitialization();
}

// Register the Phase-2 guard so extension files can call ensureServicesReady()
// without importing RunAnywhere directly (avoids circular imports).
registerServicesReadyGuard(ensureServicesReadyInternal);
