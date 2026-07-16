import {
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
  StorageInfoResult,
  type StorageAvailabilityRequest as ProtoStorageAvailabilityRequest,
  type StorageAvailabilityResult as ProtoStorageAvailabilityResult,
  type StorageDeletePlan as ProtoStorageDeletePlan,
  type StorageDeletePlanRequest as ProtoStorageDeletePlanRequest,
  type StorageDeleteRequest as ProtoStorageDeleteRequest,
  type StorageDeleteResult as ProtoStorageDeleteResult,
  type StorageInfoRequest as ProtoStorageInfoRequest,
  type StorageInfoResult as ProtoStorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
import {
  ModelArtifactType,
  ModelCategory,
  type InferenceFramework,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import {
  RAC_ERROR_DELETE_FAILED,
  RAC_ERROR_INVALID_ARGUMENT,
  RAC_ERROR_MODEL_NOT_LOADED,
  RAC_OK,
} from '../Foundation/RACErrors.js';
import { SDKLogger } from '../Foundation/SDKLogger.js';
import { OPFSBridge } from '../Infrastructure/OPFSBridge.js';
import { frameworkOPFSDir } from '../Infrastructure/FrameworkOPFSPaths.js';
import { ModelLifecycleAdapter } from './ModelLifecycleAdapter.js';
import { ModelRegistryAdapter } from './ModelRegistryAdapter.js';
import { getAllRegisteredModules } from '../runtime/EmscriptenModule.js';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm.js';

const logger = new SDKLogger('StorageAdapter');

export interface StorageModule extends ProtoWasmModule {
  _rac_get_model_registry?(): number;
  _rac_storage_analyzer_info_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_availability_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_delete_plan_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
  _rac_storage_analyzer_delete_proto?(
    handle: number,
    registryHandle: number,
    requestBytes: number,
    requestSize: number,
    outResult: number,
  ): number;
}

interface StorageAnalyzerLifecycle {
  readonly isDisposed: boolean;
  refreshStorageState(): void;
  refreshLoadedModelState(): void;
  prepareDelete(request: ProtoStorageDeleteRequest): Promise<void>;
  finishDelete(): void;
}

interface StorageAnalyzerBinding {
  readonly module: StorageModule;
  readonly analyzerHandle: number;
  readonly registryHandle: number;
  readonly lifecycle: StorageAnalyzerLifecycle | null;
  deleteTail: Promise<void>;
  closing: boolean;
}

let defaultBinding: StorageAnalyzerBinding | null = null;

export class StorageAdapter {
  static setDefaultHandles(
    module: StorageModule,
    analyzerHandle: number,
    registryHandle = 0,
    lifecycle: StorageAnalyzerLifecycle | null = null,
  ): void {
    if (defaultBinding) defaultBinding.closing = true;
    defaultBinding = {
      module,
      analyzerHandle,
      registryHandle,
      lifecycle,
      deleteTail: Promise.resolve(),
      closing: false,
    };
  }

  static clearDefaultHandles(module?: StorageModule, analyzerHandle?: number): void {
    const binding = defaultBinding;
    if (!binding) return;
    if (module && binding.module !== module) return;
    if (analyzerHandle && binding.analyzerHandle !== analyzerHandle) return;
    binding.closing = true;
    defaultBinding = null;
  }

  /**
   * Close the current delete admission gate and wait for every operation that
   * entered before shutdown. This must run before the analyzer handle or its
   * WASM module is destroyed; callers that retained an adapter from this
   * lifetime are rejected after the gate closes instead of reaching stale C
   * function pointers.
   */
  static async prepareForShutdown(module?: StorageModule): Promise<void> {
    const binding = defaultBinding;
    if (!binding || (module && binding.module !== module)) return;
    binding.closing = true;
    await binding.deleteTail;
  }

  static tryDefault(): StorageAdapter | null {
    const binding = defaultBinding;
    if (!binding || !binding.analyzerHandle || binding.closing) return null;
    const adapter = new StorageAdapter(
      binding.module,
      binding.analyzerHandle,
      binding.registryHandle,
    );
    adapter.binding = binding;
    return adapter;
  }

  private binding: StorageAnalyzerBinding;

  constructor(
    private readonly module: StorageModule,
    private readonly analyzerHandle: number,
    private readonly registryHandle = 0,
  ) {
    this.binding = {
      module,
      analyzerHandle,
      registryHandle,
      lifecycle: null,
      deleteTail: Promise.resolve(),
      closing: false,
    };
  }

  supportsProtoStorage(): boolean {
    return !this.binding.closing
      && !this.binding.lifecycle?.isDisposed
      && this.missingExports().length === 0
      && this.analyzerHandle !== 0;
  }

  info(request: ProtoStorageInfoRequest): ProtoStorageInfoResult | null {
    if (!this.ensureExports('info', ['_rac_storage_analyzer_info_proto'])) return null;
    this.binding.lifecycle?.refreshStorageState();
    return this.bridge().withEncodedRequest(
      request,
      StorageInfoRequest,
      StorageInfoResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_storage_analyzer_info_proto!(
          this.analyzerHandle,
          this.getRegistryHandle(),
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_storage_analyzer_info_proto',
    );
  }

  availability(
    request: ProtoStorageAvailabilityRequest,
  ): ProtoStorageAvailabilityResult | null {
    if (!this.ensureExports('availability', ['_rac_storage_analyzer_availability_proto'])) {
      return null;
    }
    this.binding.lifecycle?.refreshStorageState();
    return this.bridge().withEncodedRequest(
      request,
      StorageAvailabilityRequest,
      StorageAvailabilityResult,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_storage_analyzer_availability_proto!(
          this.analyzerHandle,
          this.getRegistryHandle(),
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_storage_analyzer_availability_proto',
    );
  }

  deletePlan(request: ProtoStorageDeletePlanRequest): ProtoStorageDeletePlan | null {
    if (!this.ensureExports('deletePlan', ['_rac_storage_analyzer_delete_plan_proto'])) {
      return null;
    }
    this.binding.lifecycle?.refreshStorageState();
    return this.bridge().withEncodedRequest(
      request,
      StorageDeletePlanRequest,
      StorageDeletePlan,
      (requestPtr, requestSize, outResult) => (
        this.module._rac_storage_analyzer_delete_plan_proto!(
          this.analyzerHandle,
          this.getRegistryHandle(),
          requestPtr,
          requestSize,
          outResult,
        )
      ),
      'rac_storage_analyzer_delete_plan_proto',
    );
  }

  async delete(request: ProtoStorageDeleteRequest): Promise<ProtoStorageDeleteResult | null> {
    const binding = this.binding;
    if (binding.closing || binding.lifecycle?.isDisposed) {
      throw new Error('Storage delete cancelled because the SDK runtime is shutting down.');
    }
    if (!this.ensureExports('delete', ['_rac_storage_analyzer_delete_proto'])) return null;
    const predecessor = binding.deleteTail;
    let release!: () => void;
    binding.deleteTail = new Promise<void>((resolve) => { release = resolve; });
    await predecessor;
    const lifecycle = binding.lifecycle;
    try {
      if (lifecycle?.isDisposed) {
        throw new Error('Storage delete cancelled because its analyzer was disposed.');
      }
      await lifecycle?.prepareDelete(request);
      if (lifecycle?.isDisposed) {
        throw new Error('Storage delete cancelled because its analyzer was disposed.');
      }
      // OPFS removal yields to the event loop. A caller may load the model
      // again while that persistent operation is pending, so refresh the
      // synchronous callback cache at the final no-yield boundary before
      // native validates loaded state and touches any module's MEMFS.
      lifecycle?.refreshLoadedModelState();
      const result = this.bridge().withEncodedRequest(
        request,
        StorageDeleteRequest,
        StorageDeleteResult,
        (requestPtr, requestSize, outResult) => (
          this.module._rac_storage_analyzer_delete_proto!(
            this.analyzerHandle,
            this.getRegistryHandle(),
            requestPtr,
            requestSize,
            outResult,
          )
        ),
        'rac_storage_analyzer_delete_proto',
      );
      if (result && request.clearRegistryPaths && !request.dryRun) {
        this.synchronizeClearedRegistryPaths(result.deletedModelIds);
      }
      return result;
    } finally {
      lifecycle?.finishDelete();
      release();
    }
  }

  private getRegistryHandle(): number {
    if (this.registryHandle) return this.registryHandle;
    return this.module._rac_get_model_registry?.() ?? 0;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private synchronizeClearedRegistryPaths(deletedModelIds: readonly string[]): void {
    const registry = ModelRegistryAdapter.tryDefault();
    if (!registry) return;
    for (const modelId of new Set(deletedModelIds.filter((id) => id.length > 0))) {
      try {
        if (!registry.updateDownloadStatus(modelId, null)) {
          logger.warning(`Failed to synchronize cleared storage metadata for model '${modelId}'.`);
        }
      } catch {
        logger.warning(`Failed to synchronize cleared storage metadata for model '${modelId}'.`);
      }
    }
  }

  private missingExports(): string[] {
    const required: Array<keyof StorageModule> = [
      '_rac_get_model_registry',
      '_rac_storage_analyzer_info_proto',
      '_rac_storage_analyzer_availability_proto',
      '_rac_storage_analyzer_delete_plan_proto',
      '_rac_storage_analyzer_delete_proto',
    ];
    return [
      ...this.bridge().missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
  }

  private ensureExports(operation: string, required: Array<keyof StorageModule>): boolean {
    if (this.binding.closing || this.binding.lifecycle?.isDisposed) {
      logger.warning(`${operation}: storage analyzer belongs to a closed SDK runtime`);
      return false;
    }
    if (!this.analyzerHandle) {
      logger.warning(`${operation}: storage analyzer handle is null`);
      return false;
    }
    const missing = [
      ...this.bridge().missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
    if (missing.length > 0) {
      logger.warning(`${operation}: module missing storage proto exports: ${missing.join(', ')}`);
      return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Browser-owned native storage analyzer lifecycle
// ---------------------------------------------------------------------------

interface StorageEstimateResult {
  usage?: number;
  quota?: number;
}

interface BrowserStorageManager {
  estimate?: () => Promise<StorageEstimateResult>;
}

interface StorageAnalyzerFS {
  analyzePath?(path: string): { exists: boolean };
  stat(path: string): { size: number; mode: number };
  readdir?(path: string): string[];
  isDir?(mode: number): boolean;
  unlink(path: string): void;
  rmdir?(path: string): void;
}

export interface BrowserStorageAnalyzerModule extends StorageModule {
  _malloc(size: number): number;
  _free(ptr: number): void;
  addFunction(
    callback: (...args: number[]) => number | bigint | void,
    signature: string,
  ): number;
  removeFunction(ptr: number): void;
  setValue(ptr: number, value: number, type: string): void;
  getValue(ptr: number, type: string): number;
  UTF8ToString(ptr: number, maxBytesToRead?: number): string;
  FS?: unknown;

  _rac_storage_analyzer_create(callbacksPtr: number, outHandlePtr: number): number;
  _rac_storage_analyzer_destroy(handle: number): void;
  _rac_get_model_registry(): number;

  _rac_wasm_sizeof_storage_callbacks?(): number;
  _rac_wasm_offsetof_storage_callbacks_calculate_dir_size?(): number;
  _rac_wasm_offsetof_storage_callbacks_get_file_size?(): number;
  _rac_wasm_offsetof_storage_callbacks_path_exists?(): number;
  _rac_wasm_offsetof_storage_callbacks_get_available_space?(): number;
  _rac_wasm_offsetof_storage_callbacks_get_total_space?(): number;
  _rac_wasm_offsetof_storage_callbacks_delete_path?(): number;
  _rac_wasm_offsetof_storage_callbacks_is_model_loaded?(): number;
  _rac_wasm_offsetof_storage_callbacks_unload_model?(): number;
  _rac_wasm_offsetof_storage_callbacks_user_data?(): number;
}

interface StorageCallbackLayout {
  size: number;
  calculateDirSize: number;
  getFileSize: number;
  pathExists: number;
  getAvailableSpace: number;
  getTotalSpace: number;
  deletePath: number;
  isModelLoaded: number;
  unloadModel: number;
  userData: number;
}

interface StorageCallbackPointers {
  calculateDirSize: number;
  getFileSize: number;
  pathExists: number;
  getAvailableSpace: number;
  getTotalSpace: number;
  deletePath: number;
  isModelLoaded: number;
  unloadModel: number;
}

interface StoragePathMetadata {
  readonly size: number;
  readonly isDirectory: boolean;
}

const STORAGE_MODEL_PREFIX = '/opfs/RunAnywhere/Models/';
const MODEL_CATEGORIES: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  ModelCategory.MODEL_CATEGORY_VISION,
  ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  ModelCategory.MODEL_CATEGORY_AUDIO,
  ModelCategory.MODEL_CATEGORY_EMBEDDING,
  ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
];
const DIRECTORY_ARTIFACT_TYPES = new Set<ModelArtifactType>([
  ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
  ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
  ModelArtifactType.MODEL_ARTIFACT_TYPE_ZIP_ARCHIVE,
  ModelArtifactType.MODEL_ARTIFACT_TYPE_ARCHIVE,
  ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE,
  ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_BZ2_ARCHIVE,
  ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_XZ_ARCHIVE,
]);

function requiredStorageLayoutHelper(
  helper: (() => number) | undefined,
  name: string,
): number {
  if (typeof helper !== 'function') {
    throw new Error(`WASM module missing ${name}; rebuild the core Web artifact.`);
  }
  return helper();
}

function fsFor(module: object): StorageAnalyzerFS | null {
  const candidate = (module as { FS?: unknown }).FS;
  if (!candidate || typeof candidate !== 'object') return null;
  const fs = candidate as Partial<StorageAnalyzerFS>;
  if (
    typeof fs.stat !== 'function'
    || typeof fs.unlink !== 'function'
  ) {
    return null;
  }
  return fs as StorageAnalyzerFS;
}

function pathExistsInFS(fs: StorageAnalyzerFS, path: string): boolean {
  try {
    if (fs.analyzePath) return fs.analyzePath(path).exists;
    fs.stat(path);
    return true;
  } catch {
    return false;
  }
}

function isDirectoryInFS(fs: StorageAnalyzerFS, path: string): boolean {
  try {
    const stat = fs.stat(path);
    return typeof fs.isDir === 'function'
      ? fs.isDir(stat.mode)
      : (stat.mode & 0o170000) === 0o040000;
  } catch {
    return false;
  }
}

function calculatePathSize(fs: StorageAnalyzerFS, path: string): number {
  if (!pathExistsInFS(fs, path)) return 0;
  if (!isDirectoryInFS(fs, path)) {
    try {
      return Math.max(0, Math.trunc(fs.stat(path).size));
    } catch {
      return 0;
    }
  }
  if (typeof fs.readdir !== 'function') return 0;
  let total = 0;
  for (const name of fs.readdir(path)) {
    if (name === '.' || name === '..') continue;
    total += calculatePathSize(fs, `${path.replace(/\/$/, '')}/${name}`);
  }
  return Math.min(Number.MAX_SAFE_INTEGER, total);
}

function deletePathFromFS(fs: StorageAnalyzerFS, path: string, recursive: boolean): boolean {
  if (!pathExistsInFS(fs, path)) return true;
  if (!isDirectoryInFS(fs, path)) {
    fs.unlink(path);
    return true;
  }
  if (!recursive || typeof fs.readdir !== 'function' || typeof fs.rmdir !== 'function') {
    return false;
  }
  for (const name of fs.readdir(path)) {
    if (name === '.' || name === '..') continue;
    if (!deletePathFromFS(fs, `${path.replace(/\/$/, '')}/${name}`, true)) return false;
  }
  fs.rmdir(path);
  return true;
}

function isSafeModelStoragePath(path: string): boolean {
  if (!path.startsWith(STORAGE_MODEL_PREFIX)) return false;
  const relativeSegments = path.slice(STORAGE_MODEL_PREFIX.length).split('/');
  return relativeSegments.length >= 2
    && relativeSegments.every((segment) => segment.length > 0 && segment !== '.' && segment !== '..');
}

function finiteStorageBytes(value: number | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  return Math.min(Number.MAX_SAFE_INTEGER, Math.max(0, Math.trunc(value)));
}

/**
 * Owns the JavaScript function-table entries and native analyzer handle for
 * one commons WASM lifetime. Native callbacks stay synchronous; destructive
 * persistent work is awaited by the public async facade before native commits
 * the matching MEMFS and registry changes.
 */
export class BrowserStorageAnalyzerAdapter implements StorageAnalyzerLifecycle {
  private callbacksPtr = 0;
  private analyzerHandle = 0;
  private registryHandle = 0;
  private callbackPointers: StorageCallbackPointers | null = null;
  private readonly callbackLayout: StorageCallbackLayout;
  private totalSpace = 0;
  private availableSpace = 0;
  private readonly loadedModelIds = new Set<string>();
  private readonly loadedModelIdsByModule = new Map<object, Set<string>>();
  private readonly unloadFailures = new Set<string>();
  /** One authoritative metadata row per downloaded model local path. */
  private readonly modelStorageRoots = new Map<string, StoragePathMetadata>();
  /** Exact model and known multi-file child paths for synchronous callbacks. */
  private readonly pathMetadata = new Map<string, StoragePathMetadata>();
  private readonly modelStoragePathsById = new Map<string, string>();
  /** Canonical per-model folders removed by the native storage analyzer. */
  private readonly modelDeletePathsById = new Map<string, string>();
  private readonly preparedPersistentDeletes = new Set<string>();
  private readonly persistentDeleteFailures = new Set<string>();
  private disposed = false;

  private constructor(private readonly module: BrowserStorageAnalyzerModule) {
    this.callbackLayout = this.readCallbackLayout();
  }

  static async install(
    module: BrowserStorageAnalyzerModule,
  ): Promise<BrowserStorageAnalyzerAdapter> {
    const adapter = new BrowserStorageAnalyzerAdapter(module);
    await adapter.refreshQuotaEstimate();
    adapter.register();
    return adapter;
  }

  get handle(): number {
    return this.analyzerHandle;
  }

  get isDisposed(): boolean {
    return this.disposed;
  }

  cleanup(): void {
    this.disposed = true;
    StorageAdapter.clearDefaultHandles(this.module, this.analyzerHandle);
    if (this.analyzerHandle !== 0) {
      try {
        this.module._rac_storage_analyzer_destroy(this.analyzerHandle);
      } catch {
        logger.warning('Failed to destroy the browser storage analyzer handle.');
      }
      this.analyzerHandle = 0;
    }
    if (this.callbackPointers) {
      for (const ptr of Object.values(this.callbackPointers)) {
        if (!ptr) continue;
        try {
          this.module.removeFunction(ptr);
        } catch {
          // Continue releasing the remaining function-table entries.
        }
      }
      this.callbackPointers = null;
    }
    if (this.callbacksPtr !== 0) {
      this.module._free(this.callbacksPtr);
      this.callbacksPtr = 0;
    }
    this.loadedModelIds.clear();
    this.loadedModelIdsByModule.clear();
    this.unloadFailures.clear();
    this.modelStorageRoots.clear();
    this.pathMetadata.clear();
    this.modelStoragePathsById.clear();
    this.modelDeletePathsById.clear();
    this.preparedPersistentDeletes.clear();
    this.persistentDeleteFailures.clear();
  }

  refreshStorageState(): void {
    this.refreshRegistryMetadata();
    this.refreshLoadedModelState();
    void this.refreshQuotaEstimate();
  }

  refreshLoadedModelState(): void {
    this.loadedModelIds.clear();
    this.loadedModelIdsByModule.clear();
    for (const module of this.registeredModules()) {
      const loadedForModule = new Set<string>();
      const lifecycle = ModelLifecycleAdapter.fromModule(module);
      if (!lifecycle.supportsProtoLifecycle()) {
        this.loadedModelIdsByModule.set(module, loadedForModule);
        continue;
      }
      for (const category of MODEL_CATEGORIES) {
        try {
          const result = lifecycle.currentModel({ category, includeModelMetadata: false });
          if (result?.found && result.modelId) {
            loadedForModule.add(result.modelId);
            this.loadedModelIds.add(result.modelId);
          }
        } catch {
          // A backend without this category simply contributes no loaded id.
        }
      }
      this.loadedModelIdsByModule.set(module, loadedForModule);
    }
  }

  async prepareDelete(request: ProtoStorageDeleteRequest): Promise<void> {
    this.unloadFailures.clear();
    this.preparedPersistentDeletes.clear();
    this.persistentDeleteFailures.clear();
    this.refreshStorageState();
    if (request.dryRun) return;
    if (!request.deleteFiles && !request.clearRegistryPaths) return;
    if (request.deleteFiles && !request.allowPlatformDelete) return;
    if (request.requirePlanMatch && !request.plan) return;

    // Match native's plan-candidate semantics before performing any browser
    // side effect. Native stores candidates in an unordered_map, so duplicate
    // ids are last-wins; using Array.find() here would make JS pre-delete a
    // different path than native later validates.
    const targets = this.validatedDeleteTargets(request);

    if (request.unloadIfLoaded) {
      for (const modelId of targets.keys()) {
        if (!this.loadedModelIds.has(modelId)) continue;
        for (const [module, loadedIds] of this.loadedModelIdsByModule) {
          if (!loadedIds.has(modelId)) continue;
          try {
            const result = ModelLifecycleAdapter.fromModule(module).unload({
              modelId,
              unloadAll: false,
            });
            if (!result?.success) this.unloadFailures.add(modelId);
          } catch {
            this.unloadFailures.add(modelId);
          }
        }
      }
      this.refreshLoadedModelState();
    }

    if (!request.deleteFiles) return;
    for (const [modelId, path] of targets) {
      if (this.loadedModelIds.has(modelId) || this.unloadFailures.has(modelId)) continue;
      if (!isSafeModelStoragePath(path)) continue;
      try {
        await OPFSBridge.removePath(path);
        this.preparedPersistentDeletes.add(path);
      } catch {
        this.persistentDeleteFailures.add(path);
      }
    }
  }

  private validatedDeleteTargets(
    request: ProtoStorageDeleteRequest,
  ): ReadonlyMap<string, string> {
    const planCandidates = new Map<string, { localPath: string }>();
    for (const candidate of request.plan?.candidates ?? []) {
      if (candidate.modelId) planCandidates.set(candidate.modelId, candidate);
    }

    const targets = new Map<string, string>();
    for (const modelId of this.requestedDeleteModelIds(request)) {
      const localPath = this.modelStoragePathsById.get(modelId);
      if (!localPath) continue;
      const plannedCandidate = planCandidates.get(modelId);
      if (request.requirePlanMatch && !plannedCandidate) continue;
      if (plannedCandidate?.localPath && plannedCandidate.localPath !== localPath) continue;
      targets.set(modelId, this.modelDeletePathsById.get(modelId) ?? localPath);
    }
    return targets;
  }

  finishDelete(): void {
    this.preparedPersistentDeletes.clear();
    this.persistentDeleteFailures.clear();
  }

  private requestedDeleteModelIds(request: ProtoStorageDeleteRequest): ReadonlySet<string> {
    const requestedIds = request.modelIds.filter((id) => id.length > 0);
    const ids = requestedIds.length > 0
      ? requestedIds
      : (request.plan?.candidates ?? []).map((candidate) => candidate.modelId);
    if (!request.requirePlanMatch || !request.plan) {
      return new Set(ids.filter((id) => id.length > 0));
    }
    const plannedIds = new Set(
      request.plan.candidates.map((candidate) => candidate.modelId).filter((id) => id.length > 0),
    );
    return new Set(ids.filter((id) => plannedIds.has(id)));
  }

  private register(): void {
    this.callbacksPtr = this.module._malloc(this.callbackLayout.size);
    if (!this.callbacksPtr) throw new Error('Failed to allocate browser storage callbacks.');
    this.zeroMemory(this.callbacksPtr, this.callbackLayout.size);

    try {
      this.callbackPointers = {
        calculateDirSize: this.module.addFunction(
          (pathPtr: number) => BigInt(this.calculateSize(pathPtr)),
          'jii',
        ),
        getFileSize: this.module.addFunction(
          (pathPtr: number) => BigInt(this.fileSize(pathPtr)),
          'jii',
        ),
        pathExists: this.module.addFunction(
          (pathPtr: number, outIsDirectoryPtr: number) => (
            this.pathExists(pathPtr, outIsDirectoryPtr)
          ),
          'iiii',
        ),
        getAvailableSpace: this.module.addFunction(
          () => BigInt(this.availableSpace),
          'ji',
        ),
        getTotalSpace: this.module.addFunction(
          () => BigInt(this.totalSpace),
          'ji',
        ),
        deletePath: this.module.addFunction(
          (pathPtr: number, recursive: number) => this.deletePath(pathPtr, recursive !== 0),
          'iiii',
        ),
        isModelLoaded: this.module.addFunction(
          (modelIdPtr: number, outIsLoadedPtr: number) => (
            this.isModelLoaded(modelIdPtr, outIsLoadedPtr)
          ),
          'iiii',
        ),
        unloadModel: this.module.addFunction(
          (modelIdPtr: number) => this.unloadModel(modelIdPtr),
          'iii',
        ),
      };

      this.writeCallback('calculateDirSize', this.callbackLayout.calculateDirSize);
      this.writeCallback('getFileSize', this.callbackLayout.getFileSize);
      this.writeCallback('pathExists', this.callbackLayout.pathExists);
      this.writeCallback('getAvailableSpace', this.callbackLayout.getAvailableSpace);
      this.writeCallback('getTotalSpace', this.callbackLayout.getTotalSpace);
      this.writeCallback('deletePath', this.callbackLayout.deletePath);
      this.writeCallback('isModelLoaded', this.callbackLayout.isModelLoaded);
      this.writeCallback('unloadModel', this.callbackLayout.unloadModel);
      this.module.setValue(this.callbacksPtr + this.callbackLayout.userData, 0, '*');

      const outHandlePtr = this.module._malloc(4);
      if (!outHandlePtr) throw new Error('Failed to allocate storage analyzer out-handle.');
      try {
        this.module.setValue(outHandlePtr, 0, '*');
        const result = this.module._rac_storage_analyzer_create(this.callbacksPtr, outHandlePtr);
        if (result !== RAC_OK) {
          throw new Error(`rac_storage_analyzer_create failed with code ${result}.`);
        }
        this.analyzerHandle = this.module.getValue(outHandlePtr, '*') >>> 0;
      } finally {
        this.module._free(outHandlePtr);
      }
      if (!this.analyzerHandle) throw new Error('Native storage analyzer returned a null handle.');
      this.registryHandle = this.module._rac_get_model_registry();
      if (!this.registryHandle) throw new Error('Native model registry returned a null handle.');
      // rac_storage_analyzer_create copies the table by value. Release only
      // the caller-owned struct; the function-table entries themselves remain
      // owned until cleanup(), after the analyzer handle is destroyed.
      this.module._free(this.callbacksPtr);
      this.callbacksPtr = 0;
      StorageAdapter.setDefaultHandles(
        this.module,
        this.analyzerHandle,
        this.registryHandle,
        this,
      );
    } catch (error) {
      this.cleanup();
      throw error;
    }
  }

  private writeCallback(
    field: keyof StorageCallbackPointers,
    offset: number,
  ): void {
    const callback = this.callbackPointers?.[field] ?? 0;
    this.module.setValue(this.callbacksPtr + offset, callback, '*');
  }

  private calculateSize(pathPtr: number): number {
    const path = this.readPath(pathPtr);
    if (!path) return 0;
    let largestSize = 0;
    for (const module of this.registeredModules()) {
      const fs = fsFor(module);
      if (!fs) continue;
      largestSize = Math.max(largestSize, calculatePathSize(fs, path));
    }
    return Math.max(largestSize, this.metadataSize(path));
  }

  private fileSize(pathPtr: number): number {
    const path = this.readPath(pathPtr);
    if (!path) return -1;
    let found = false;
    let largestSize = 0;
    for (const module of this.registeredModules()) {
      const fs = fsFor(module);
      if (!fs || !pathExistsInFS(fs, path) || isDirectoryInFS(fs, path)) continue;
      found = true;
      largestSize = Math.max(largestSize, calculatePathSize(fs, path));
    }
    const metadata = this.pathMetadata.get(path);
    if (metadata && !metadata.isDirectory) {
      return Math.max(largestSize, metadata.size);
    }
    return found ? largestSize : -1;
  }

  private pathExists(pathPtr: number, outIsDirectoryPtr: number): number {
    const path = this.readPath(pathPtr);
    if (!path) return 0;
    let exists = false;
    let isDirectory = false;
    for (const module of this.registeredModules()) {
      const fs = fsFor(module);
      if (!fs || !pathExistsInFS(fs, path)) continue;
      exists = true;
      isDirectory ||= isDirectoryInFS(fs, path);
    }
    const metadata = this.metadataPathInfo(path);
    if (metadata) {
      exists = true;
      isDirectory ||= metadata.isDirectory;
    }
    if (outIsDirectoryPtr) {
      this.module.setValue(outIsDirectoryPtr, isDirectory ? 1 : 0, 'i32');
    }
    return exists ? 1 : 0;
  }

  private deletePath(pathPtr: number, recursive: boolean): number {
    const path = this.readPath(pathPtr);
    if (!path || !isSafeModelStoragePath(path)) return RAC_ERROR_INVALID_ARGUMENT;
    if (this.persistentDeleteFailures.has(path)) return RAC_ERROR_DELETE_FAILED;
    if (!this.preparedPersistentDeletes.has(path)) return RAC_ERROR_DELETE_FAILED;
    try {
      for (const module of this.registeredModules()) {
        const fs = fsFor(module);
        if (!fs) continue;
        if (!deletePathFromFS(fs, path, recursive)) return RAC_ERROR_DELETE_FAILED;
      }
      this.removeMetadataPath(path);
      void this.refreshQuotaEstimate();
      return RAC_OK;
    } catch {
      return RAC_ERROR_DELETE_FAILED;
    }
  }

  private isModelLoaded(modelIdPtr: number, outIsLoadedPtr: number): number {
    if (!modelIdPtr || !outIsLoadedPtr) return RAC_ERROR_INVALID_ARGUMENT;
    const modelId = this.module.UTF8ToString(modelIdPtr);
    this.module.setValue(outIsLoadedPtr, this.loadedModelIds.has(modelId) ? 1 : 0, 'i32');
    return RAC_OK;
  }

  private unloadModel(modelIdPtr: number): number {
    if (!modelIdPtr) return RAC_ERROR_INVALID_ARGUMENT;
    const modelId = this.module.UTF8ToString(modelIdPtr);
    return this.loadedModelIds.has(modelId) || this.unloadFailures.has(modelId)
      ? RAC_ERROR_MODEL_NOT_LOADED
      : RAC_OK;
  }

  private async refreshQuotaEstimate(): Promise<void> {
    const storage = typeof navigator === 'undefined'
      ? undefined
      : (navigator.storage as BrowserStorageManager | undefined);
    if (typeof storage?.estimate !== 'function') {
      this.totalSpace = 0;
      this.availableSpace = 0;
      return;
    }
    try {
      const estimate = await storage.estimate();
      const quota = finiteStorageBytes(estimate.quota);
      const usage = Math.min(quota, finiteStorageBytes(estimate.usage));
      this.totalSpace = quota;
      this.availableSpace = Math.max(0, quota - usage);
    } catch {
      this.totalSpace = 0;
      this.availableSpace = 0;
      logger.warning('Browser storage quota estimate is unavailable.');
    }
  }

  private refreshRegistryMetadata(): void {
    this.modelStorageRoots.clear();
    this.pathMetadata.clear();
    this.modelStoragePathsById.clear();
    this.modelDeletePathsById.clear();
    let models: readonly ModelInfo[] = [];
    try {
      models = ModelRegistryAdapter.tryDefault()?.list()?.models ?? [];
    } catch {
      logger.warning('Downloaded model metadata is unavailable for storage analysis.');
      return;
    }
    for (const model of models) {
      const localPath = model.localPath.trim();
      if (!localPath || model.isDownloaded === false) continue;
      const isDirectory = this.isDirectoryModel(model);
      const descriptorBytes = (model.multiFile?.files ?? []).reduce(
        (total, file) => total + finiteStorageBytes(file.sizeBytes),
        0,
      );
      const size = Math.max(finiteStorageBytes(model.downloadSizeBytes), descriptorBytes);
      const rootMetadata: StoragePathMetadata = { size, isDirectory };
      this.modelStoragePathsById.set(model.id, localPath);
      const frameworkDirectory = frameworkOPFSDir(model.framework as InferenceFramework);
      this.modelDeletePathsById.set(
        model.id,
        frameworkDirectory
          ? `${STORAGE_MODEL_PREFIX}${frameworkDirectory}/${model.id}`
          : localPath,
      );
      this.modelStorageRoots.set(localPath, rootMetadata);
      this.pathMetadata.set(localPath, rootMetadata);

      if (isDirectory) {
        for (const file of model.multiFile?.files ?? []) {
          const relativePath = (file.relativePath || file.destinationPath || file.filename).trim();
          if (!relativePath || relativePath.split('/').some((part) => part === '..')) continue;
          this.pathMetadata.set(`${localPath.replace(/\/$/, '')}/${relativePath}`, {
            size: finiteStorageBytes(file.sizeBytes),
            isDirectory: false,
          });
        }
      }
    }
  }

  private isDirectoryModel(model: ModelInfo): boolean {
    return (model.multiFile?.files?.length ?? 0) > 1
      || (model.artifactType !== undefined && DIRECTORY_ARTIFACT_TYPES.has(model.artifactType));
  }

  private metadataSize(path: string): number {
    const exact = this.pathMetadata.get(path);
    if (exact) return exact.size;
    const prefix = path.endsWith('/') ? path : `${path}/`;
    let total = 0;
    for (const [modelPath, metadata] of this.modelStorageRoots) {
      if (modelPath.startsWith(prefix)) total += metadata.size;
    }
    return Math.min(Number.MAX_SAFE_INTEGER, total);
  }

  private metadataPathInfo(path: string): StoragePathMetadata | null {
    const exact = this.pathMetadata.get(path);
    if (exact) return exact;
    const prefix = path.endsWith('/') ? path : `${path}/`;
    for (const modelPath of this.modelStorageRoots.keys()) {
      if (modelPath.startsWith(prefix)) return { size: this.metadataSize(path), isDirectory: true };
    }
    return null;
  }

  private removeMetadataPath(path: string): void {
    for (const [modelId, modelPath] of Array.from(this.modelStoragePathsById.entries())) {
      if (modelPath === path || modelPath.startsWith(`${path.replace(/\/$/, '')}/`)) {
        this.modelStoragePathsById.delete(modelId);
        this.modelDeletePathsById.delete(modelId);
      }
    }
    for (const modelPath of Array.from(this.modelStorageRoots.keys())) {
      if (modelPath === path || modelPath.startsWith(`${path.replace(/\/$/, '')}/`)) {
        this.modelStorageRoots.delete(modelPath);
      }
    }
    for (const metadataPath of Array.from(this.pathMetadata.keys())) {
      if (metadataPath === path || metadataPath.startsWith(`${path.replace(/\/$/, '')}/`)) {
        this.pathMetadata.delete(metadataPath);
      }
    }
  }

  private registeredModules(): BrowserStorageAnalyzerModule[] {
    const modules = new Set<object>([this.module, ...getAllRegisteredModules()]);
    return Array.from(modules) as BrowserStorageAnalyzerModule[];
  }

  private readPath(pathPtr: number): string {
    if (!pathPtr) return '';
    try {
      return this.module.UTF8ToString(pathPtr);
    } catch {
      return '';
    }
  }

  private zeroMemory(ptr: number, size: number): void {
    for (let index = 0; index < size; index += 1) {
      this.module.setValue(ptr + index, 0, 'i8');
    }
  }

  private readCallbackLayout(): StorageCallbackLayout {
    const module = this.module;
    return {
      size: requiredStorageLayoutHelper(
        module._rac_wasm_sizeof_storage_callbacks,
        'rac_wasm_sizeof_storage_callbacks',
      ),
      calculateDirSize: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_calculate_dir_size,
        'rac_wasm_offsetof_storage_callbacks_calculate_dir_size',
      ),
      getFileSize: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_get_file_size,
        'rac_wasm_offsetof_storage_callbacks_get_file_size',
      ),
      pathExists: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_path_exists,
        'rac_wasm_offsetof_storage_callbacks_path_exists',
      ),
      getAvailableSpace: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_get_available_space,
        'rac_wasm_offsetof_storage_callbacks_get_available_space',
      ),
      getTotalSpace: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_get_total_space,
        'rac_wasm_offsetof_storage_callbacks_get_total_space',
      ),
      deletePath: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_delete_path,
        'rac_wasm_offsetof_storage_callbacks_delete_path',
      ),
      isModelLoaded: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_is_model_loaded,
        'rac_wasm_offsetof_storage_callbacks_is_model_loaded',
      ),
      unloadModel: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_unload_model,
        'rac_wasm_offsetof_storage_callbacks_unload_model',
      ),
      userData: requiredStorageLayoutHelper(
        module._rac_wasm_offsetof_storage_callbacks_user_data,
        'rac_wasm_offsetof_storage_callbacks_user_data',
      ),
    };
  }
}
