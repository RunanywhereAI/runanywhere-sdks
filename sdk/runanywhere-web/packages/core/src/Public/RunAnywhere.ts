/**
 * RunAnywhere Web SDK - Main Entry Point
 *
 * The public API for the RunAnywhere Web SDK.
 * Core is pure TypeScript — no WASM. Backend packages ship their own WASM
 * and install proto-byte adapters via `setRunanywhereModule(...)`.
 *
 * After the V2 cleanup, model lifecycle, registry, downloads, and provider
 * routing are all owned by the commons C ABI through the proto-byte adapters.
 * This file no longer dispatches through ExtensionPoint or ModelManager.
 *
 * Usage:
 *   import { RunAnywhere } from '@runanywhere/web';
 *
 *   await RunAnywhere.initialize({ environment: 'development' });
 *   // Backend packages register their WASM module via setRunanywhereModule();
 *   // typed adapters (ModelLifecycleAdapter, DownloadAdapter, ...) become live.
 */

import { EventCategory } from '@runanywhere/proto-ts/component_types';
import {
  SDKEnvironment,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  DownloadState,
  type DownloadProgress,
} from '@runanywhere/proto-ts/download_service';
import type { TTSSpeakResult } from '@runanywhere/proto-ts/tts_options';
import {
  SdkInitEnvironment,
  SdkInitPhase1Request,
  SdkInitPhase2Request,
  SdkInitResult,
  type SdkInitResult as ProtoSdkInitResult,
} from '@runanywhere/proto-ts/sdk_init';
import type { SDKInitOptions } from '../types/models';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger, LogLevel } from '../Foundation/SDKLogger';
import { LocalFileStorage } from '../Infrastructure/LocalFileStorage';
import { SDKErrorCode, SDKException } from '../Foundation/SDKException';
import { Runtime, prepareModelLoad } from '../Foundation/RuntimeConfig';
import { solutions as SolutionsCapability } from './Extensions/RunAnywhere+Solutions';
import { LoRA as LoRACapability } from './Extensions/RunAnywhere+LoRA';
import { RAG as RAGCapability } from './Extensions/RunAnywhere+RAG';
import { VoiceAgent as VoiceAgentCapability } from './Extensions/RunAnywhere+VoiceAgent';
import { Downloads as DownloadsCapability } from './Extensions/RunAnywhere+Downloads';
import { SDKEvents as SDKEventsCapability } from './Extensions/RunAnywhere+SDKEvents';
import { ModelRegistry as ModelRegistryCapability } from './Extensions/RunAnywhere+ModelRegistry';
import { ModelLifecycle as ModelLifecycleCapability } from './Extensions/RunAnywhere+ModelLifecycle';
import { Hardware as HardwareCapability } from './Extensions/RunAnywhere+Hardware';
import { TextGeneration as TextGenerationCapability } from './Extensions/RunAnywhere+TextGeneration';
import { StructuredOutput as StructuredOutputCapability } from './Extensions/RunAnywhere+StructuredOutput';
import { ToolCalling as ToolCallingCapability } from './Extensions/RunAnywhere+ToolCalling';
import { Logging as LoggingCapability } from './Extensions/RunAnywhere+Logging';
import { STT as STTCapability } from './Extensions/RunAnywhere+STT';
import { TTS as TTSCapability } from './Extensions/RunAnywhere+TTS';
import { VAD as VADCapability } from './Extensions/RunAnywhere+VAD';
import { PluginLoader as PluginLoaderCapability } from './Extensions/RunAnywhere+PluginLoader';
import { VisionLanguage as VisionLanguageCapability } from './Extensions/RunAnywhere+VisionLanguage';
import { createStorageNamespace } from './Extensions/RunAnywhere+Storage';
import { disposeSpeechProvider } from './Extensions/SpeechProvider';
import { StorageAdapter } from '../Adapters/StorageAdapter';
import { HTTPAdapter } from '../Adapters/HTTPAdapter';
import { SDK_VERSION } from '../Foundation/Version';
import {
  clearRunanywhereModule,
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../runtime/EmscriptenModule';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';

/**
 * Persistent storage backend active for the current SDK session.
 * - `fsAccess`: File System Access API (user picked a real directory, Chrome 122+).
 * - `opfs`: Origin Private File System (default persistent fallback).
 * - `memory`: No persistent backend — models live in volatile MEMFS.
 */
export type StorageBackend = 'fsAccess' | 'opfs' | 'memory';

export interface DownloadModelOptions {
  modelId: string;
  model?: ModelInfo;
  allowMeteredNetwork?: boolean;
  resumeExisting?: boolean;
  verifyChecksums?: boolean;
  validateExistingBytes?: boolean;
  updateRegistryOnCompletion?: boolean;
  storageNamespace?: string;
  availableStorageBytes?: number;
  requiredFreeBytesAfterDownload?: number;
  pollIntervalMs?: number;
  onProgress?: (progress: DownloadProgress) => void;
}

const logger = new SDKLogger('RunAnywhere');

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

let _isInitialized = false;
let _initOptions: SDKInitOptions | null = null;
let _initializingPromise: Promise<void> | null = null;
let _localFileStorage: LocalFileStorage | null = null;
let _deviceId: string | null = null;
let _hasCompletedNativePhase1 = false;

// Phase 2 (services) init state — mirrors Swift's
// `hasCompletedServicesInit` + `hasCompletedHTTPSetup` split.
let _hasCompletedServicesInit = false;
let _servicesInitPromise: Promise<void> | null = null;

interface SdkInitModule extends EmscriptenRunanywhereModule {
  _rac_sdk_init_phase1_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_sdk_init_phase2_proto?(
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_auth_is_authenticated?(): number;
  _rac_auth_get_user_id?(): number;
  _rac_auth_get_organization_id?(): number;
  _rac_state_is_device_registered?(): number;
}

/** Generate (and cache) a stable device ID, matching Swift's UUID-style. */
function generateDeviceId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/** Persist + retrieve a device ID across SDK sessions (best-effort localStorage). */
function ensureDeviceId(): string {
  if (_deviceId) return _deviceId;
  try {
    if (typeof localStorage !== 'undefined') {
      const stored = localStorage.getItem('runanywhere.deviceId');
      if (stored) {
        _deviceId = stored;
        return stored;
      }
    }
  } catch { /* ignore */ }
  const id = generateDeviceId();
  try {
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('runanywhere.deviceId', id);
    }
  } catch { /* ignore */ }
  _deviceId = id;
  return id;
}

function mapSdkInitEnvironment(env: SDKEnvironment): SdkInitEnvironment {
  switch (env) {
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_PRODUCTION;
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_STAGING;
    case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
    default:
      return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT;
  }
}

function invokeSdkInitProto(
  module: SdkInitModule,
  bytes: Uint8Array,
  fn: (requestBytes: number, requestSize: number, outResult: number) => number,
  functionName: string,
): ProtoSdkInitResult | null {
  return new ProtoWasmBridge(module, logger).withHeapBytes(bytes, (ptr, size) => (
    new ProtoWasmBridge(module, logger).callResultProto(
      SdkInitResult,
      (outResult) => fn(ptr, size, outResult),
      functionName,
    )
  ));
}

function throwIfSdkInitFailed(result: ProtoSdkInitResult | null, phase: string): void {
  if (!result) {
    throw SDKException.fromCode(
      SDKErrorCode.InitializationFailed,
      `${phase} returned no sdk-init result.`,
    );
  }
  if (!result.success) {
    throw new SDKException(result.error ?? {
      category: 0,
      code: 0,
      cAbiCode: SDKErrorCode.InitializationFailed,
      message: `${phase} failed.`,
      nestedMessage: result.warning || undefined,
      context: undefined,
      timestampMs: Date.now(),
      severity: 0,
      component: 'sdk',
      retryable: false,
      remediationHint: '',
      correlationId: '',
    });
  }
  if (result.warning) {
    logger.warning(`${phase} warning: ${result.warning}`);
  }
}

export function completeNativePhase1ForModule(module: EmscriptenRunanywhereModule): void {
  if (_hasCompletedNativePhase1) return;
  const sdkModule = module as SdkInitModule;
  if (typeof sdkModule._rac_sdk_init_phase1_proto !== 'function') {
    logger.warning(
      'WASM module missing _rac_sdk_init_phase1_proto; native Phase 1 will run after the artifact is rebuilt.',
    );
    return;
  }

  const environment = _initOptions?.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
  const bytes = SdkInitPhase1Request.encode({
    environment: mapSdkInitEnvironment(environment),
    apiKey: _initOptions?.apiKey ?? '',
    baseUrl: _initOptions?.baseURL ?? '',
    deviceId: ensureDeviceId(),
  }).finish();

  const result = invokeSdkInitProto(
    sdkModule,
    bytes,
    sdkModule._rac_sdk_init_phase1_proto.bind(sdkModule),
    'rac_sdk_init_phase1_proto',
  );
  throwIfSdkInitFailed(result, 'SDK Phase 1');
  _hasCompletedNativePhase1 = true;
}

export async function completeDeferredServicesInitialization(): Promise<void> {
  if (!_isInitialized || _hasCompletedServicesInit) return;
  await RunAnywhere.completeServicesInitialization();
}

function readNullableCString(fn?: () => number): string | null {
  if (typeof fn !== 'function') return null;
  const module = tryRunanywhereModule() as SdkInitModule | null;
  if (!module) return null;
  try {
    const ptr = fn.call(module);
    return ptr ? module.UTF8ToString(ptr) : null;
  } catch {
    return null;
  }
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ---------------------------------------------------------------------------
// RunAnywhere Public API
// ---------------------------------------------------------------------------

export const RunAnywhere = {
  // =========================================================================
  // SDK State
  // =========================================================================

  get isInitialized(): boolean {
    return _isInitialized;
  },

  /** Mirror Swift `RunAnywhere.areServicesReady` (Phase 2 complete). */
  get areServicesReady(): boolean {
    return _hasCompletedServicesInit;
  },

  /** Mirror Swift `RunAnywhere.isActive`. */
  get isActive(): boolean {
    return _isInitialized && _initOptions !== null;
  },

  get version(): string {
    return SDK_VERSION;
  },

  get environment(): SDKEnvironment | null {
    return _initOptions?.environment ?? null;
  },

  get events(): EventBus {
    return EventBus.shared;
  },

  /**
   * Stable device identifier. On the Web SDK this is persisted in
   * `localStorage` so it survives reloads.
   */
  get deviceId(): string {
    return ensureDeviceId();
  },

  /**
   * Returns true if the SDK currently holds a non-expired access token.
   *
   * Delegates to commons `rac_auth_is_authenticated()` via the WASM module
   * once a backend has installed it. Before any backend registers, no WASM
   * module exists and the SDK cannot be authenticated — this returns false.
   *
   * NOTE: the Web SDK does not yet call `rac_auth_init` + the
   * authenticate/refresh flow from the browser (no UI surface registers
   * credentials), so this will typically return false until a future auth
   * flow lands. The implementation here is the canonical bridge, so once
   * auth wiring arrives, this call will reflect the real state without
   * further changes.
   */
  get isAuthenticated(): boolean {
    const mod = tryRunanywhereModule() as SdkInitModule | null;
    if (!mod) return false;
    const fn = mod._rac_auth_is_authenticated;
    if (typeof fn !== 'function') return false;
    try {
      return fn.call(mod) !== 0;
    } catch {
      return false;
    }
  },

  getUserId(): string | null {
    const mod = tryRunanywhereModule() as SdkInitModule | null;
    return readNullableCString(mod?._rac_auth_get_user_id);
  },

  getOrganizationId(): string | null {
    const mod = tryRunanywhereModule() as SdkInitModule | null;
    return readNullableCString(mod?._rac_auth_get_organization_id);
  },

  isDeviceRegistered(): boolean {
    const mod = tryRunanywhereModule() as SdkInitModule | null;
    const fn = mod?._rac_state_is_device_registered;
    if (typeof fn !== 'function') return false;
    try {
      return fn.call(mod) !== 0;
    } catch {
      return false;
    }
  },

  /** Runtime configuration surface (acceleration mode etc.). */
  get runtime(): typeof Runtime {
    return Runtime;
  },

  /** Convenience setter for the preferred acceleration. */
  async setRuntime(mode: 'cpu' | 'webgpu' | 'auto'): Promise<void> {
    if (mode === 'auto') {
      Runtime.preferred = 'auto';
      return;
    }
    await Runtime.setAcceleration(mode);
  },

  // =========================================================================
  // Initialization (pure TypeScript — no WASM)
  // =========================================================================

  /**
   * Initialize the RunAnywhere SDK.
   *
   * This only initializes the TypeScript infrastructure:
   *   1. Configure logging
   *   2. Restore local file storage (if previously configured)
   *
   * WASM and proto-byte adapters are installed by backend packages once
   * their module loads.
   */
  async initialize(options: SDKInitOptions = {}): Promise<void> {
    if (_isInitialized) {
      logger.debug('Already initialized');
      return;
    }

    if (_initializingPromise) {
      logger.debug('Initialization already in progress, awaiting...');
      return _initializingPromise;
    }

    _initializingPromise = (async () => {
      try {
        const env = options.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
        _initOptions = { ...options, environment: env };

        if (options.debug) {
          SDKLogger.level = LogLevel.Debug;
        }

        logger.info(`Initializing RunAnywhere Web SDK (${env})...`);

        if (typeof ReadableStream === 'undefined') {
          throw SDKException.fromCode(
            SDKErrorCode.InitializationFailed,
            'ReadableStream is not available in this environment. ' +
            'The RunAnywhere Web SDK requires the Fetch Streams API ' +
            '(Chrome 43+, Firefox 65+, Safari 14.1+, Edge 79+).',
          );
        }

        try {
          await RunAnywhere.storage.restoreLocalStorage();
        } catch (err) {
          logger.warning(`Failed to restore local storage: ${err instanceof Error ? err.message : String(err)}`);
        }

        _isInitialized = true;

        ensureDeviceId();

        logger.info('RunAnywhere Web SDK initialized successfully');
        EventBus.shared.emit('sdk.initialized', EventCategory.EVENT_CATEGORY_INITIALIZATION, {
          environment: env,
        });

        void RunAnywhere.completeServicesInitialization().catch((err) => {
          logger.warning(
            `Phase 2 init failed (non-fatal): ${err instanceof Error ? err.message : String(err)}`,
          );
        });
      } finally {
        _initializingPromise = null;
      }
    })();

    return _initializingPromise;
  },

  /**
   * Complete the Phase 2 (services) initialization. Mirror of Swift's
   * `RunAnywhere.completeServicesInitialization()`. Idempotent — concurrent
   * callers share a single in-flight promise.
   */
  async completeServicesInitialization(): Promise<void> {
    if (_hasCompletedServicesInit) return;
    if (_servicesInitPromise) return _servicesInitPromise;

    _servicesInitPromise = (async () => {
      try {
        const module = tryRunanywhereModule() as SdkInitModule | null;
        if (!module) {
          logger.debug('Services initialization deferred until a Web backend registers a WASM module');
          return;
        }

        if (!_hasCompletedNativePhase1) {
          completeNativePhase1ForModule(module);
        }

        if (typeof module._rac_sdk_init_phase2_proto === 'function') {
          const bytes = SdkInitPhase2Request.encode({}).finish();
          const result = invokeSdkInitProto(
            module,
            bytes,
            module._rac_sdk_init_phase2_proto.bind(module),
            'rac_sdk_init_phase2_proto',
          );
          throwIfSdkInitFailed(result, 'SDK Phase 2');
        } else {
          logger.warning(
            'WASM module missing _rac_sdk_init_phase2_proto; services init remains browser-only until rebuild.',
          );
        }

        _hasCompletedServicesInit = true;
        logger.debug('Services initialization complete (Phase 2)');
      } finally {
        _servicesInitPromise = null;
      }
    })();
    return _servicesInitPromise;
  },

  /**
   * Internal-style guard used by extensions that need a fully-initialized SDK.
   */
  async ensureServicesReady(): Promise<void> {
    if (_hasCompletedServicesInit) return;
    return RunAnywhere.completeServicesInitialization();
  },

  // =========================================================================
  // Storage namespace
  // =========================================================================

  storage: createStorageNamespace({
    get isLocalStorageSupported(): boolean {
      return LocalFileStorage.isSupported;
    },

    get isLocalStorageReady(): boolean {
      return _localFileStorage?.isReady ?? false;
    },

    get hasLocalStorageHandle(): boolean {
      return _localFileStorage?.hasStoredHandle ?? false;
    },

    get localStorageDirectoryName(): string | null {
      return _localFileStorage?.directoryName ?? LocalFileStorage.storedDirectoryName;
    },

    get storageBackend(): StorageBackend {
      if (LocalFileStorage.isSupported && _localFileStorage?.isReady) {
        return 'fsAccess';
      }
      const hasOPFS = typeof navigator !== 'undefined'
        && 'storage' in navigator
        && 'getDirectory' in (navigator.storage || {});
      return hasOPFS ? 'opfs' : 'memory';
    },

    async chooseLocalStorageDirectory(): Promise<boolean> {
      if (!LocalFileStorage.isSupported) {
        logger.warning('File System Access API not supported — using browser storage (OPFS)');
        return false;
      }

      if (!_localFileStorage) {
        _localFileStorage = new LocalFileStorage();
      }

      const success = await _localFileStorage.chooseDirectory();
      if (success) {
        EventBus.shared.emit('storage.localDirectorySelected', EventCategory.EVENT_CATEGORY_STORAGE, {
          directoryName: _localFileStorage.directoryName,
        });
      }
      return success;
    },

    async restoreLocalStorage(): Promise<boolean> {
      if (!LocalFileStorage.isSupported) return false;

      if (!_localFileStorage) {
        _localFileStorage = new LocalFileStorage();
      }

      const success = await _localFileStorage.restoreDirectory();
      if (success) {
        logger.info(`Local storage restored: ${_localFileStorage.directoryName}`);
      }
      return success;
    },

    async requestLocalStorageAccess(): Promise<boolean> {
      if (!_localFileStorage) return false;
      return _localFileStorage.requestAccess();
    },
  }),

  // =========================================================================
  // Solutions namespace
  // =========================================================================

  solutions: SolutionsCapability,

  // =========================================================================
  // Namespace extensions — proto-byte adapter facades.
  // =========================================================================

  /** C++-owned download workflow — plan/start/cancel/resume/progress. */
  downloads: DownloadsCapability,

  /** C++ SDKEvent proto stream — subscribe/publish/poll/failure. */
  sdkEvents: SDKEventsCapability,

  /** C++ model registry proto bridge — list/query/listDownloaded/get/mutate. */
  modelRegistry: ModelRegistryCapability,

  /** C++ model lifecycle proto bridge — load/unload/current/snapshot. */
  modelLifecycle: ModelLifecycleCapability,

  /** Text generation — `RunAnywhere.textGeneration.generate(options)` etc. */
  textGeneration: TextGenerationCapability,

  /** Structured output — `RunAnywhere.structuredOutput.generate(prompt, schema)` */
  structuredOutput: StructuredOutputCapability,

  /** Tool calling — `RunAnywhere.toolCalling.generate(prompt, tools)` */
  toolCalling: ToolCallingCapability,

  /** Speech-to-text — `RunAnywhere.stt.create()` / `transcribe(handle, audio)` etc. */
  stt: STTCapability,

  /** Text-to-speech — `RunAnywhere.tts.create()` / `synthesize(handle, text)` etc. */
  tts: TTSCapability,

  /** Voice activity detection — `RunAnywhere.vad.create()` / `process(handle, samples)` etc. */
  vad: VADCapability,

  /** Logging control — `RunAnywhere.logging.setLevel(LogLevel.Debug)` */
  logging: LoggingCapability,

  /** LoRA adapter management — `RunAnywhere.lora.apply(request)` etc. */
  lora: LoRACapability,

  /** RAG retrieval pipeline — `RunAnywhere.rag.query(...)` etc. */
  rag: RAGCapability,

  /** Voice-agent orchestration — `RunAnywhere.voiceAgent.processTurn(...)` etc. */
  voiceAgent: VoiceAgentCapability,

  /** Vision-language model inference — `RunAnywhere.visionLanguage.processImage(...)`. */
  visionLanguage: VisionLanguageCapability,

  /** Runtime plugin loader — unavailable on plain WASM unless host exports the ABI. */
  pluginLoader: PluginLoaderCapability,

  /** Hardware profile — `RunAnywhere.hardware.getProfile()` etc. */
  hardware: HardwareCapability,

  // =========================================================================
  // Swift-shaped flat facade
  // =========================================================================

  async loadModel(
    request: Parameters<typeof ModelLifecycleCapability.loadModel>[0],
  ): Promise<Awaited<ReturnType<typeof ModelLifecycleCapability.loadModelAsync>>> {
    return ModelLifecycleCapability.loadModelAsync(request);
  },

  async unloadModel(
    request: Parameters<typeof ModelLifecycleCapability.unloadModel>[0],
  ): Promise<Awaited<ReturnType<typeof ModelLifecycleCapability.unloadModelAsync>>> {
    return ModelLifecycleCapability.unloadModelAsync(request);
  },

  currentModel(
    request?: Parameters<typeof ModelLifecycleCapability.currentModel>[0],
  ): ReturnType<typeof ModelLifecycleCapability.currentModel> {
    return ModelLifecycleCapability.currentModel(request);
  },

  componentLifecycleSnapshot(
    component: Parameters<typeof ModelLifecycleCapability.componentLifecycleSnapshot>[0],
  ): ReturnType<typeof ModelLifecycleCapability.componentLifecycleSnapshot> {
    return ModelLifecycleCapability.componentLifecycleSnapshot(component);
  },

  listModels(): ReturnType<typeof ModelRegistryCapability.listModels> {
    return ModelRegistryCapability.listModels();
  },

  queryModels(
    query: Parameters<typeof ModelRegistryCapability.queryModels>[0],
  ): ReturnType<typeof ModelRegistryCapability.queryModels> {
    return ModelRegistryCapability.queryModels(query);
  },

  getModel(
    modelId: Parameters<typeof ModelRegistryCapability.getModel>[0],
  ): ReturnType<typeof ModelRegistryCapability.getModel> {
    return ModelRegistryCapability.getModel(modelId);
  },

  downloadedModels(): ReturnType<typeof ModelRegistryCapability.downloadedModels> {
    return ModelRegistryCapability.downloadedModels();
  },

  importModel(model: ModelInfo): boolean {
    return ModelRegistryCapability.registerModel(model);
  },

  async downloadModel(
    input: string | DownloadModelOptions,
  ): Promise<DownloadProgress> {
    const request = typeof input === 'string' ? { modelId: input } : input;
    const model = request.model ?? ModelRegistryCapability.getModel(request.modelId) ?? undefined;
    if (!model) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        `Model metadata for '${request.modelId}' is not registered.`,
      );
    }
    await prepareModelLoad({
      request: {
        modelId: request.modelId,
        category: model.category,
        framework: model.framework,
      },
      model,
    });
    ModelRegistryCapability.registerModel(model);

    const plan = DownloadsCapability.plan({
      modelId: request.modelId,
      model,
      resumeExisting: request.resumeExisting ?? false,
      availableStorageBytes: request.availableStorageBytes ?? 0,
      allowMeteredNetwork: request.allowMeteredNetwork ?? true,
      storageNamespace: request.storageNamespace ?? '',
      validateExistingBytes: request.validateExistingBytes ?? false,
      verifyChecksums: request.verifyChecksums ?? false,
      requiredFreeBytesAfterDownload: request.requiredFreeBytesAfterDownload ?? 0,
    });
    if (!plan?.canStart) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        plan?.errorMessage || `Download plan for '${request.modelId}' could not start.`,
      );
    }

    const start = DownloadsCapability.start({
      modelId: request.modelId,
      plan,
      resume: request.resumeExisting ?? false,
      resumeToken: plan.resumeToken,
      updateRegistryOnCompletion: request.updateRegistryOnCompletion ?? true,
    });
    if (!start?.accepted) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        start?.errorMessage || `Download start for '${request.modelId}' was rejected.`,
      );
    }

    const terminal = new Set([
      DownloadState.DOWNLOAD_STATE_COMPLETED,
      DownloadState.DOWNLOAD_STATE_FAILED,
      DownloadState.DOWNLOAD_STATE_CANCELLED,
    ]);
    let lastProgress = start.initialProgress;
    if (lastProgress) request.onProgress?.(lastProgress);

    while (!lastProgress || !terminal.has(lastProgress.state)) {
      await delay(request.pollIntervalMs ?? 250);
      const progress = DownloadsCapability.poll({
        modelId: request.modelId,
        taskId: start.taskId,
      });
      if (!progress) continue;
      lastProgress = progress;
      request.onProgress?.(progress);
    }

    if (lastProgress.state !== DownloadState.DOWNLOAD_STATE_COMPLETED) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        lastProgress.errorMessage || `Download for '${request.modelId}' ended in state ${lastProgress.state}.`,
      );
    }
    return lastProgress;
  },

  getStorageInfo(
    request: Parameters<ReturnType<typeof createStorageNamespace>['info']>[0],
  ): ReturnType<ReturnType<typeof createStorageNamespace>['info']> {
    return RunAnywhere.storage.info(request);
  },

  deleteStorage(
    request: Parameters<ReturnType<typeof createStorageNamespace>['delete']>[0],
  ): ReturnType<ReturnType<typeof createStorageNamespace>['delete']> {
    return RunAnywhere.storage.delete(request);
  },

  clearCache(): never {
    throw SDKException.backendNotAvailable(
      'clearCache',
      'The Web SDK has no exported rac_file_manager_clear_cache bridge yet.',
    );
  },

  cleanTempFiles(): never {
    throw SDKException.backendNotAvailable(
      'cleanTempFiles',
      'The Web SDK has no exported rac_file_manager_clear_temp bridge yet.',
    );
  },

  generate(
    options: Parameters<typeof TextGenerationCapability.generate>[0],
  ): ReturnType<typeof TextGenerationCapability.generate> {
    return TextGenerationCapability.generate(options);
  },

  generateStream(
    options: Parameters<typeof TextGenerationCapability.generateStream>[0],
  ): ReturnType<typeof TextGenerationCapability.generateStream> {
    return TextGenerationCapability.generateStream(options);
  },

  cancelGeneration(): void {
    TextGenerationCapability.cancelGeneration();
  },

  generateStructured(
    ...args: Parameters<typeof StructuredOutputCapability.generate>
  ): ReturnType<typeof StructuredOutputCapability.generate> {
    return StructuredOutputCapability.generate(...args);
  },

  generateStructuredStream(
    ...args: Parameters<typeof TextGenerationCapability.generateStructuredStream>
  ): ReturnType<typeof TextGenerationCapability.generateStructuredStream> {
    return TextGenerationCapability.generateStructuredStream(...args);
  },

  extractStructuredOutput(
    ...args: Parameters<typeof TextGenerationCapability.extractStructuredOutput>
  ): ReturnType<typeof TextGenerationCapability.extractStructuredOutput> {
    return TextGenerationCapability.extractStructuredOutput(...args);
  },

  generateWithTools(
    prompt: Parameters<typeof ToolCallingCapability.generateWithTools>[0],
    options?: Parameters<typeof ToolCallingCapability.generateWithTools>[1],
  ): ReturnType<typeof ToolCallingCapability.generateWithTools> {
    return ToolCallingCapability.generateWithTools(prompt, options);
  },

  transcribe(
    ...args: Parameters<typeof STTCapability.transcribeAuto>
  ): ReturnType<typeof STTCapability.transcribeAuto> {
    return STTCapability.transcribeAuto(...args);
  },

  transcribeStream(
    ...args: Parameters<typeof STTCapability.transcribeStream>
  ): ReturnType<typeof STTCapability.transcribeStream> {
    return STTCapability.transcribeStream(...args);
  },

  synthesize(
    ...args: Parameters<typeof TTSCapability.synthesizeAuto>
  ): ReturnType<typeof TTSCapability.synthesizeAuto> {
    return TTSCapability.synthesizeAuto(...args);
  },

  synthesizeStream(
    ...args: Parameters<typeof TTSCapability.synthesizeStream>
  ): ReturnType<typeof TTSCapability.synthesizeStream> {
    return TTSCapability.synthesizeStream(...args);
  },

  async speak(
    ...args: Parameters<typeof TTSCapability.synthesizeAuto>
  ): Promise<TTSSpeakResult> {
    const output = await TTSCapability.synthesizeAuto(...args);
    return {
      audioFormat: output.audioFormat,
      sampleRate: output.sampleRate,
      durationMs: output.durationMs,
      audioSizeBytes: output.audioSizeBytes || output.audioData.byteLength,
      metadata: output.metadata,
      timestampMs: output.timestampMs,
      errorMessage: output.errorMessage,
      errorCode: output.errorCode,
    };
  },

  stopSynthesis(
    handle: Parameters<typeof TTSCapability.stop>[0],
  ): ReturnType<typeof TTSCapability.stop> {
    return TTSCapability.stop(handle);
  },

  stopSpeaking(
    handle: Parameters<typeof TTSCapability.stop>[0],
  ): ReturnType<typeof TTSCapability.stop> {
    return TTSCapability.stop(handle);
  },

  detectVoiceActivity(
    ...args: Parameters<typeof VADCapability.detectVoiceAuto>
  ): ReturnType<typeof VADCapability.detectVoiceAuto> {
    return VADCapability.detectVoiceAuto(...args);
  },

  async *streamVAD(
    audio: AsyncIterable<Parameters<typeof VADCapability.detectVoiceAuto>[0]>,
    options?: Parameters<typeof VADCapability.detectVoiceAuto>[1],
  ): AsyncIterable<Awaited<ReturnType<typeof VADCapability.detectVoiceAuto>>> {
    for await (const chunk of audio) {
      yield await VADCapability.detectVoiceAuto(chunk, options);
    }
  },

  resetVAD(
    handle: Parameters<typeof VADCapability.reset>[0],
  ): ReturnType<typeof VADCapability.reset> {
    return VADCapability.reset(handle);
  },

  ragCreatePipeline(
    ...args: Parameters<typeof RAGCapability.createPipeline>
  ): ReturnType<typeof RAGCapability.createPipeline> {
    return RAGCapability.createPipeline(...args);
  },

  ragDestroyPipeline(): ReturnType<typeof RAGCapability.destroyPipeline> {
    return RAGCapability.destroyPipeline();
  },

  ragIngest(
    ...args: Parameters<typeof RAGCapability.ingest>
  ): ReturnType<typeof RAGCapability.ingest> {
    return RAGCapability.ingest(...args);
  },

  ragAddDocumentsBatch(
    ...args: Parameters<typeof RAGCapability.addDocumentsBatch>
  ): ReturnType<typeof RAGCapability.addDocumentsBatch> {
    return RAGCapability.addDocumentsBatch(...args);
  },

  ragGetDocumentCount(): ReturnType<typeof RAGCapability.getDocumentCount> {
    return RAGCapability.getDocumentCount();
  },

  ragGetStatistics(): ReturnType<typeof RAGCapability.getStatistics> {
    return RAGCapability.getStatistics();
  },

  ragClearDocuments(): ReturnType<typeof RAGCapability.clearDocuments> {
    return RAGCapability.clearDocuments();
  },

  ragQuery(
    ...args: Parameters<typeof RAGCapability.query>
  ): ReturnType<typeof RAGCapability.query> {
    return RAGCapability.query(...args);
  },

  initializeVoiceAgent(
    ...args: Parameters<typeof VoiceAgentCapability.initialize>
  ): ReturnType<typeof VoiceAgentCapability.initialize> {
    return VoiceAgentCapability.initialize(...args);
  },

  initializeVoiceAgentWithLoadedModels(): ReturnType<typeof VoiceAgentCapability.initializeWithLoadedModels> {
    return VoiceAgentCapability.initializeWithLoadedModels();
  },

  getVoiceAgentComponentStates(): ReturnType<typeof VoiceAgentCapability.getComponentStates> {
    return VoiceAgentCapability.getComponentStates();
  },

  processVoiceTurn(
    ...args: Parameters<typeof VoiceAgentCapability.processTurn>
  ): ReturnType<typeof VoiceAgentCapability.processTurn> {
    return VoiceAgentCapability.processTurn(...args);
  },

  streamVoiceAgent(
    ...args: Parameters<typeof VoiceAgentCapability.stream>
  ): ReturnType<typeof VoiceAgentCapability.stream> {
    return VoiceAgentCapability.stream(...args);
  },

  cleanupVoiceAgent(): ReturnType<typeof VoiceAgentCapability.cleanup> {
    return VoiceAgentCapability.cleanup();
  },

  async processImage(
    ...args: Parameters<typeof VisionLanguageCapability.processImage>
  ): Promise<Awaited<ReturnType<typeof VisionLanguageCapability.processImage>>> {
    if (!VisionLanguageCapability.isModelLoaded) {
      await VisionLanguageCapability.loadCurrentModel();
    }
    return VisionLanguageCapability.processImage(...args);
  },

  async processImageStream(
    ...args: Parameters<typeof VisionLanguageCapability.processImageStream>
  ): ReturnType<typeof VisionLanguageCapability.processImageStream> {
    if (!VisionLanguageCapability.isModelLoaded) {
      await VisionLanguageCapability.loadCurrentModel();
    }
    return VisionLanguageCapability.processImageStream(...args);
  },

  cancelVLMGeneration(): ReturnType<typeof VisionLanguageCapability.cancelVLMGeneration> {
    return VisionLanguageCapability.cancelVLMGeneration();
  },

  // =========================================================================
  // Shutdown
  // =========================================================================

  shutdown(): void {
    logger.info('Shutting down RunAnywhere Web SDK...');

    // Clear every WASM adapter singleton that `setRunanywhereModule()`
    // installed (DownloadAdapter, HardwareAdapter, ModelLifecycleAdapter,
    // ModelRegistryAdapter, ModalityProtoAdapter, SDKEventStreamAdapter)
    // and null the global module so post-shutdown calls into
    // ModalityProtoAdapter / HardwareAdapter / tryRunanywhereModule()
    // can't acquire stale references to a torn-down backend.
    clearRunanywhereModule();
    // HTTPAdapter and StorageAdapter are owned outside setRunanywhereModule(),
    // so they must be cleared explicitly to complete the ownership boundary.
    HTTPAdapter.clearDefaultModule();
    StorageAdapter.clearDefaultHandles();

    // Tear down any registered speech provider (e.g. standalone Sherpa
    // installed by `@runanywhere/web-onnx`) so its backend module/component
    // handles do not survive across shutdown/reset boundaries. Errors are
    // logged but do not block the rest of the teardown.
    void disposeSpeechProvider().catch((err) => {
      logger.warning(`SpeechProvider.dispose() threw during shutdown: ${String(err)}`);
    });

    EventBus.reset();

    _isInitialized = false;
    _initOptions = null;
    _initializingPromise = null;
    _localFileStorage = null;
    _hasCompletedNativePhase1 = false;
    _hasCompletedServicesInit = false;
    _servicesInitPromise = null;

    logger.info('RunAnywhere Web SDK shut down');
  },

  reset(): void {
    RunAnywhere.shutdown();
  },
};
