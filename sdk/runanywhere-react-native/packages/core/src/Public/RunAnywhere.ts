/**
 * The RunAnywhere React Native SDK facade.
 *
 * One `initialize` call brings the SDK up; every capability then hangs off a
 * namespace (`llm`, `stt`, `voice`, `models`, …). All inference lives in native
 * commons — this layer only marshals options and results.
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
import {
  asSDKException,
  sdkExceptionFromRcResult,
  SDKException,
} from '../Foundation/Errors/SDKException';

import { pluginLoader } from './Extensions/RunAnywhere+PluginLoader';
import { solutions } from './Extensions/Solutions/RunAnywhere+Solutions';
import { llm } from './Api/Llm';
import { vlm } from './Api/Vlm';
import { stt } from './Api/Stt';
import { tts } from './Api/Tts';
import { vad } from './Api/Vad';
import { embeddings } from './Api/Embeddings';
import { rerank } from './Api/Rerank';
import { images } from './Api/Images';
import { diarization } from './Api/Diarization';
import { segmentation } from './Api/Segmentation';
import { voice } from './Api/Voice';
import { rag } from './Api/Rag';
import { models } from './Api/Models';
import { lora } from './Api/Lora';
import { sdkEvents } from './Api/Events';
import { auth, logging, storage } from './Api/Platform';
import type { InitializeOptions, SdkEvent } from './Api/Types';

const logger = new SDKLogger('RunAnywhere');

// ============================================================================
// Internal lifecycle state
// ============================================================================

let initState: InitializationState = createInitialState();
let servicesInitPromise: Promise<void> | null = null;
// In-flight Phase 1 promise shared across concurrent initialize() callers.
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

function requireCurrentLifecycle(generation: number, operation: string): void {
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
 * HTTP-retry bridge.
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

function mapSdkInitEnvironment(environment: SDKEnvironment): SdkInitEnvironment {
  switch (environment) {
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
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return 'production';
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
    case SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED:
    default:
      return 'development';
  }
}

/**
 * Run the deferred network phase: auth, device registration, catalog, and
 * telemetry. `initialize` starts this in the background and callers never wait
 * on it; the services-ready guard joins it when an online call needs it.
 *
 * Not part of the public facade — exported only so the lifecycle-serialization
 * tests can drive the phase directly.
 *
 * @internal
 */
export async function completeServicesInitialization(): Promise<void> {
  const activeReset = resetPromise;
  if (activeReset) await activeReset;

  if (!initState.isCoreInitialized) {
    throw SDKException.notInitialized(
      'The SDK core must be initialized before its network phase can run'
    );
  }
  if (initState.hasCompletedServicesInit) return;
  if (servicesInitPromise) return servicesInitPromise;
  if (!isNativeModuleAvailable()) throw SDKException.nativeModuleUnavailable();

  const generation = lifecycleGeneration;
  const operation = (async () => {
    const native = requireNativeModule();

    requireCurrentLifecycle(generation, 'services initialization');
    initState = markServicesInitializing(initState);

    const phase2Result = await native.completeServicesInitialization();
    const { httpConfigured, httpApplicable } =
      decodeSdkInitResultPayload(phase2Result);

    requireCurrentLifecycle(generation, 'services initialization');
    initState = markServicesInitialized(
      initState,
      httpConfigured,
      httpApplicable
    );
    if (httpConfigured) {
      logger.info('Network phase completed.');
    } else if (!httpApplicable) {
      logger.info(
        'Network phase completed (HTTP setup not applicable for this configuration).'
      );
    } else {
      logger.info(
        'Network phase completed (HTTP/auth deferred — will retry on the next online call).'
      );
    }
  })();
  servicesInitPromise = operation;

  try {
    await operation;
  } catch (error) {
    const sdkError = await asNativeSDKException(error);
    if (generation === lifecycleGeneration) {
      logger.error('Network phase failed', {
        errorCode: sdkError.code,
        errorCategory: sdkError.category,
      });
    }
    throw sdkError;
  } finally {
    if (servicesInitPromise === operation) servicesInitPromise = null;
  }
}

async function initializeCore(options: InitializeOptions): Promise<void> {
  const activeReset = resetPromise;
  if (activeReset) await activeReset;
  if (resetRequired) {
    throw SDKException.notInitialized(
      'Previous SDK teardown did not complete; call reset() again'
    );
  }
  if (initState.isCoreInitialized) return;
  if (initializingPromise) return initializingPromise;

  const generation = lifecycleGeneration;

  initializingPromise = (async () => {
    try {
      const environment =
        options.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
      const effectiveBaseURL = options.baseUrl?.trim() || DEFAULT_BASE_URL;
      const effectiveApiKey = isUsableCredential(options.apiKey)
        ? options.apiKey!.trim()
        : '';
      // Keyless staging is valid: commons overrides the base URL with the baked
      // staging backend and requests go out unauthenticated (PUBLIC-org
      // ingestion). Only production demands credentials.
      const requiresCredentials =
        environment === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
      if (
        !isUsableHTTPURL(effectiveBaseURL, {
          requireHTTPS:
            environment === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
        })
      ) {
        throw SDKException.validationFailed({
          fieldPath: 'InitializeOptions.baseUrl',
          message:
            environment === SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
              ? 'baseUrl must be an absolute HTTPS URL without embedded credentials, query, or fragment'
              : 'baseUrl must be an absolute HTTP(S) URL without embedded credentials, query, or fragment',
        });
      }
      if (requiresCredentials && !effectiveApiKey) {
        throw SDKException.validationFailed({
          fieldPath: 'InitializeOptions.apiKey',
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
      // The baked dev build token is gone; the backend is reached solely
      // through the effective base URL. Keep the proto field, always empty.
      phase2Request.buildToken = '';
      phase2Request.forceRefreshAssignments = false;
      phase2Request.flushTelemetry = true;
      phase2Request.discoverDownloadedModels = true;
      phase2Request.rescanLocalModels = true;

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
        logger.warning('NitroModules global initialization failed', { error });
      }

      requireCurrentLifecycle(generation, 'initialization');

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

        requireCurrentLifecycle(generation, 'initialization');
        initState = markCoreInitialized(initState, initParams);

        logger.info('SDK initialized successfully');

        // The network phase runs in the background: local inference is already
        // usable, and the services-ready guard joins this when an online call
        // needs it.
        void completeServicesInitialization().catch((err) => {
          if (generation !== lifecycleGeneration) return;
          logger.warning(
            `Network phase failed (non-fatal): ${
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
}

function resetInternal(): Promise<void> {
  if (resetPromise) return resetPromise;

  const pendingInitialization = initializingPromise;
  const pendingServicesInitialization = servicesInitPromise;
  const pendingHTTPRetry = httpRetryPromise;
  lifecycleGeneration += 1;
  resetRequired = true;
  // Close the facade synchronously. Generation guards prevent Phase 1, the
  // network phase, and HTTP recovery from reopening this lifetime while their
  // native work settles.
  initState = resetState();

  const operation = (async () => {
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
}

// ============================================================================
// Public facade
// ============================================================================

/** On-device AI for React Native. */
export const RunAnywhere = {
  /**
   * Bring the SDK up: platform adapters, native load, auth, device
   * registration, catalog, and telemetry.
   *
   * Returns as soon as local inference is usable; the network work continues in
   * the background and retries on its own.
   *
   * @example
   * await RunAnywhere.initialize({ apiKey, environment: SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION });
   * const result = await RunAnywhere.llm.generate('Hello');
   *
   * @throws SDKException when the options are invalid or native initialization fails.
   */
  initialize(options: InitializeOptions = {}): Promise<void> {
    return initializeCore(options);
  },

  /** Unload models, close sessions, and clear SDK state. */
  reset(): Promise<void> {
    return resetInternal();
  },

  /** Whether local inference is usable. */
  get isReady(): boolean {
    return initState.isCoreInitialized;
  },

  /** SDK version. */
  get version(): string {
    return SDKConstants.version;
  },

  /**
   * Stable device identity for this app installation.
   *
   * @throws SDKException when native identity cannot be resolved durably.
   */
  get deviceId(): Promise<string> {
    return (async () => {
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
    })();
  },

  /** Lifecycle, model, and error breadcrumbs. */
  get events(): AsyncIterable<SdkEvent> {
    return sdkEvents();
  },

  llm,
  vlm,
  stt,
  tts,
  vad,
  embeddings,
  rerank,
  images,
  diarization,
  segmentation,
  voice,
  rag,
  models,
  lora,

  // Platform services outside the modality spec.
  storage,
  logging,
  auth,
  pluginLoader,
  solutions,
};

// ============================================================================
// Internal network-phase guard. Three branches:
//   1. Fast path: services + HTTP both done → return immediately.
//   2. Recovery path: services done, HTTP failed (offline init) → retry HTTP
//      without re-running the network phase.
//   3. Cold-start path: the network phase has not run yet.
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
  if (!isNativeModuleAvailable()) return;

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
    if (httpRetryPromise === operation) httpRetryPromise = null;
  }
}

async function ensureServicesReadyInternal(): Promise<void> {
  const services = initState.hasCompletedServicesInit;
  const http = initState.hasCompletedHTTPSetup;
  const applicable = initState.httpSetupApplicable;
  if (services && (http || !applicable)) return;
  if (services && !http && applicable) {
    await retryHTTPSetupInternal();
    return;
  }
  await completeServicesInitialization();
}

// Register the network-phase guard so capability files can call
// ensureServicesReady() without importing RunAnywhere (avoids circular imports).
registerServicesReadyGuard(ensureServicesReadyInternal);

// Register the live core-initialized flag so capability files can run the
// `guard isInitialized` check without importing RunAnywhere.
registerInitializedProvider(() => initState.isCoreInitialized);
