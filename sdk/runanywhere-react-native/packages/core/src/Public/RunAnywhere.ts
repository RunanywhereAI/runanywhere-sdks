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
  isUsableHTTPURL,
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
import { registerInitializedProvider } from '../Foundation/Initialization/InitializedGuard';
import type { SDKInitOptions } from '../types/models';

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
import {
  asSDKException,
  sdkExceptionFromRcResult,
  SDKException,
} from '../Foundation/Errors/SDKException';

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal State
// ============================================================================

let initState: InitializationState = createInitialState();
let servicesInitPromise: Promise<void> | null = null;
// In-flight Phase 1 promise shared across concurrent initialize() callers.
// Mirrors Swift's `guard !isInitializedFlag else { return }` + Kotlin's `synchronized` guard.
let initializingPromise: Promise<void> | null = null;
// In-flight offline HTTP recovery. Reset joins this before native teardown so
// retry cannot race credential/config release or rewrite a newer lifetime.
let httpRetryPromise: Promise<void> | null = null;
// Reset is a process-wide lifetime barrier: concurrent resets join it and new
// initialization/services work waits until native destroy completes.
let resetPromise: Promise<void> | null = null;
let lifecycleGeneration = 0;
// A failed native destroy leaves ownership uncertain. Keep the facade closed
// until a later reset successfully completes teardown.
let resetRequired = false;

function requireCurrentLifecycle(
  generation: number,
  operation: string
): void {
  if (generation !== lifecycleGeneration) {
    throw SDKException.notInitialized(`SDK lifetime ended during ${operation}`);
  }
}

async function awaitSettlement(promise: Promise<unknown> | null): Promise<void> {
  if (!promise) return;
  try {
    await promise;
  } catch {
    // The originating caller owns the error; reset still must destroy any
    // partially initialized native lifetime.
  }
}

/**
 * Decode the serialized `RASdkInitResult` returned by the native phase-2 /
 * HTTP-retry bridge. Mirrors Swift, which reads `hasCompletedHttpSetup ||
 * httpConfigured` and `httpApplicable` from the same proto.
 *
 */
function decodeSdkInitResultPayload(payload: ArrayBuffer): {
  httpConfigured: boolean;
  httpApplicable: boolean;
} {
  if (payload.byteLength === 0) {
    throw SDKException.protoDecodeFailed('sdkInitResult');
  }
  const decoded = SdkInitResult.decode(new Uint8Array(payload));
  return {
    httpConfigured: decoded.hasCompletedHttpSetup || decoded.httpConfigured,
    httpApplicable: decoded.httpApplicable,
  };
}

const nativeRacResultPattern = /(?:^|\s)RAC_RESULT=(-?\d+)(?:\s|$)/;

/** Convert a native bridge failure carrying RAC_RESULT into the canonical proto error. */
async function asNativeSDKException(error: unknown): Promise<SDKException> {
  if (error instanceof Error) {
    const match = nativeRacResultPattern.exec(error.message);
    if (match?.[1]) {
      const rc = Number.parseInt(match[1], 10);
      const mapped = await sdkExceptionFromRcResult(rc);
      if (mapped) return mapped;
    }
  }
  return asSDKException(error);
}

function mapSdkInitEnvironment(
  environment: SDKEnvironment
): SdkInitEnvironment {
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

// Lifecycle INITIALIZATION_STAGE_* events are published once by commons
// (rac_sdk_init_phase1_proto); RN no longer hand-emits duplicates.

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
    const activeReset = resetPromise;
    if (activeReset) await activeReset;
    if (resetRequired) {
      throw SDKException.notInitialized(
        'Previous SDK teardown did not complete; call reset() again'
      );
    }

    // Idempotency guard — mirrors Swift `guard !isInitializedFlag else { return }`.
    if (initState.isCoreInitialized) return;
    // Re-entrancy guard — concurrent callers share the in-flight Phase 1 promise
    // instead of racing through init and double-emitting lifecycle events.
    if (initializingPromise) return initializingPromise;

    const generation = lifecycleGeneration;

    initializingPromise = (async () => {
      try {
        const environment =
          options.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
        const effectiveBaseURL = options.baseURL?.trim() || DEFAULT_BASE_URL;
        const effectiveApiKey = isUsableCredential(options.apiKey)
          ? options.apiKey!.trim()
          : '';
        const requiresCredentials =
          environment === SDKEnvironment.SDK_ENVIRONMENT_STAGING ||
          environment === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
        if (
          !isUsableHTTPURL(effectiveBaseURL, {
            requireHTTPS:
              environment === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
          })
        ) {
          throw SDKException.validationFailed({
            fieldPath: 'SDKInitOptions.baseURL',
            message:
              environment === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
                ? 'baseURL must be an absolute HTTPS URL without embedded credentials, query, or fragment'
                : 'baseURL must be an absolute HTTP(S) URL without embedded credentials, query, or fragment',
          });
        }
        if (requiresCredentials && !effectiveApiKey) {
          throw SDKException.validationFailed({
            fieldPath: 'SDKInitOptions.apiKey',
            message:
              'apiKey must be non-empty and must not be a placeholder outside development',
          });
        }
        const phase1Request: SdkInitPhase1RequestMessage =
          SdkInitPhase1Request.create();
        phase1Request.environment = mapSdkInitEnvironment(environment);
        phase1Request.apiKey = effectiveApiKey;
        phase1Request.baseUrl = effectiveBaseURL;
        phase1Request.deviceId = '';
        phase1Request.platform = SDKConstants.platform;
        phase1Request.sdkVersion = SDKConstants.version;

        const phase2Request: SdkInitPhase2RequestMessage =
          SdkInitPhase2Request.create();
        phase2Request.buildToken = options.buildToken?.trim() ?? '';
        phase2Request.forceRefreshAssignments =
          options.forceRefreshAssignments ?? false;
        phase2Request.flushTelemetry = options.flushTelemetry ?? true;
        phase2Request.discoverDownloadedModels =
          options.discoverDownloadedModels ?? true;
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

        logger.info('SDK initialization starting...');
        ensureProtoTextEncoding();

        try {
          await initializeNitroModulesGlobally();
        } catch (error) {
          logger.warning('NitroModules global initialization failed', {
            error,
          });
        }

        requireCurrentLifecycle(generation, 'initialization');

        if (!isNativeModuleAvailable()) {
          logger.warning('Native module not available');
          const nativeUnavailableError = SDKException.nativeModuleUnavailable();
          initState = markInitializationFailed(
            initState,
            nativeUnavailableError
          );
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
            throw SDKException.notInitialized(
              'Native SDK initialization failed'
            );
          }

          requireCurrentLifecycle(generation, 'initialization');
          initState = markCoreInitialized(initState, initParams);

          logger.info('SDK initialized successfully');

          // completeServicesInitialization() manages servicesInitPromise internally.
          // Do NOT wipe it here — an unconditional null would destroy any in-flight
          // Phase 2 promise from a concurrent ensureServicesReady caller.
          void this.completeServicesInitialization().catch((err) => {
            if (generation !== lifecycleGeneration) return;
            logger.warning(
              `Phase 2 services initialization failed (non-fatal): ${
                err instanceof Error ? err.message : String(err)
              }`
            );
          });
        } catch (error) {
          const sdkError = await asNativeSDKException(error);
          if (generation === lifecycleGeneration) {
            // Initialization failures can originate in auth/config transports.
            // Log only structured non-secret identifiers; the full exception is
            // returned to the caller and must not be copied into device logs.
            logger.error('SDK initialization failed', {
              errorCode: sdkError.code,
              errorCategory: sdkError.category,
            });
            initState = markInitializationFailed(initState, sdkError);
          }
          throw sdkError;
        }
      } finally {
        initializingPromise = null;
      }
    })();

    return initializingPromise;
  },

  reset(): Promise<void> {
    if (resetPromise) return resetPromise;

    const pendingInitialization = initializingPromise;
    const pendingServicesInitialization = servicesInitPromise;
    const pendingHTTPRetry = httpRetryPromise;
    lifecycleGeneration += 1;
    resetRequired = true;
    // Close the facade synchronously. Generation guards prevent Phase 1,
    // Phase 2, and HTTP recovery from reopening this lifetime while their
    // native work settles.
    initState = resetState();

    const operation = (async () => {
      // Never destroy native state underneath Phase 1/2. Both operations are
      // invalidated by the generation bump above, so their late completions
      // cannot reopen the facade while reset waits for them to settle.
      await awaitSettlement(pendingInitialization);
      await awaitSettlement(pendingServicesInitialization);
      await awaitSettlement(pendingHTTPRetry);

      initializingPromise = null;
      servicesInitPromise = null;
      httpRetryPromise = null;

      if (isNativeModuleAvailable()) {
        const native = requireNativeModule();
        await native.destroy();
      }
      resetRequired = false;
    })();

    resetPromise = operation;
    void operation.then(
      () => {
        if (resetPromise === operation) resetPromise = null;
      },
      () => {
        if (resetPromise === operation) resetPromise = null;
      }
    );
    return operation;
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
    const activeReset = resetPromise;
    if (activeReset) await activeReset;

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

    const generation = lifecycleGeneration;
    const operation = (async () => {
      const native = requireNativeModule();

      requireCurrentLifecycle(generation, 'services initialization');
      initState = markServicesInitializing(initState);

      const phase2Result = await native.completeServicesInitialization();
      const decoded = decodeSdkInitResultPayload(phase2Result);
      const { httpConfigured, httpApplicable } = decoded;

      requireCurrentLifecycle(generation, 'services initialization');
      initState = markServicesInitialized(
        initState,
        httpConfigured,
        httpApplicable
      );
      if (httpConfigured) {
        logger.info('Services initialisation completed.');
      } else if (!httpApplicable) {
        logger.info(
          'Services initialisation completed (HTTP setup not applicable for this configuration).'
        );
      } else {
        logger.info(
          'Services initialisation completed (HTTP/auth deferred — will retry on next online call).'
        );
      }
    })();
    servicesInitPromise = operation;

    try {
      await operation;
    } catch (error) {
      const sdkError = await asNativeSDKException(error);
      if (generation === lifecycleGeneration) {
        logger.error('Services initialisation failed', {
          errorCode: sdkError.code,
          errorCategory: sdkError.category,
        });
      }
      throw sdkError;
    } finally {
      if (servicesInitPromise === operation) {
        servicesInitPromise = null;
      }
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
   * Supply a Hugging Face bearer token so the SDK can download **private**
   * model repos (e.g. gated `runanywhere/<name>_HNPU` NPU bundles). Auth
   * lives in the C++ commons layer, which attaches it ONLY to https
   * `huggingface.co`/`hf.co` requests — downloads, HEAD size preflight,
   * resumable transfers, and HF repo registration — on every platform
   * uniformly. Kotlin parity: `RunAnywhere.setHfToken`.
   *
   * Pass an empty string to clear the token and restore the public no-auth
   * behavior (also disables the `HF_TOKEN` env fallback).
   */
  async setHfToken(token: string): Promise<void> {
    if (!isNativeModuleAvailable()) return;
    const native = requireNativeModule();
    await native.setHfToken(token);
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
   * Matches Swift's throwing `RunAnywhere.deviceId` property. RN returns a
   * Promise because the value lives behind the Nitro async bridge and rejects
   * if native identity cannot be resolved durably.
   */
  async getDeviceId(): Promise<string> {
    if (!isNativeModuleAvailable()) {
      throw SDKException.nativeModuleUnavailable();
    }
    const native = requireNativeModule();
    try {
      const registeredDeviceId = await native.getDeviceId();
      if (registeredDeviceId) return registeredDeviceId;

      const persistentDeviceId = await native.getPersistentDeviceUUID();
      if (!persistentDeviceId) {
        throw SDKException.notInitialized('Persistent device identity');
      }
      return persistentDeviceId;
    } catch (error) {
      throw await asNativeSDKException(error);
    }
  },

  /**
   * Device ID persisted in platform secure storage for the app installation.
   *
   * RN-only property accessor — matches Swift's throwing device-ID getter,
   * but returns `Promise<string>` through the Nitro async native bridge.
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
  initializeVoiceAgentWithLoadedModels:
    VoiceAgent.initializeVoiceAgentWithLoadedModels,
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
  inferModelFileRole: ModelManagement.inferModelFileRole,

  // ============================================================================
  // Display helpers (proxies for commons C ABI tables)
  // ============================================================================

  formatFramework,

  // ============================================================================
  // Storage Management (Delegated to Extension)
  // ============================================================================

  getStorageInfo: Storage.getStorageInfo,
  deleteStorage: Storage.deleteStorage,
  deleteModel: Storage.deleteModel,
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
  const activeReset = resetPromise;
  if (activeReset) await activeReset;
  if (resetRequired) {
    throw SDKException.notInitialized(
      'Previous SDK teardown did not complete; call reset() again'
    );
  }
  if (httpRetryPromise) return httpRetryPromise;
  if (!isNativeModuleAvailable()) {
    return;
  }

  const generation = lifecycleGeneration;
  const operation = (async () => {
    requireCurrentLifecycle(generation, 'HTTP setup retry');
    const native = requireNativeModule();
    logger.debug('Retrying HTTP/auth setup...');

    const retryResult = await native.retryHTTPSetupProto();
    const decoded = decodeSdkInitResultPayload(retryResult);
    requireCurrentLifecycle(generation, 'HTTP setup retry');
    initState = markHTTPSetupResult(
      initState,
      decoded.httpConfigured,
      decoded.httpApplicable
    );
    if (decoded.httpConfigured) {
      logger.info('HTTP/Auth setup succeeded on retry.');
    } else if (!decoded.httpApplicable) {
      logger.info(
        'HTTP setup not applicable for this configuration; retries stopped.'
      );
    }
  })();
  httpRetryPromise = operation;

  try {
    await operation;
  } catch (error) {
    const sdkError = await asNativeSDKException(error);
    if (generation === lifecycleGeneration) {
      logger.debug('HTTP/Auth retry failed', {
        errorCode: sdkError.code,
        errorCategory: sdkError.category,
      });
    }
    throw sdkError;
  } finally {
    if (httpRetryPromise === operation) {
      httpRetryPromise = null;
    }
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

// Register the live Phase-1 flag so extension files can run the Swift-shaped
// `guard isInitialized` check (requireInitialized / isSDKInitialized) without
// importing RunAnywhere directly (avoids circular imports).
registerInitializedProvider(() => initState.isCoreInitialized);
