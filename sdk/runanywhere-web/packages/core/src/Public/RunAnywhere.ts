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
  ModelArtifactType,
  ModelCategory,
  AudioFormat,
  type InferenceFramework,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  DownloadFailureReason,
  DownloadState,
  type DownloadPlanRequest,
  type DownloadPlanResult,
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
import { SDKLogger } from '../Foundation/SDKLogger';
import { requestPersistentStorage } from '../Infrastructure/BrowserStorage';
import { LocalFileStorage } from '../Infrastructure/LocalFileStorage';
import { OPFSBridge } from '../Infrastructure/OPFSBridge';
import {
  frameworkOPFSDir,
  primaryFilenameFromModel,
} from '../Infrastructure/FrameworkOPFSPaths';
import { ProtoErrorCode, SDKException } from '../Foundation/SDKException';
import { Runtime, prepareModelLoad } from '../Foundation/RuntimeConfig';
import { solutions as SolutionsCapability } from './Extensions/RunAnywhere+Solutions';
import { Embeddings as EmbeddingsCapability } from './Extensions/RunAnywhere+Embeddings';
import { LoRA as LoRACapability } from './Extensions/RunAnywhere+LoRA';
import { RAG as RAGCapability } from './Extensions/RunAnywhere+RAG';
import { VoiceAgent as VoiceAgentCapability } from './Extensions/RunAnywhere+VoiceAgent';
import { Downloads as DownloadsCapability } from './Extensions/RunAnywhere+Downloads';
import { SDKEvents as SDKEventsCapability } from './Extensions/RunAnywhere+SDKEvents';
import { ModelRegistry as ModelRegistryCapability } from './Extensions/RunAnywhere+ModelRegistry';
import { WebModelLifecycle as ModelLifecycleCapability } from './Extensions/RunAnywhere+ModelLifecycle';
import { TextGeneration as TextGenerationCapability } from './Extensions/RunAnywhere+TextGeneration';
import { StructuredOutput as StructuredOutputCapability } from './Extensions/RunAnywhere+StructuredOutput';
import { ToolCalling as ToolCallingCapability } from './Extensions/RunAnywhere+ToolCalling';
import { Logging as LoggingCapability } from './Extensions/RunAnywhere+Logging';
import { STT as STTCapability } from './Extensions/RunAnywhere+STT';
import { TTS as TTSCapability, sharedTTSPlayback } from './Extensions/RunAnywhere+TTS';
import { VAD as VADCapability } from './Extensions/RunAnywhere+VAD';
import { PluginLoader as PluginLoaderCapability } from './Extensions/RunAnywhere+PluginLoader';
import { VisionLanguage as VisionLanguageCapability } from './Extensions/RunAnywhere+VisionLanguage';
import type {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
  VLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';
import { Hybrid as HybridCapability } from './Extensions/RunAnywhere+Hybrid';
import { Backends as BackendsCapability } from './Extensions/Backends/onnxStatus';
import {
  createStorageNamespace,
  setRegisterModelHydrateHook,
} from './Extensions/RunAnywhere+Storage';
import { flatFacade } from './Extensions/RunAnywhere+FlatFacade';
import { StorageAdapter } from '../Adapters/StorageAdapter';
import { HTTPAdapter } from '../Adapters/HTTPAdapter';
import { SDK_PLATFORM, SDK_VERSION } from '../Foundation/Version';
import {
  clearRunanywhereModule,
  getAllRegisteredModules,
  getModuleForCapability,
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../runtime/EmscriptenModule';
import { CommonsModule } from '../runtime/CommonsModule';
import { ProtoWasmBridge } from '../runtime/ProtoWasm';
import { OffscreenRuntimeBridge, setStreamWorkerInit } from '../runtime/OffscreenRuntimeBridge';
import { setStreamWorkerFactory } from '../runtime/StreamWorkerFactoryRegistry';

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
// Separate from _hasCompletedServicesInit: Phase 2 marks services ready even
// if the HTTP/auth round-trip failed (offline mode). ensureServicesReady()
// retries HTTP-only on the next API call without re-running Phase 2.
let _hasCompletedHTTPSetup = false;
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
  _rac_sdk_retry_http_proto?(outResult: number): number;
  _rac_wasm_set_client_info?(
    sdkBinding: number,
    appIdentifier: number,
    appName: number,
    appVersion: number,
    appBuild: number,
    locale: number,
    timezone: number,
  ): void;
  _rac_wasm_get_version_major?(): number;
  _rac_wasm_get_version_minor?(): number;
  _rac_wasm_get_version_patch?(): number;
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

/** Persist + retrieve a device ID across SDK sessions.
 *
 * Mirrors Swift's `CppBridge.Device.persistentId`: delegates to commons'
 * device-identity chain (secure_get → vendor ID → synthesized UUID) when a
 * WASM module is available, falling back to the TS-local UUID only when no
 * module is installed. This ensures the same canonical ID is returned whether
 * the call happens before or after a backend module registers.
 *
 * The `rac_state_get_persistent_device_id` function is exported by the commons
 * WASM and reads/writes via the `secure_get` / `secure_set` ABI backed by
 * `localStorage` with the `rac_sdk_` key prefix — the same storage slot that
 * C++ uses, so there is only one device-ID registry entry.
 */
function ensureDeviceId(): string {
  if (_deviceId) return _deviceId;

  // Prefer the commons device-identity chain so all layers share one ID.
  try {
    const mod = tryRunanywhereModule();
    const modWithDeviceId = mod as (EmscriptenRunanywhereModule & { _rac_state_get_persistent_device_id?: () => number }) | null;
    if (modWithDeviceId && typeof modWithDeviceId._rac_state_get_persistent_device_id === 'function') {
      const ptr = modWithDeviceId._rac_state_get_persistent_device_id();
      if (ptr) {
        const id = modWithDeviceId.UTF8ToString(ptr);
        if (id) {
          _deviceId = id;
          return id;
        }
      }
    }
  } catch { /* fall through to TS fallback */ }

  // TS fallback: keep backwards-compat key so existing installs keep their ID.
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

function invokeSdkResultProto(
  module: SdkInitModule,
  fn: (outResult: number) => number,
  functionName: string,
): ProtoSdkInitResult | null {
  return new ProtoWasmBridge(module, logger).callResultProto(
    SdkInitResult,
    (outResult) => fn(outResult),
    functionName,
  );
}

function normalizeMetadataString(value: string | null | undefined): string | null {
  const normalized = value?.trim();
  return normalized && normalized.length > 0 ? normalized : null;
}

function browserDocumentTitle(): string | null {
  if (typeof document === 'undefined') return null;
  const appNameMeta = document.querySelector<HTMLMetaElement>('meta[name="application-name"]');
  return normalizeMetadataString(appNameMeta?.content)
    ?? normalizeMetadataString(document.title);
}

function browserLocale(): string | null {
  if (typeof navigator === 'undefined') return null;
  return normalizeMetadataString(navigator.languages?.[0])
    ?? normalizeMetadataString(navigator.language);
}

function browserTimezone(): string | null {
  try {
    return normalizeMetadataString(Intl.DateTimeFormat().resolvedOptions().timeZone);
  } catch {
    return null;
  }
}

function clientInfoValue(value: string | null | undefined): string | null {
  return normalizeMetadataString(value);
}

function nativeSdkVersion(module: SdkInitModule): string {
  if (
    typeof module._rac_wasm_get_version_major !== 'function'
    || typeof module._rac_wasm_get_version_minor !== 'function'
    || typeof module._rac_wasm_get_version_patch !== 'function'
  ) {
    return SDK_VERSION;
  }

  try {
    const major = module._rac_wasm_get_version_major();
    const minor = module._rac_wasm_get_version_minor();
    const patch = module._rac_wasm_get_version_patch();
    if (major < 0 || minor < 0 || patch < 0) return SDK_VERSION;
    return `${major}.${minor}.${patch}`;
  } catch {
    return SDK_VERSION;
  }
}

function configureWebClientInfo(module: SdkInitModule): void {
  if (typeof module._rac_wasm_set_client_info !== 'function') return;

  const values = [
    'web',
    clientInfoValue(_initOptions?.appIdentifier)
      ?? (typeof location !== 'undefined' ? normalizeMetadataString(location.origin) : null),
    clientInfoValue(_initOptions?.appName) ?? browserDocumentTitle(),
    clientInfoValue(_initOptions?.appVersion),
    clientInfoValue(_initOptions?.appBuild),
    browserLocale(),
    browserTimezone(),
  ];
  const ptrs: number[] = [];
  try {
    for (const value of values) {
      if (!value) {
        ptrs.push(0);
        continue;
      }
      const bytes = module.lengthBytesUTF8(value) + 1;
      const ptr = module._malloc(bytes);
      module.stringToUTF8(value, ptr, bytes);
      ptrs.push(ptr);
    }
    module._rac_wasm_set_client_info(
      ptrs[0],
      ptrs[1],
      ptrs[2],
      ptrs[3],
      ptrs[4],
      ptrs[5],
      ptrs[6],
    );
  } finally {
    for (const ptr of ptrs) {
      if (ptr) module._free(ptr);
    }
  }
}

function throwIfSdkInitFailed(result: ProtoSdkInitResult | null, phase: string): void {
  if (!result) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
      `${phase} returned no sdk-init result.`,
    );
  }
  if (!result.success) {
    throw new SDKException(result.error ?? {
      category: 0,
      code: 0,
      cAbiCode: -ProtoErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
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
    platform: SDK_PLATFORM,
    sdkVersion: nativeSdkVersion(sdkModule),
  }).finish();

  const result = invokeSdkInitProto(
    sdkModule,
    bytes,
    sdkModule._rac_sdk_init_phase1_proto.bind(sdkModule),
    'rac_sdk_init_phase1_proto',
  );
  throwIfSdkInitFailed(result, 'SDK Phase 1');
  configureWebClientInfo(sdkModule);
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

/**
 * Optional extra args accepted by the Swift-shaped flat facade verbs that
 * mirror the cancellation contract Swift expresses through Task cancellation.
 * Mirrors the `{ signal?: AbortSignal }` shape already used by
 * `toolCalling.generateWithTools`.
 */
export interface CancellableCall {
  signal?: AbortSignal;
}

/**
 * Pre-check an AbortSignal before issuing a blocking native call. The Swift
 * source dispatches via `Task.checkCancellation()` at each suspension point;
 * the Web port can only short-circuit at the entry boundary because every
 * `_rac_*` invocation runs synchronously inside a single WASM worker tick.
 * Mirrors the eager-check pattern in `RunAnywhere+ToolCalling.ts`.
 */
function throwIfAborted(signal: AbortSignal | undefined, verb: string): void {
  if (signal?.aborted) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_GENERATION_CANCELLED,
      `${verb} cancelled`,
      'AbortSignal was already aborted before the call was invoked',
    );
  }
}

/**
 * Wire an AbortSignal into the synchronous WASM cancel ABI for a streaming
 * call: the cancel function is invoked on abort so commons stops pulling
 * more tokens. The returned cleanup detaches the listener. Suitable for
 * `generateStream` / `transcribeStream` / `synthesizeStream` / VLM stream.
 */
function attachSignalToCancel(
  signal: AbortSignal | undefined,
  cancel: () => void,
): () => void {
  if (!signal) return () => undefined;
  const onAbort = (): void => {
    try {
      cancel();
    } catch { /* best-effort; native cancel may not be wired yet */ }
  };
  signal.addEventListener('abort', onAbort);
  return () => signal.removeEventListener('abort', onAbort);
}

/**
 * Decode a TTSOutput's audio bytes into Float32 PCM samples suitable for
 * `AudioPlayback.play(...)`. Mirrors the Swift `RunAnywhere+TTS.swift`
 * `convertPCMToWAV` + AudioPlaybackManager pipeline: convert whatever the
 * engine produced into the audio-frame shape the platform player needs.
 *
 * The Web Audio API ultimately wants Float32 samples in [-1, 1]; we
 * interpret the engine bytes as follows:
 *   - `AUDIO_FORMAT_PCM`: typed Float32 native bytes (4-byte aligned), as
 *     produced by the sherpa TTS engines.
 *   - `AUDIO_FORMAT_PCM_S16LE`: signed 16-bit little-endian PCM; convert
 *     by normalizing to [-1, 1].
 *   - Any other (WAV/MP3/Opus/...): unsupported here without a decoder,
 *     return null so the caller can warn and continue.
 */
function decodeTTSAudioToFloat32(output: {
  audioFormat: AudioFormat;
  audioData: Uint8Array;
}): Float32Array | null {
  const bytes = output.audioData;
  if (!bytes || bytes.byteLength === 0) return null;
  switch (output.audioFormat) {
    case AudioFormat.AUDIO_FORMAT_PCM: {
      // Float32 native bytes — copy via a DataView read because the source
      // Uint8Array's byte offset is not guaranteed to be 4-aligned.
      const sampleCount = Math.floor(bytes.byteLength / 4);
      const out = new Float32Array(sampleCount);
      const view = new DataView(bytes.buffer, bytes.byteOffset, sampleCount * 4);
      for (let i = 0; i < sampleCount; i += 1) {
        out[i] = view.getFloat32(i * 4, true);
      }
      return out;
    }
    case AudioFormat.AUDIO_FORMAT_PCM_S16LE: {
      const usableBytes = bytes.byteLength - (bytes.byteLength % 2);
      const sampleCount = usableBytes / 2;
      const out = new Float32Array(sampleCount);
      const view = new DataView(bytes.buffer, bytes.byteOffset, usableBytes);
      for (let i = 0; i < sampleCount; i += 1) {
        out[i] = view.getInt16(i * 2, true) / 0x8000;
      }
      return out;
    }
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// Multi-file Download Helpers (Web / OPFS platform layer)
// ---------------------------------------------------------------------------

function isTarGzArchiveArtifact(model: ModelInfo): boolean {
  return model.artifactType === ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE;
}

function opfsModelDirectory(model: ModelInfo): string | null {
  const dir = frameworkOPFSDir(model.framework as InferenceFramework);
  if (!dir) return null;
  return `/opfs/RunAnywhere/Models/${dir}/${model.id}`;
}

/** Registry path after download/extract — archives hydrate as model dirs, not .tar.gz files. */
function registryLocalPathForDownload(model: ModelInfo, reportedPath: string): string {
  const modelDir = opfsModelDirectory(model);
  if (modelDir && isTarGzArchiveArtifact(model)) {
    return modelDir;
  }
  const isMultiFile = (model.multiFile?.files?.length ?? 0) > 1;
  if (modelDir && isMultiFile) {
    return modelDir;
  }
  return reportedPath;
}

async function resolveHydratedModelPath(
  model: ModelInfo,
  frameworkDir: string,
): Promise<{ exists: boolean; localPath: string }> {
  const modelDir = `/opfs/RunAnywhere/Models/${frameworkDir}/${model.id}`;
  const isMultiFile = (model.multiFile?.files?.length ?? 0) > 1;
  if (isMultiFile || isTarGzArchiveArtifact(model)) {
    const hasDir = await OPFSBridge.directoryHasArtifacts([
      'RunAnywhere',
      'Models',
      frameworkDir,
      model.id,
    ]);
    if (hasDir) {
      return { exists: true, localPath: modelDir };
    }
  }
  const filename = primaryFilenameFromModel(model);
  if (!filename) {
    return { exists: false, localPath: modelDir };
  }
  const opfsPath = `${modelDir}/${filename}`;
  const exists = await OPFSBridge.exists(opfsPath);
  return { exists, localPath: exists ? opfsPath : modelDir };
}

/**
 * Mirror a completed download into the user-visible model registry so
 * `getModel()` / `downloadedModels()` reflect on-disk state immediately.
 * Matches iOS `RunAnywhere+Storage.persistDownloadCompletion` → `importModel`.
 *
 * Self-heal inside the C++ download orchestrator may update only the
 * commons WASM's `s_model_registry`. `registerModel` broadcasts to every
 * known module via `ModelRegistryAdapter`.
 */
/**
 * Invoke one of the `rac_wasm_file_manager_clear_*` shims (wasm_exports.cpp)
 * on the commons-owning module. The shims build the rac_file_callbacks_t in
 * C++ against the module's own filesystem, so commons keeps ownership of the
 * Cache/Temp path computation and clear semantics.
 */
async function callWasmFileManagerClear(
  operation: 'clearCache' | 'cleanTempFiles',
  exportName: '_rac_wasm_file_manager_clear_cache' | '_rac_wasm_file_manager_clear_temp',
): Promise<void> {
  const module = getModuleForCapability('commons') ?? tryRunanywhereModule();
  const fn = (module as unknown as Record<string, (() => number) | undefined>)?.[exportName];
  if (!module || typeof fn !== 'function') {
    throw SDKException.backendNotAvailable(
      operation,
      `The loaded WASM artifact does not export ${exportName}; rebuild with ` +
        `sdk/runanywhere-web/scripts/build-core-wasm.sh to enable ${operation}.`,
    );
  }
  const rc = fn();
  if (rc !== 0) {
    throw SDKException.fromCode(rc, `${exportName} failed with code ${rc}`);
  }
}

function mirrorDownloadCompletionToRegistry(model: ModelInfo, localPath: string): void {
  const importedModel: ModelInfo = {
    ...model,
    localPath,
    isDownloaded: true,
    isAvailable: true,
    updatedAtUnixMs: Date.now(),
  };
  // Swift parity (RunAnywhere+Storage.swift persistDownloadCompletion):
  // route through the commons import path (ModelImportRequest →
  // rac_model_registry_import_proto) so C++ owns import semantics instead
  // of a bare registerModel write.
  const result = ModelRegistryCapability.importModel({
    model: importedModel,
    sourcePath: localPath,
    copyIntoManagedStorage: false,
    overwriteExisting: true,
    validateBeforeRegister: false,
    files: importedModel.multiFile?.files ?? [],
  });
  if (!result?.success) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
      result?.errorMessage
        ? result.errorMessage
        : 'Downloaded model could not be imported into the registry',
      'downloadModel',
    );
  }
}

/**
 * Reconcile the Web vision-language provider's private "loaded" flag with
 * the canonical C++ lifecycle state. Called from `loadModel` and
 * `unloadModel` so example app views never need to invoke
 * `RunAnywhere.visionLanguage.loadCurrentModel()` themselves.
 *
 * Both `.multimodal` and `.vision` categories collapse to
 * `SDK_COMPONENT_VLM` in C++ commons (same as iOS Swift); query both
 * before deciding the provider should be unloaded.
 *
 * Errors are swallowed because backend availability is allowed to lag
 * the lifecycle (e.g. LlamaCPP WASM still initializing). Real provider
 * failures will surface when `processImage` next runs.
 */
async function syncVisionLanguageProviderToLifecycle(): Promise<void> {
  try {
    const currentVLM =
      ModelLifecycleCapability.currentModel({
        category: ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        includeModelMetadata: true,
      }) ??
      ModelLifecycleCapability.currentModel({
        category: ModelCategory.MODEL_CATEGORY_VISION,
        includeModelMetadata: true,
      });

    const hasVLMModelLoaded = Boolean(currentVLM?.modelId);
    const providerReportsLoaded = VisionLanguageCapability.isModelLoaded;

    if (hasVLMModelLoaded && !providerReportsLoaded) {
      await VisionLanguageCapability.loadCurrentModel();
    } else if (!hasVLMModelLoaded && providerReportsLoaded) {
      await VisionLanguageCapability.unloadModel();
    }
  } catch (err) {
    if (err instanceof SDKException && err.code === ProtoErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE) {
      return;
    }
    logger.debug(
      `vision-language provider sync skipped: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}

/**
 * Plan a download and retry once after clearing oversize partial bytes.
 *
 * Mirrors Swift `RunAnywhere+Storage.planDownload(_:)`: when a prior
 * interrupted download left more bytes on disk than the new plan expects
 * (e.g. the server reported a smaller Content-Length after a CDN swap),
 * delete the oversize partials and re-plan instead of surfacing
 * `existing partial bytes exceed` to the caller as a hard error. Web partials
 * live in each module's MEMFS and in OPFS under the synthetic `/opfs/` prefix,
 * so the removal goes through `OPFSBridge.removeFile`.
 */
async function planDownloadWithSelfHeal(
  modelId: string,
  request: DownloadPlanRequest,
): Promise<DownloadPlanResult | null> {
  const plan = DownloadsCapability.plan(request);
  if (
    !plan ||
    plan.canStart ||
    plan.failureReason !== DownloadFailureReason.DOWNLOAD_FAILURE_REASON_OVERSIZE_PARTIAL_BYTES
  ) {
    return plan;
  }

  const modules = getAllRegisteredModules();
  for (const file of plan.files) {
    if (!file.destinationPath) continue;
    await OPFSBridge.removeFile(modules, file.destinationPath);
    logger.warning(
      `Removed oversize partial download at '${file.destinationPath}' for '${modelId}'`,
    );
  }

  return DownloadsCapability.plan(request);
}

// The previous in-TS multi-file
// orchestrator that walked `model.multiFile.files`, fetched each URL,
// wrote to OPFS, and mirrored to MEMFS used to live here. The commons C
// download orchestrator already drives the same flow via
// `rac_download_plan_proto` / `rac_download_start_proto` /
// `rac_download_progress_poll_proto` (the multi_file_plan branch in
// `download_orchestrator.cpp` writes the folder path back as
// `completion_local_path`), and the post-download
// `OPFSBridge.ensureDownloadPersisted` already detects directory artifacts
// and flushes them recursively into OPFS via `flushDirectoryFromMemfs`.
// Multi-file models now share the single canonical download codepath as
// every other framework SDK; nothing Web-specific belongs in the TS layer.

// ---------------------------------------------------------------------------
// HTTP retry (mirrors Swift retryHTTPSetup / RN retryHTTPSetupInternal)
// ---------------------------------------------------------------------------

/**
 * Retry HTTP/auth after an offline initialization. Commons owns the retry
 * orchestration (auth, device registration, telemetry flush); Web only
 * ensures the fetch-backed transport was registered with the active WASM.
 */
async function retryHTTPSetup(): Promise<void> {
  if (_hasCompletedHTTPSetup) return;
  const module = tryRunanywhereModule() as SdkInitModule | null;
  if (!module) return;

  if (typeof module._rac_sdk_retry_http_proto === 'function') {
    const result = invokeSdkResultProto(
      module,
      module._rac_sdk_retry_http_proto.bind(module),
      'rac_sdk_retry_http_proto',
    );
    throwIfSdkInitFailed(result, 'SDK HTTP retry');
    _hasCompletedHTTPSetup = result?.hasCompletedHttpSetup ?? result?.httpConfigured ?? false;
    if (result?.warning) {
      logger.debug(`HTTP/Auth retry warning: ${result.warning}`);
    }
    if (_hasCompletedHTTPSetup) {
      logger.info('HTTP/Auth setup succeeded on retry');
    }
    return;
  }

  // Backward compatibility for stale WASM artifacts that predate
  // rac_sdk_retry_http_proto. New builds export the commons-owned retry path.
  const authFn = module._rac_auth_is_authenticated;
  if (typeof authFn !== 'function') return;

  try {
    const authenticated = authFn.call(module) !== 0;
    if (authenticated) {
      _hasCompletedHTTPSetup = true;
      logger.info('HTTP/Auth setup succeeded on retry');
    }
  } catch {
    // Still offline or auth state unavailable — leave _hasCompletedHTTPSetup false.
  }
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
   * once a commons/backend module has installed it. Before any module loads,
   * no WASM module exists and the SDK cannot be authenticated — this returns false.
   *
   * Phase 2 owns auth/refresh in commons via the registered browser fetch
   * transport; this getter only reflects the current native auth state.
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
  // Initialization
  // =========================================================================

  /**
   * Initialize the RunAnywhere SDK.
   *
   * Web owns browser setup (logging, persisted storage, WASM/package loading,
   * OPFS/MEMFS hydration, fetch transport registration). Commons owns the
   * deterministic init phases once a WASM module is available.
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

        // Swift parity (RunAnywhere.swift performCoreInitSerial): set the
        // environment first so logging boots with the correct config
        // (dev=debug, prod=warning/local-off).
        SDKLogger.applyEnvironmentConfiguration(env);

        logger.info(`Initializing RunAnywhere Web SDK (${env})...`);

        if (typeof ReadableStream === 'undefined') {
          throw SDKException.fromCode(
            -ProtoErrorCode.ERROR_CODE_INITIALIZATION_FAILED,
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

        await requestPersistentStorage();

        // Load the core commons WASM so the SDK facade (init, environment,
        // auth, model registry, lifecycle, proto events) has its native
        // backing. Swift parity (RunAnywhere.swift performCoreInitSerial):
        // Phase 1 failure is fatal — initialize() rethrows and
        // `isInitialized` stays false.
        await CommonsModule.shared.ensureLoaded();

        _isInitialized = true;

        ensureDeviceId();

        logger.info('RunAnywhere Web SDK initialized successfully');
        EventBus.shared.publish('sdk.initialized', EventCategory.EVENT_CATEGORY_INITIALIZATION, {
          environment: env,
        });

        // Phase 2 (services) runs in the background so initialize() can
        // resolve before the WASM-backed services come up. A failure must
        // be observable to callers — surface it on the event bus and keep
        // `areServicesReady === false` so polling consumers can react.
        // The promise itself is intentionally fire-and-forget; consumers
        // who need to wait can call `RunAnywhere.completeServicesInitialization()`
        // (or `ensureServicesReady()`) directly and await the same promise.
        void RunAnywhere.completeServicesInitialization().catch((err) => {
          const message = err instanceof Error ? err.message : String(err);
          logger.warning(`Phase 2 init failed (non-fatal): ${message}`);
          EventBus.shared.publish(
            'sdk.initializationFailed',
            EventCategory.EVENT_CATEGORY_INITIALIZATION,
            { error: message, source: 'completeServicesInitialization' },
          );
        });

        // Hydrate any pre-existing OPFS-backed models registered before
        // `initialize()` returned, so the Storage tab paints the correct
        // "Downloaded" state on first render. Catalogs registered AFTER
        // `initialize()` resolves go through the new `registerModel(...)`
        // overloads, which schedule their own follow-up hydrate. This
        // call is idempotent and no-ops if the registry is empty.
        try {
          await RunAnywhere.hydrateModelRegistry();
        } catch (err) {
          logger.warning(
            `Initial model registry hydrate failed (non-fatal): ${err instanceof Error ? err.message : String(err)}`,
          );
        }
      } catch (error) {
        // Swift parity (RunAnywhere.swift performCoreInitSerial error path):
        // reset init state fully and rethrow so callers observe the failure.
        logger.error(
          `Initialization failed: ${error instanceof Error ? error.message : String(error)}`,
        );
        _isInitialized = false;
        _initOptions = null;
        _hasCompletedServicesInit = false;
        _hasCompletedHTTPSetup = false;
        _servicesInitPromise = null;
        throw error;
      } finally {
        _initializingPromise = null;
      }
    })();

    return _initializingPromise;
  },

  /**
   * Complete the Phase 2 (services) initialization. Mirror of Swift's
   * `RunAnywhere.completeServicesInitialization()`. Idempotent — concurrent
   * callers share a single in-flight promise. The promise is kept alive until
   * it either settles successfully (`_hasCompletedServicesInit = true`) or
   * throws, mirroring Swift's `_servicesInitLock` + `_servicesInitTask` join
   * pattern so two callers arriving concurrently never spawn duplicate Phase 2
   * work.
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

        let httpConfigured = false;
        if (typeof module._rac_sdk_init_phase2_proto === 'function') {
          const environment = _initOptions?.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
          const bytes = SdkInitPhase2Request.encode({
            buildToken: environment === SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
              ? (_initOptions?.buildToken ?? '')
              : '',
            forceRefreshAssignments: false,
            flushTelemetry: true,
            discoverDownloadedModels: true,
            rescanLocalModels: true,
          }).finish();
          const result = invokeSdkInitProto(
            module,
            bytes,
            module._rac_sdk_init_phase2_proto.bind(module),
            'rac_sdk_init_phase2_proto',
          );
          throwIfSdkInitFailed(result, 'SDK Phase 2');
          httpConfigured = result?.hasCompletedHttpSetup ?? result?.httpConfigured ?? false;
          const linkedModelsCount = result?.linkedModelsCount ?? 0;
          if (linkedModelsCount > 0) {
            logger.info(`Phase 2 linked ${linkedModelsCount} downloaded models`);
          }
        } else {
          logger.warning(
            'WASM module missing _rac_sdk_init_phase2_proto; services init remains browser-only until rebuild.',
          );
        }

        _hasCompletedServicesInit = true;
        _hasCompletedHTTPSetup = httpConfigured;
        if (httpConfigured) {
          logger.debug('Services initialization complete (Phase 2)');
        } else {
          logger.debug('Services initialization complete (Phase 2, HTTP/auth deferred — will retry on next online call)');
        }
      } catch (err) {
        // Clear the promise on failure so a subsequent retry can re-enter.
        _servicesInitPromise = null;
        throw err;
      }
      // Success path: leave _servicesInitPromise set so any late concurrent
      // caller that reads it after _hasCompletedServicesInit flips true still
      // gets a resolved promise rather than re-entering the init logic.
    })();
    return _servicesInitPromise;
  },

  /**
   * Internal-style guard used by extensions that need a fully-initialized SDK.
   * Three-branch mirror of Swift's ensureServicesReady():
   *   1. Fast path: services + HTTP both done → return immediately.
   *   2. Recovery path: services done, HTTP failed (offline init) → retry HTTP only.
   *   3. Cold-start path: Phase 2 not yet run → completeServicesInitialization().
   */
  async ensureServicesReady(): Promise<void> {
    if (_hasCompletedServicesInit && _hasCompletedHTTPSetup) {
      return;
    }
    if (_hasCompletedServicesInit && !_hasCompletedHTTPSetup) {
      await retryHTTPSetup();
      return;
    }
    return RunAnywhere.completeServicesInitialization();
  },

  // =========================================================================
  // Storage namespace
  //
  // Intentionally PUBLIC despite having no Swift namespace counterpart:
  // File System Access API / OPFS directory selection, persistence restore,
  // and backend probing are genuinely Web-platform surface (the browser is
  // the only platform where the host must ask the user for a persistent
  // filesystem), so this stays a web-justified namespace rather than being
  // folded into the Swift-shaped flat facade.
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
        EventBus.shared.publish('storage.localDirectorySelected', EventCategory.EVENT_CATEGORY_STORAGE, {
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
  //
  // The raw download / model-registry proto bridges (`Downloads`,
  // `ModelRegistry`) are NOT exposed here — Swift keeps its CppBridge
  // internal, and the canonical cross-SDK surface is the flat verbs
  // (`downloadModel` / `downloadModelStream` / `listModels` / `queryModels` /
  // `getModel` / `downloadedModels` / `importModel` / `refreshModelRegistry`).
  // Backend packages reach the bridge objects via `@runanywhere/web/internal`.
  // =========================================================================

  /** C++ SDKEvent proto stream — subscribe/publish/poll/failure. */
  sdkEvents: SDKEventsCapability,

  // Cross-SDK lifecycle surface is the four top-level flat verbs below
  // (`loadModel` / `unloadModel` / `currentModel` /
  // `componentLifecycleSnapshot`), mirroring Swift's source-of-truth shape.
  // Web's extra OPFS/MEMFS helpers live on the internal `WebModelLifecycle`
  // namespace and are NOT exposed here; if cross-SDK code needs `isLoaded`,
  // `isComponentReady`, `unloadAllModels`, `loadModelAsync`, etc., they
  // must be promoted to the canonical contract in Swift first.

  /** Text generation — `RunAnywhere.textGeneration.generate(options)` etc. */
  textGeneration: TextGenerationCapability,

  /** Web-only structured-output extras (export probe + raw proto primitives).
   * Generation itself is the flat Swift-named `RunAnywhere.generateStructured`
   * / `generateStructuredStream`. */
  structuredOutput: StructuredOutputCapability,

  /** Tool calling — `RunAnywhere.toolCalling.generate(prompt, tools)` */
  toolCalling: ToolCallingCapability,

  /** Speech-to-text — `RunAnywhere.stt.create()` / `transcribe(handle, audio)` etc. */
  stt: STTCapability,

  /** Text-to-speech — `RunAnywhere.tts.create()` / `synthesize(handle, text)` etc. */
  tts: TTSCapability,

  /** Voice activity detection — `RunAnywhere.vad.create()` / `process(handle, samples)` etc. */
  vad: VADCapability,

  /** Logging control — `RunAnywhere.logging.setLevel(LogLevel.LOG_LEVEL_DEBUG)` */
  logging: LoggingCapability,

  /** LoRA adapter management — `RunAnywhere.lora.apply(request)` etc. */
  lora: LoRACapability,

  /** Web-only RAG extras (provider wiring, availability, document list/remove).
   * Pipeline operations are the flat Swift-named verbs (`ragCreatePipeline`,
   * `ragIngest`, `ragQuery`, ...). */
  rag: RAGCapability,

  /** Embeddings generation — `RunAnywhere.embeddings.embed('text', {modelID})` etc. */
  embeddings: EmbeddingsCapability,

  /** Web-only voice-agent extras (availability/readiness probes, provider
   * sub-operations). Orchestration is the flat Swift-named verbs
   * (`initializeVoiceAgent`, `processVoiceTurn`, `streamVoiceAgent`, ...). */
  voiceAgent: VoiceAgentCapability,

  /** Vision-language model inference — `RunAnywhere.visionLanguage.processImage(...)`. */
  visionLanguage: VisionLanguageCapability,

  /** Model-registry proto bridge — `RunAnywhere.modelRegistry.registerModel(model)`
   * etc. (documented public namespace; the flat Swift-named verbs
   * `registerModel`/`listModels`/`refreshModelRegistry` delegate to it). */
  modelRegistry: ModelRegistryCapability,

  /** Hybrid STT router — `RunAnywhere.hybrid.createSttRouter()` etc. Per-request
   * offline(sherpa)↔online(cloud) dispatch; commons owns all routing. */
  hybrid: HybridCapability,

  /** Runtime plugin loader — unavailable on plain WASM unless host exports the ABI. */
  pluginLoader: PluginLoaderCapability,

  /**
   * Backend availability snapshots — `RunAnywhere.backends.onnxStatus()`
   * etc. Returns build-flag-free reasons that example apps can render
   * directly without leaking CMake symbol names into the UI.
   */
  backends: BackendsCapability,

  // =========================================================================
  // Swift-shaped flat facade
  //
  // Pure-delegate forwarding methods live in RunAnywhere+FlatFacade.ts and
  // are spread below. Methods with real orchestration logic (VLM lifecycle
  // sync, AbortSignal wiring, async generator wrapping, audio playback) are
  // implemented here where they can access module-scoped state and helpers.
  // =========================================================================

  ...flatFacade,

  async loadModel(
    request: Parameters<typeof ModelLifecycleCapability.loadModel>[0],
  ): Promise<Awaited<ReturnType<typeof ModelLifecycleCapability.loadModelAsync>>> {
    await RunAnywhere.ensureServicesReady();
    const result = await ModelLifecycleCapability.loadModelAsync(request);
    // VLM lifecycle mirror: when the loaded model is multimodal/vision and a
    // Web vision-language provider is registered, automatically populate
    // its private `_modelLoaded` flag against the lifecycle-resolved
    // current model. Without this, app code had to call
    // `RunAnywhere.visionLanguage.loadCurrentModel()` itself after every
    // load — the SDK now owns that coupling so example views stay free
    // of SDK-internal lifecycle bridge calls.
    if (result?.success) {
      await syncVisionLanguageProviderToLifecycle();
    }
    return result;
  },

  async unloadModel(
    request: Parameters<typeof ModelLifecycleCapability.unloadModel>[0],
  ): Promise<Awaited<ReturnType<typeof ModelLifecycleCapability.unloadModelAsync>>> {
    const result = await ModelLifecycleCapability.unloadModelAsync(request);
    // Symmetric to loadModel above: drop the VLM provider's loaded flag
    // when the lifecycle no longer reports a current VLM model so the
    // next processImage call surfaces "no model loaded" instead of
    // dispatching against a stale provider handle.
    if (result?.success) {
      await syncVisionLanguageProviderToLifecycle();
    }
    return result;
  },

  async downloadModel(
    input: string | DownloadModelOptions,
    extra: CancellableCall = {},
  ): Promise<DownloadProgress> {
    throwIfAborted(extra.signal, 'downloadModel');
    await RunAnywhere.ensureServicesReady();
    const request = typeof input === 'string' ? { modelId: input } : input;
    const model = request.model ?? ModelRegistryCapability.getModel(request.modelId) ?? undefined;
    if (!model) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        `Model metadata for '${request.modelId}' is not registered.`,
      );
    }

    // Multi-file models (VLM = primary GGUF + mmproj
    // sidecar, embeddings = model.onnx + vocab.txt) now flow through the
    // same canonical plan/start/poll path. The C++ orchestrator's
    // multi_file_plan branch reports the folder path as
    // `completion_local_path`, and `OPFSBridge.ensureDownloadPersisted`
    // recursively flushes the directory contents to OPFS + mirrors them
    // into every module's MEMFS. No Web-specific orchestrator below.

    await prepareModelLoad({
      request: {
        modelId: request.modelId,
        category: model.category,
        framework: model.framework,
      },
      model,
    });
    ModelRegistryCapability.registerModel(model);

    // Plan defaults mirror Swift RunAnywhere+Storage.swift:187-189:
    // resumeExisting=true, validateExistingBytes=true,
    // verifyChecksums=!checksum.isEmpty.
    const planRequest = {
      modelId: request.modelId,
      model,
      resumeExisting: request.resumeExisting ?? true,
      availableStorageBytes: request.availableStorageBytes ?? 0,
      allowMeteredNetwork: request.allowMeteredNetwork ?? true,
      storageNamespace: request.storageNamespace ?? '',
      validateExistingBytes: request.validateExistingBytes ?? true,
      verifyChecksums:
        request.verifyChecksums ?? (model.checksumSha256?.length ?? 0) > 0,
      requiredFreeBytesAfterDownload: request.requiredFreeBytesAfterDownload ?? 0,
    };
    const plan = await planDownloadWithSelfHeal(request.modelId, planRequest);
    if (!plan?.canStart) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        plan?.errorMessage || `Download plan for '${request.modelId}' could not start.`,
      );
    }

    // Swift parity (RunAnywhere+Storage.swift:207-210): commons does NOT
    // update the registry on completion; the explicit import below
    // (mirrorDownloadCompletionToRegistry — Web's RAModelImportRequest
    // equivalent) is the canonical persistence step, run after the OPFS
    // flush. Callers may still opt out via updateRegistryOnCompletion=false.
    const start = DownloadsCapability.start({
      modelId: request.modelId,
      plan,
      resume: request.resumeExisting ?? true,
      resumeToken: plan.resumeToken,
      updateRegistryOnCompletion: false,
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

    // Mirror Swift's `cancelNativeDownload(taskID:modelID:)`: wire the
    // AbortSignal so rac_download_cancel_proto fires with deletePartialBytes=false
    // (preserves resume tokens). Detach the listener in the finally block.
    const detachCancel = attachSignalToCancel(extra.signal, () => {
      DownloadsCapability.cancel({
        modelId: request.modelId,
        taskId: start.taskId,
        deletePartialBytes: false,
      });
    });

    let lastProgress = start.initialProgress;
    // Suppress COMPLETED here for the same reason as the poll loop below:
    // a cached download whose `start.initialProgress` is already COMPLETED
    // would otherwise produce two onProgress callbacks (one here, one after
    // the OPFS flush below). The single post-flush emit at the bottom of
    // downloadModel() is the canonical "download done" signal.
    if (lastProgress && lastProgress.state !== DownloadState.DOWNLOAD_STATE_COMPLETED) {
      request.onProgress?.(lastProgress);
    }

    try {
      while (!lastProgress || !terminal.has(lastProgress.state)) {
        throwIfAborted(extra.signal, 'downloadModel');
        await delay(request.pollIntervalMs ?? 250);
        const progress = DownloadsCapability.poll({
          modelId: request.modelId,
          taskId: start.taskId,
        });
        if (!progress) continue;
        lastProgress = progress;
        // Defer COMPLETED to onProgress until OPFS flush finishes.
        // UI/E2E often triggers loadModel on COMPLETED; firing it early races
        // the async MEMFS→OPFS persist that follows the poll loop.
        if (progress.state !== DownloadState.DOWNLOAD_STATE_COMPLETED) {
          request.onProgress?.(progress);
        }
      }
    } finally {
      detachCancel();
    }

    if (lastProgress.state !== DownloadState.DOWNLOAD_STATE_COMPLETED) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        lastProgress.errorMessage || `Download for '${request.modelId}' ended in state ${lastProgress.state}.`,
      );
    }

    // OPFS persistence: the C++ download orchestrator wrote
    // bytes via `std::ofstream` which on Emscripten lands on MEMFS — an
    // in-memory filesystem invisible to `navigator.storage.estimate()` and
    // destroyed on tab reload. Flush the freshly-written file into the
    // Origin Private File System so the download actually persists.
    //
    // Architectural note: on iOS / Android / desktop the SDKs do nothing
    // here because libc maps `std::ofstream` to the real filesystem.
    // Web's responsibility — per the platform-adapter IoC contract — is to
    // back the synthetic `/opfs/` prefix with a real persistent
    // filesystem. We do that here at the TS layer (no WASM rebuild) by
    // mirroring MEMFS → OPFS once the download completes.
    if (lastProgress.localPath) {
      const downloaderModule = getModuleForCapability('commons')
        ?? tryRunanywhereModule();
      const allModules = getAllRegisteredModules();
      if (downloaderModule) {
        try {
          await OPFSBridge.ensureDownloadPersisted(
            lastProgress.localPath,
            downloaderModule,
            allModules,
          );
        } catch (err) {
          throw SDKException.fromCode(
            -ProtoErrorCode.ERROR_CODE_STORAGE_ERROR,
            err instanceof Error ? err.message : String(err),
            'downloadModel',
          );
        }
      }
    }

    // Single canonical COMPLETED emit: both the start.initialProgress
    // branch and the poll loop intentionally suppress COMPLETED so the only
    // place this fires is HERE, AFTER OPFSBridge.ensureDownloadPersisted has
    // resolved. UI/E2E observers gate loadModel on this; firing earlier races
    // the MEMFS→OPFS persist.
    request.onProgress?.(lastProgress);

    // Self-heal may only update the commons WASM registry. Mirror
    // localPath + isDownloaded into every module so harness/UI polls succeed.
    if (request.updateRegistryOnCompletion !== false && lastProgress.localPath) {
      try {
        const registryPath = registryLocalPathForDownload(model, lastProgress.localPath);
        mirrorDownloadCompletionToRegistry(model, registryPath);
      } catch (err) {
        logger.debug(
          `post-download registry mirror failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
    return lastProgress;
  },

  /**
   * Stream download progress for a registered model. Mirrors Swift's
   * `downloadModelStream(_:)` (RunAnywhere+Storage.swift:263) — a thin
   * async-iterable over the callback-based `downloadModel`. Consumer
   * cancellation (break / `return()`) cancels the in-flight download,
   * matching Swift's `onTermination == .cancelled` branch.
   */
  downloadModelStream(
    input: string | DownloadModelOptions,
    extra: CancellableCall = {},
  ): AsyncIterable<DownloadProgress> {
    return (async function* downloadProgressStream(): AsyncGenerator<DownloadProgress> {
      const queue: DownloadProgress[] = [];
      let notify: (() => void) | null = null;
      let done = false;
      let failure: unknown = null;
      const controller = new AbortController();
      const detachOuter = attachSignalToCancel(extra.signal, () => controller.abort());
      const request = typeof input === 'string' ? { modelId: input } : { ...input };
      const callerOnProgress = request.onProgress;

      const downloadPromise = RunAnywhere.downloadModel(
        {
          ...request,
          onProgress: (progress) => {
            callerOnProgress?.(progress);
            queue.push(progress);
            notify?.();
          },
        },
        { signal: controller.signal },
      ).then(
        () => {
          done = true;
          notify?.();
        },
        (err: unknown) => {
          failure = err;
          done = true;
          notify?.();
        },
      );

      try {
        for (;;) {
          while (queue.length > 0) {
            yield queue.shift()!;
          }
          if (done) break;
          await new Promise<void>((resolve) => {
            notify = resolve;
          });
          notify = null;
        }
        if (failure) throw failure;
        await downloadPromise;
      } finally {
        detachOuter();
        if (!done) {
          controller.abort();
        }
      }
    })();
  },

  /**
   * Scan the Origin Private File System for models that were downloaded in a
   * previous session and update the C++ registry's `localPath` for any
   * that are found on disk but not yet reflected in the in-memory registry.
   *
   * Call this once after backends register and the model catalog is
   * populated, to restore the "Downloaded" status across tab reloads.
   *
   * Returns the number of registry entries patched.
   *
   * TODO(layering): the positive-link branch (mark isDownloaded=true when the
   * canonical OPFS path exists) is now largely redundant with the C++ adapter
   * rescan that `rac_model_registry_refresh_proto` runs via the registered
   * `file_list_directory` slot. The piece C++ does NOT yet cover is the
   * negative reconciliation below (clear isDownloaded when OPFS bytes were
   * purged) — the commons `prune_orphans` path is still a documented no-op.
   * Once a C++ orphan-prune lands, this can be retired entirely. Do not
   * delete until then.
   */
  async hydrateModelRegistry(): Promise<number> {
    const list = ModelRegistryCapability.listModels();
    if (!list?.models?.length) return 0;

    let patched = 0;
    for (const model of list.models) {
      const existing = ModelRegistryCapability.getModel(model.id);
      if (!existing) continue;

      const dir = frameworkOPFSDir(existing.framework as InferenceFramework);
      if (!dir) continue;

      const { exists, localPath } = await resolveHydratedModelPath(existing, dir);

      // clearSiteStorage (or manual OPFS purge)
      // wipes bytes but the registry can still report isDownloaded=true from
      // a prior session. Reconcile: if the canonical OPFS path is gone, clear
      // the flag so the next downloadModel() re-fetches instead of no-oping.
      if (!exists) {
        if (existing.localPath || existing.isDownloaded) {
          try {
            ModelRegistryCapability.updateModel({ ...existing, localPath: '', isDownloaded: false });
            patched++;
          } catch { /* ignore */ }
        }
        continue;
      }

      if (existing.localPath && existing.isDownloaded) continue;

      try {
        ModelRegistryCapability.updateModel({ ...existing, localPath, isDownloaded: true });
        patched++;
      } catch { /* ignore */ }
    }
    if (patched > 0) {
      // Notify UI subscribers (Storage tab, model
      // sheet) so they re-query the registry and render Downloaded/Load
      // instead of Download after a fresh page load.
      EventBus.shared.publish(
        'models.hydrated',
        EventCategory.EVENT_CATEGORY_STORAGE,
        { count: patched },
      );
    }
    return patched;
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

  deleteModel(
    modelId: string,
  ): ReturnType<ReturnType<typeof createStorageNamespace>['deleteModel']> {
    return RunAnywhere.storage.deleteModel(modelId);
  },

  /**
   * Clear the SDK's Cache directory. Mirrors Swift `clearCache()`
   * (RunAnywhere+Storage.swift:305-313): init guard + ensureServicesReady,
   * then the commons file manager clears {base}/RunAnywhere/Cache
   * (delete-recursive + recreate) via the `rac_wasm_file_manager_clear_cache`
   * shim. Platform note: on Web that directory lives in the commons module's
   * volatile MEMFS — OPFS is untouched by design (cache/temp are never
   * flushed there; OPFS reclamation is `deleteStorage`/`storage.delete`).
   * Throws backendNotAvailable against older WASM artifacts without the shim.
   */
  async clearCache(): Promise<void> {
    await RunAnywhere.ensureServicesReady();
    await callWasmFileManagerClear('clearCache', '_rac_wasm_file_manager_clear_cache');
  },

  /**
   * Clear the SDK's Temp directory. Mirrors Swift `cleanTempFiles()`
   * (RunAnywhere+Storage.swift:315-325); same platform semantics as
   * [clearCache].
   */
  async cleanTempFiles(): Promise<void> {
    await RunAnywhere.ensureServicesReady();
    await callWasmFileManagerClear('cleanTempFiles', '_rac_wasm_file_manager_clear_temp');
  },

  async generate(
    options: Parameters<typeof TextGenerationCapability.generate>[0],
    extra: CancellableCall = {},
  ): ReturnType<typeof TextGenerationCapability.generate> {
    throwIfAborted(extra.signal, 'generate');
    await RunAnywhere.ensureServicesReady();
    // Mirror Swift's Task cancellation: bridge the abort signal to commons
    // cancelGeneration so the synchronous WASM call returns early.
    const detach = attachSignalToCancel(extra.signal, () => TextGenerationCapability.cancelGeneration());
    return TextGenerationCapability.generate(options).finally(detach);
  },

  async generateStream(
    options: Parameters<typeof TextGenerationCapability.generateStream>[0],
    extra: CancellableCall = {},
  ): Promise<Awaited<ReturnType<typeof TextGenerationCapability.generateStream>>> {
    throwIfAborted(extra.signal, 'generateStream');
    await RunAnywhere.ensureServicesReady();
    const stream = await TextGenerationCapability.generateStream(options);
    const detach = attachSignalToCancel(extra.signal, () => stream.cancel());
    void stream.result.finally(detach);
    return stream;
  },

  transcribeStream(
    handle: Parameters<typeof STTCapability.transcribeStream>[0],
    audio: Parameters<typeof STTCapability.transcribeStream>[1],
    options: Parameters<typeof STTCapability.transcribeStream>[2],
    extra: CancellableCall = {},
  ): ReturnType<typeof STTCapability.transcribeStream> {
    throwIfAborted(extra.signal, 'transcribeStream');
    const iterable = STTCapability.transcribeStream(handle, audio, options);
    if (!extra.signal) return iterable;
    const signal = extra.signal;
    return (async function* () {
      for await (const partial of iterable) {
        throwIfAborted(signal, 'transcribeStream');
        yield partial;
      }
    })();
  },

  synthesizeStream(
    handle: Parameters<typeof TTSCapability.synthesizeStream>[0],
    text: Parameters<typeof TTSCapability.synthesizeStream>[1],
    options: Parameters<typeof TTSCapability.synthesizeStream>[2],
    extra: CancellableCall = {},
  ): ReturnType<typeof TTSCapability.synthesizeStream> {
    throwIfAborted(extra.signal, 'synthesizeStream');
    const iterable = TTSCapability.synthesizeStream(handle, text, options);
    if (!extra.signal) return iterable;
    const detach = attachSignalToCancel(extra.signal, () => TTSCapability.stop(handle));
    return (async function* () {
      try {
        yield* iterable;
      } finally {
        detach();
      }
    })();
  },

  async speak(
    ...args: Parameters<typeof TTSCapability.synthesizeAuto>
  ): Promise<TTSSpeakResult> {
    const output = await TTSCapability.synthesizeAuto(...args);
    // Swift parity: speak() must actually play the synthesized audio through
    // the default device speakers. AudioPlayback expects Float32Array PCM
    // samples; convert from the proto AudioFormat as needed. Failure to
    // play audio is non-fatal — return the synthesis result either way so
    // callers can still inspect timings / format metadata.
    if (output.audioData && output.audioData.byteLength > 0) {
      try {
        const samples = decodeTTSAudioToFloat32(output);
        if (samples && samples.length > 0) {
          // Shared playback instance (Swift parity: `ttsAudioPlayback`
          // singleton) so `stopSpeaking()` can stop in-flight speech.
          await sharedTTSPlayback().play(
            samples,
            output.sampleRate > 0 ? output.sampleRate : 22050,
          );
        }
      } catch (err) {
        logger.warning(
          `speak(): audio playback failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
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

  async *streamVAD(
    audio: AsyncIterable<Parameters<typeof VADCapability.detectVoiceAuto>[0]>,
    options?: Parameters<typeof VADCapability.detectVoiceAuto>[1],
  ): AsyncIterable<Awaited<ReturnType<typeof VADCapability.detectVoiceAuto>>> {
    for await (const chunk of audio) {
      yield await VADCapability.detectVoiceAuto(chunk, options);
    }
  },

  async processImage(
    image: VLMImage,
    options: VLMGenerationOptions,
    extra: CancellableCall = {},
  ): Promise<VLMResult> {
    throwIfAborted(extra.signal, 'processImage');
    if (!VisionLanguageCapability.isModelLoaded) {
      await VisionLanguageCapability.loadCurrentModel();
    }
    const detach = attachSignalToCancel(
      extra.signal,
      () => { void VisionLanguageCapability.cancelVLMGeneration(); },
    );
    return VisionLanguageCapability.processImage(image, options).finally(detach);
  },

  // Explicit overloads (the capability function is overloaded; deriving the
  // param types via Parameters<> would collapse to the LAST overload and
  // reject VLMGenerationOptions at the facade).
  async processImageStream(
    image: VLMImage,
    optionsOrPrompt: VLMGenerationOptions | string,
    maybeOptionsOrExtra?: VLMGenerationOptions | CancellableCall,
    maybeExtra: CancellableCall = {},
  ): Promise<AsyncIterable<VLMStreamEvent>> {
    const promptForm = typeof optionsOrPrompt === 'string';
    const extra: CancellableCall = promptForm
      ? maybeExtra
      : ((maybeOptionsOrExtra as CancellableCall | undefined) ?? {});
    throwIfAborted(extra.signal, 'processImageStream');
    if (!VisionLanguageCapability.isModelLoaded) {
      await VisionLanguageCapability.loadCurrentModel();
    }
    const stream = promptForm
      ? await VisionLanguageCapability.processImageStream(
        image,
        optionsOrPrompt,
        maybeOptionsOrExtra as VLMGenerationOptions | undefined,
      )
      : await VisionLanguageCapability.processImageStream(image, optionsOrPrompt);
    attachSignalToCancel(
      extra.signal,
      () => { void VisionLanguageCapability.cancelVLMGeneration(); },
    );
    return stream;
  },

  // =========================================================================
  // Shutdown
  // =========================================================================

  async shutdown(): Promise<void> {
    logger.info('Shutting down RunAnywhere Web SDK...');

    // Clear every WASM adapter singleton that `setRunanywhereModule()`
    // installed (DownloadAdapter, ModelLifecycleAdapter,
    // ModelRegistryAdapter, ModalityProtoAdapter, SDKEventStreamAdapter)
    // and null the global module so post-shutdown calls into
    // ModalityProtoAdapter / tryRunanywhereModule()
    // can't acquire stale references to a torn-down backend.
    clearRunanywhereModule();
    // HTTPAdapter and StorageAdapter are owned outside setRunanywhereModule(),
    // so they must be cleared explicitly to complete the ownership boundary.
    HTTPAdapter.clearDefaultModule();
    StorageAdapter.clearDefaultHandles();

    // Tear down the Worker streaming pipeline. The WASM ownership boundary
    // is `clearRunanywhereModule()`, but the Worker singletons
    // (`OffscreenRuntimeBridge._instance`, `_init` payload, and the
    // `StreamWorkerFactoryRegistry._factory`) live outside that
    // boundary. Without explicit teardown the spawned worker keeps its
    // mirror Emscripten module + loaded model weights alive across
    // logout / account-switch / test reset, and the next `initialize()`
    // would reuse the stale bridge.
    try {
      OffscreenRuntimeBridge.disposeShared();
    } catch (err) {
      logger.warning(`OffscreenRuntimeBridge.disposeShared threw during shutdown: ${String(err)}`);
    }
    setStreamWorkerFactory(null);
    setStreamWorkerInit(null);

    EventBus.reset();

    _isInitialized = false;
    _initOptions = null;
    _initializingPromise = null;
    _localFileStorage = null;
    _hasCompletedNativePhase1 = false;
    _hasCompletedServicesInit = false;
    _hasCompletedHTTPSetup = false;
    _servicesInitPromise = null;

    logger.info('RunAnywhere Web SDK shut down');
  },

  reset(): Promise<void> {
    return RunAnywhere.shutdown();
  },
};

// Install the post-register hydrate hook so the high-level
// `RunAnywhere.registerModel*(...)` overloads in `RunAnywhere+Storage.ts`
// automatically reconcile OPFS-backed model state with the freshly-added
// catalog entry. Fire-and-forget — `hydrateModelRegistry()` is idempotent
// and logs its own failures.
setRegisterModelHydrateHook(() => {
  void RunAnywhere.hydrateModelRegistry().catch((err) => {
    logger.debug(
      `post-register hydrate failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  });
});
