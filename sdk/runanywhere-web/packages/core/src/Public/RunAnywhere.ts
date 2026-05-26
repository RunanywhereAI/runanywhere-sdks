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
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  AudioFormat,
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
import { requestPersistentStorage } from '../Infrastructure/BrowserStorage';
import { LocalFileStorage } from '../Infrastructure/LocalFileStorage';
import { OPFSBridge } from '../Infrastructure/OPFSBridge';
import { AudioPlayback } from '../Infrastructure/AudioPlayback';
import {
  frameworkOPFSDir,
  primaryFilenameFromModel,
} from '../Infrastructure/FrameworkOPFSPaths';
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
import { Backends as BackendsCapability } from './Extensions/Backends/onnxStatus';
import {
  createStorageNamespace,
  registerModelArchive as registerModelArchiveImpl,
  registerModelFromUrl,
  registerModelMultiFile as registerModelMultiFileImpl,
  setRegisterModelHydrateHook,
  type RegisterModelOptions,
  type RegisterMultiFileOptions,
} from './Extensions/RunAnywhere+Storage';
import { disposeSpeechProvider } from './Extensions/SpeechProvider';
import { StorageAdapter } from '../Adapters/StorageAdapter';
import { HTTPAdapter } from '../Adapters/HTTPAdapter';
import { SDK_VERSION } from '../Foundation/Version';
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
      SDKErrorCode.GenerationCancelled,
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
 *   - `AUDIO_FORMAT_PCM`: typed Float32 native bytes (4-byte aligned). This
 *     is what the standalone Sherpa SpeechProvider produces.
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

async function fetchFileBytes(
  url: string,
  onProgress?: (loaded: number) => void,
): Promise<Uint8Array> {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`fetch(${url}) returned HTTP ${response.status}`);
  }
  const reader = response.body?.getReader();
  if (!reader) {
    const buf = new Uint8Array(await response.arrayBuffer());
    onProgress?.(buf.byteLength);
    return buf;
  }
  const chunks: Uint8Array[] = [];
  let received = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value) {
      chunks.push(value);
      received += value.byteLength;
      onProgress?.(received);
    }
  }
  const out = new Uint8Array(received);
  let off = 0;
  for (const c of chunks) { out.set(c, off); off += c.byteLength; }
  return out;
}

/**
 * Mirror a completed download into the user-visible model registry so
 * `getModel()` / `downloadedModels()` reflect on-disk state immediately.
 * Matches iOS `RunAnywhere+Storage.persistDownloadCompletion` → `importModel`.
 *
 * CPP-02 self-heal inside the C++ download orchestrator may update only the
 * commons WASM's `s_model_registry`. `registerModel` broadcasts to every
 * known module via `ModelRegistryAdapter`.
 */
function mirrorDownloadCompletionToRegistry(model: ModelInfo, localPath: string): void {
  const importedModel: ModelInfo = {
    ...model,
    localPath,
    isDownloaded: true,
    isAvailable: true,
    updatedAtUnixMs: Date.now(),
  };
  ModelRegistryCapability.registerModel(importedModel);
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
    if (err instanceof SDKException && err.code === SDKErrorCode.BackendNotAvailable) {
      return;
    }
    logger.debug(
      `vision-language provider sync skipped: ${err instanceof Error ? err.message : String(err)}`,
    );
  }
}

async function downloadMultiFileModel(
  request: DownloadModelOptions,
  model: ModelInfo,
  onProgress?: (progress: DownloadProgress) => void,
): Promise<DownloadProgress> {
  const files = model.multiFile?.files ?? [];
  const frameworkDir = frameworkOPFSDir(model.framework as InferenceFramework);
  if (!frameworkDir) {
    throw new Error(`Multi-file download: unsupported framework ${model.framework}`);
  }

  const folderSegments = ['RunAnywhere', 'Models', frameworkDir, request.modelId];
  const opfsFolder = `/opfs/${folderSegments.join('/')}`;
  const totalBytes = files.reduce((s, f) => s + (f.sizeBytes || 0), 0);
  let downloadedBytes = 0;

  const allModules = getAllRegisteredModules();

  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    if (!file.url || !file.filename) continue;

    const bytes = await fetchFileBytes(file.url, (loaded) => {
      const overall = totalBytes > 0 ? (downloadedBytes + loaded) / totalBytes : 0;
      onProgress?.({
        modelId: request.modelId,
        state: DownloadState.DOWNLOAD_STATE_DOWNLOADING,
        overallProgress: Math.min(1, overall),
        bytesDownloaded: downloadedBytes + loaded,
        totalBytes,
        stageProgress: overall,
        overallSpeedBps: 0,
        etaSeconds: -1,
        retryAttempt: 0,
        errorMessage: '',
        taskId: '',
        stage: i,
        currentFileIndex: i,
        totalFiles: files.length,
        storageKey: '',
        localPath: '',
        startedAtUnixMs: 0,
        updatedAtUnixMs: Date.now(),
        currentFileName: file.filename,
        resumeToken: '',
      });
    });

    downloadedBytes += bytes.byteLength;

    // Persist to OPFS
    await OPFSBridge.writeFileToOPFS([...folderSegments, file.filename], bytes);

    // Mirror into every backend MEMFS so immediate loadModel works
    const filePath = `${opfsFolder}/${file.filename}`;
    if (allModules.length > 0) {
      await OPFSBridge.restoreToMemfsAll(allModules, filePath);
      if (OPFSBridge.maxMemfsFileSizeAcrossModules(allModules, filePath) === 0) {
        throw SDKException.fromCode(
          SDKErrorCode.StorageError,
          `Multi-file persist failed: '${filePath}' has 0 bytes in MEMFS`,
          'downloadModel',
        );
      }
    }
  }

  // Mirror folder path into every WASM module's registry (WEB-001).
  try {
    mirrorDownloadCompletionToRegistry(model, opfsFolder);
  } catch (err) {
    logger.warning(
      `Multi-file registry mirror failed: ${err instanceof Error ? err.message : String(err)}`,
    );
  }

  const completed: DownloadProgress = {
    modelId: request.modelId,
    state: DownloadState.DOWNLOAD_STATE_COMPLETED,
    overallProgress: 1,
    bytesDownloaded: downloadedBytes,
    totalBytes,
    stageProgress: 1,
    overallSpeedBps: 0,
    etaSeconds: 0,
    retryAttempt: 0,
    errorMessage: '',
    taskId: '',
    stage: 0,
    currentFileIndex: files.length,
    totalFiles: files.length,
    storageKey: '',
    localPath: opfsFolder,
    startedAtUnixMs: 0,
    updatedAtUnixMs: Date.now(),
    currentFileName: '',
    resumeToken: '',
  };
  onProgress?.(completed);
  return completed;
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

        await requestPersistentStorage();

        // Load the core commons WASM so the SDK facade (init, environment,
        // auth, model registry, lifecycle, proto events) has its native
        // backing. Failure is non-fatal — backend packages (LlamaCPP, ONNX)
        // load their own WASM modules and install them via
        // `setRunanywhereModule`, so apps that only need backend-specific
        // operations can still proceed if the core artifact is missing.
        try {
          await CommonsModule.shared.ensureLoaded();
        } catch (err) {
          logger.warning(
            `Failed to load core Commons WASM (non-fatal — backend packages can still install their own modules): ${
              err instanceof Error ? err.message : String(err)
            }`,
          );
        }

        _isInitialized = true;

        ensureDeviceId();

        logger.info('RunAnywhere Web SDK initialized successfully');
        EventBus.shared.emit('sdk.initialized', EventCategory.EVENT_CATEGORY_INITIALIZATION, {
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
          EventBus.shared.emit(
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

  /**
   * Backend availability snapshots — `RunAnywhere.backends.onnxStatus()`
   * etc. Returns build-flag-free reasons that example apps can render
   * directly without leaking CMake symbol names into the UI.
   */
  backends: BackendsCapability,

  // =========================================================================
  // Swift-shaped flat facade
  // =========================================================================

  async loadModel(
    request: Parameters<typeof ModelLifecycleCapability.loadModel>[0],
  ): Promise<Awaited<ReturnType<typeof ModelLifecycleCapability.loadModelAsync>>> {
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

  /**
   * Register a single-file remote model by URL. Mirrors Swift's
   * `RunAnywhere.registerModel(id:name:url:framework:...)` so example
   * catalogs read as declarative entries — the SDK assembles the
   * `ModelInfo` proto.
   */
  registerModel(
    url: string,
    name: string,
    framework: InferenceFramework,
    options?: RegisterModelOptions,
  ): ModelInfo {
    return registerModelFromUrl(url, name, framework, options);
  },

  /**
   * Register an archive-packaged model. The SDK stamps the canonical
   * `artifactType` (`MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE`, etc.) onto the
   * resulting `ModelInfo` and routes the download orchestrator through
   * extraction.
   */
  registerModelArchive(
    url: string,
    name: string,
    framework: InferenceFramework,
    archiveType: ModelArtifactType,
    options?: RegisterModelOptions,
  ): ModelInfo {
    return registerModelArchiveImpl(url, name, framework, archiveType, options);
  },

  /**
   * Register a multi-file model (VLM = primary GGUF + mmproj sidecar,
   * embedding = `model.onnx` + `vocab.txt`). The SDK builds the
   * `MultiFileArtifact` proto + `ExpectedModelFiles` manifest from the
   * provided file list.
   */
  registerModelMultiFile(options: RegisterMultiFileOptions): ModelInfo {
    return registerModelMultiFileImpl(options);
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

    // Multi-file models (VLM = primary GGUF + mmproj sidecar, embeddings =
    // model.onnx + vocab.txt) cannot use the C++ download orchestrator on
    // Web because that path writes to MEMFS and reports the folder as
    // `localPath`; OPFSBridge.flushFromMemfs treats that as a single file
    // and silently no-ops. Use the browser-side fetch path instead.
    if ((model.multiFile?.files?.length ?? 0) > 1) {
      return downloadMultiFileModel(request, model, request.onProgress);
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
      // Defer COMPLETED to onProgress until OPFS flush finishes (WEB-001).
      // UI/E2E often triggers loadModel on COMPLETED; firing it early races
      // the async MEMFS→OPFS persist that follows the poll loop.
      if (progress.state !== DownloadState.DOWNLOAD_STATE_COMPLETED) {
        request.onProgress?.(progress);
      }
    }

    if (lastProgress.state !== DownloadState.DOWNLOAD_STATE_COMPLETED) {
      throw SDKException.backendNotAvailable(
        'downloadModel',
        lastProgress.errorMessage || `Download for '${request.modelId}' ended in state ${lastProgress.state}.`,
      );
    }

    // BUG-WEB-002 / OPFS persistence: the C++ download orchestrator wrote
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
            SDKErrorCode.StorageError,
            err instanceof Error ? err.message : String(err),
            'downloadModel',
          );
        }
      }
    }

    request.onProgress?.(lastProgress);

    // CPP-02 self-heal may only update the commons WASM registry. Mirror
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
   * Scan the Origin Private File System for models that were downloaded in a
   * previous session and update the C++ registry's `localPath` for any
   * that are found on disk but not yet reflected in the in-memory registry.
   *
   * Call this once after backends register and the model catalog is
   * populated, to restore the "Downloaded" status across tab reloads.
   *
   * Returns the number of registry entries patched.
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

      // WEB-REDOWNLOAD-WAIT-001: clearSiteStorage (or manual OPFS purge)
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
      // WEB-OPFS-HYDRATE-UI-001: notify UI subscribers (Storage tab, model
      // sheet) so they re-query the registry and render Downloaded/Load
      // instead of Download after a fresh page load.
      EventBus.shared.emit(
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
    extra: CancellableCall = {},
  ): ReturnType<typeof TextGenerationCapability.generate> {
    throwIfAborted(extra.signal, 'generate');
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
    const stream = await TextGenerationCapability.generateStream(options);
    const detach = attachSignalToCancel(extra.signal, () => stream.cancel());
    void stream.result.finally(detach);
    return stream;
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
    audio: Parameters<typeof STTCapability.transcribeAuto>[0],
    options?: Parameters<typeof STTCapability.transcribeAuto>[1],
    extra: CancellableCall = {},
  ): ReturnType<typeof STTCapability.transcribeAuto> {
    throwIfAborted(extra.signal, 'transcribe');
    return STTCapability.transcribeAuto(audio, options);
  },

  transcribeStream(
    ...args: Parameters<typeof STTCapability.transcribeStream>
  ): ReturnType<typeof STTCapability.transcribeStream> {
    // The handle-driven stream APIs accept cancellation through the
    // existing stop/destroy verbs and the AbortSignal pattern on the flat
    // verb; callers wanting to plumb a signal should pre-check it before
    // entering the loop.
    return STTCapability.transcribeStream(...args);
  },

  synthesize(
    text: Parameters<typeof TTSCapability.synthesizeAuto>[0],
    options?: Parameters<typeof TTSCapability.synthesizeAuto>[1],
    extra: CancellableCall = {},
  ): ReturnType<typeof TTSCapability.synthesizeAuto> {
    throwIfAborted(extra.signal, 'synthesize');
    return TTSCapability.synthesizeAuto(text, options);
  },

  synthesizeStream(
    ...args: Parameters<typeof TTSCapability.synthesizeStream>
  ): ReturnType<typeof TTSCapability.synthesizeStream> {
    // The handle-driven stream APIs accept cancellation through the
    // existing stop/destroy verbs and the AbortSignal pattern on the flat
    // verb; callers wanting to plumb a signal should pre-check it before
    // entering the loop.
    return TTSCapability.synthesizeStream(...args);
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
          const playback = new AudioPlayback({
            sampleRate: output.sampleRate > 0 ? output.sampleRate : 22050,
          });
          try {
            await playback.play(samples, output.sampleRate || undefined);
          } finally {
            playback.dispose();
          }
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
    image: Parameters<typeof VisionLanguageCapability.processImage>[0],
    options: Parameters<typeof VisionLanguageCapability.processImage>[1],
    extra: CancellableCall = {},
  ): Promise<Awaited<ReturnType<typeof VisionLanguageCapability.processImage>>> {
    throwIfAborted(extra.signal, 'processImage');
    if (!VisionLanguageCapability.isModelLoaded) {
      await VisionLanguageCapability.loadCurrentModel();
    }
    const detach = attachSignalToCancel(
      extra.signal,
      () => VisionLanguageCapability.cancelVLMGeneration(),
    );
    return VisionLanguageCapability.processImage(image, options).finally(detach);
  },

  async processImageStream(
    image: Parameters<typeof VisionLanguageCapability.processImageStream>[0],
    options: Parameters<typeof VisionLanguageCapability.processImageStream>[1],
    extra: CancellableCall = {},
  ): ReturnType<typeof VisionLanguageCapability.processImageStream> {
    throwIfAborted(extra.signal, 'processImageStream');
    if (!VisionLanguageCapability.isModelLoaded) {
      await VisionLanguageCapability.loadCurrentModel();
    }
    const stream = await VisionLanguageCapability.processImageStream(image, options);
    attachSignalToCancel(
      extra.signal,
      () => VisionLanguageCapability.cancelVLMGeneration(),
    );
    return stream;
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

    // Tear down the T6.1 Worker streaming pipeline. The pass-1 fix
    // established `clearRunanywhereModule()` + `disposeSpeechProvider()`
    // as the WASM ownership boundary, but the Worker singletons
    // (`OffscreenRuntimeBridge._instance`, `_init` payload, and the
    // `StreamWorkerFactoryRegistry._factory`) live outside that
    // boundary. Without explicit teardown the spawned worker keeps its
    // mirror Emscripten module + loaded model weights alive across
    // logout / account-switch / test reset, and the next `initialize()`
    // would reuse the stale bridge. See pass2-syn-033.
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
    _servicesInitPromise = null;

    logger.info('RunAnywhere Web SDK shut down');
  },

  reset(): void {
    RunAnywhere.shutdown();
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
