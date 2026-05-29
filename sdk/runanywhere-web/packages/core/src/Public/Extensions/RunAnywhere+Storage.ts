/**
 * RunAnywhere+Storage.ts
 *
 * Storage namespace matching the Swift public shape while keeping Web's
 * browser-native storage affordances behind this capability. Also owns the
 * high-level `registerModel(...)` overloads that mirror Swift's
 * `RunAnywhere+Storage.registerModel` API — example apps must not
 * hand-construct full `ModelInfo` proto messages themselves.
 */

import type {
  ExpectedModelFiles,
  InferenceFramework,
  ModelFileDescriptor,
  ModelInfo,
  MultiFileArtifact,
  RegisterModelFromUrlRequest,
} from '@runanywhere/proto-ts/model_types';
import {
  ModelArtifactType,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelInfo as ModelInfoCodec,
  ModelSource,
  RegisterModelFromUrlRequest as RegisterModelFromUrlRequestCodec,
} from '@runanywhere/proto-ts/model_types';
import type {
  StorageAvailabilityRequest,
  StorageAvailabilityResult,
  StorageDeletePlan,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
import { SDKException } from '../../Foundation/SDKException';
import { StorageAdapter } from '../../Adapters/StorageAdapter';
import { ProtoWasmBridge } from '../../runtime/ProtoWasm';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { tryRunanywhereModule } from '../../runtime/EmscriptenModule';
import { ModelRegistry } from './RunAnywhere+ModelRegistry';

const _storageLogger = new SDKLogger('RunAnywhere+Storage');

/**
 * Minimal typed overlay for the `_rac_register_model_from_url_proto` WASM
 * export. Declared locally so the fix does not require touching
 * EmscriptenModule.ts interface before the WASM is rebuilt with this export.
 */
interface RegisterModelFromUrlModule {
  _rac_register_model_from_url_proto?: (
    requestBytes: number,
    requestSize: number,
    outBuffer: number,
  ) => number;
}

function requireNativeStorage(operation: string): StorageAdapter {
  const adapter = StorageAdapter.tryDefault();
  if (!adapter || !adapter.supportsProtoStorage()) {
    throw SDKException.backendNotAvailable(
      operation,
      'No Web WASM storage analyzer handle is registered.',
    );
  }
  return adapter;
}

export interface BrowserStorageControls {
  readonly isLocalStorageSupported: boolean;
  readonly isLocalStorageReady: boolean;
  readonly hasLocalStorageHandle: boolean;
  readonly localStorageDirectoryName: string | null;
  readonly storageBackend: 'fsAccess' | 'opfs' | 'memory';
  chooseLocalStorageDirectory(): Promise<boolean>;
  restoreLocalStorage(): Promise<boolean>;
  requestLocalStorageAccess(): Promise<boolean>;
}

export function createStorageNamespace(browser: BrowserStorageControls) {
  return {
    get isLocalStorageSupported(): boolean {
      return browser.isLocalStorageSupported;
    },

    get isLocalStorageReady(): boolean {
      return browser.isLocalStorageReady;
    },

    get hasLocalStorageHandle(): boolean {
      return browser.hasLocalStorageHandle;
    },

    get localStorageDirectoryName(): string | null {
      return browser.localStorageDirectoryName;
    },

    get backend(): 'fsAccess' | 'opfs' | 'memory' {
      return browser.storageBackend;
    },

    chooseLocalStorageDirectory(): Promise<boolean> {
      return browser.chooseLocalStorageDirectory();
    },

    restoreLocalStorage(): Promise<boolean> {
      return browser.restoreLocalStorage();
    },

    requestLocalStorageAccess(): Promise<boolean> {
      return browser.requestLocalStorageAccess();
    },

    supportsNativeAnalyzer(): boolean {
      return StorageAdapter.tryDefault()?.supportsProtoStorage() ?? false;
    },

    info(request: StorageInfoRequest): StorageInfoResult {
      const result = requireNativeStorage('storage.info').info(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.info', 'Native storage analyzer returned no result.');
      }
      return result;
    },

    availability(request: StorageAvailabilityRequest): StorageAvailabilityResult {
      const result = requireNativeStorage('storage.availability').availability(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.availability', 'Native storage analyzer returned no result.');
      }
      return result;
    },

    deletePlan(request: StorageDeletePlanRequest): StorageDeletePlan {
      const result = requireNativeStorage('storage.deletePlan').deletePlan(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.deletePlan', 'Native storage analyzer returned no result.');
      }
      return result;
    },

    delete(request: StorageDeleteRequest): StorageDeleteResult {
      const result = requireNativeStorage('storage.delete').delete(request);
      if (!result) {
        throw SDKException.backendNotAvailable('storage.delete', 'Native storage analyzer returned no result.');
      }
      return result;
    },
  };
}

export type StorageNamespace = ReturnType<typeof createStorageNamespace>;

// ---------------------------------------------------------------------------
// registerModel overloads (mirror Swift RunAnywhere+Storage.registerModel)
// ---------------------------------------------------------------------------

/**
 * Optional fields shared by every `registerModel(...)` overload that take a
 * single download URL or an archive. Mirrors Swift's optional parameters on
 * `RunAnywhere.registerModel(id:name:url:framework:...)` so example app
 * catalogs read as declarative entries.
 */
export interface RegisterModelOptions {
  id?: string;
  description?: string;
  format?: ModelFormat;
  modality?: ModelCategory;
  artifactType?: ModelArtifactType;
  memoryRequirement?: number;
  downloadSizeBytes?: number;
  contextLength?: number;
  supportsThinking?: boolean;
  supportsLora?: boolean;
  source?: ModelSource;
}

/**
 * One file in a multi-file model artifact (e.g. VLM primary GGUF + mmproj
 * sidecar, embedding `model.onnx` + `vocab.txt`). Web SDK turns this list
 * into the `MultiFileArtifact` proto + `ExpectedModelFiles` manifest the
 * download orchestrator needs — example apps must not assemble that
 * structure themselves.
 */
export interface RegisterModelFile {
  url: string;
  filename: string;
  role: ModelFileRole;
  sizeBytes: number;
  isRequired?: boolean;
}

export interface RegisterMultiFileOptions {
  id: string;
  name: string;
  framework: InferenceFramework;
  files: readonly RegisterModelFile[];
  description?: string;
  format?: ModelFormat;
  modality?: ModelCategory;
  memoryRequirement?: number;
  downloadSizeBytes?: number;
  contextLength?: number;
  supportsThinking?: boolean;
  supportsLora?: boolean;
  source?: ModelSource;
}

/**
 * Hook that `RunAnywhere.initialize()` installs at module init so the
 * `registerModel(...)` overloads can schedule a post-register OPFS
 * hydrate without forming a circular import with `RunAnywhere.ts`.
 */
type RegisterModelHydrateHook = () => void;

let _postRegisterHydrate: RegisterModelHydrateHook | null = null;

export function setRegisterModelHydrateHook(fn: RegisterModelHydrateHook | null): void {
  _postRegisterHydrate = fn;
}

function schedulePostRegisterHydrate(): void {
  const fn = _postRegisterHydrate;
  if (!fn) return;
  try {
    fn();
  } catch {
    /* hydrate is best-effort; failures are surfaced by hydrate itself */
  }
}

function totalFileSize(files: readonly RegisterModelFile[]): number {
  return files.reduce((acc, file) => acc + (file.sizeBytes || 0), 0);
}

/**
 * Call `rac_register_model_from_url_proto` in the commons WASM module to build
 * and persist the canonical `ModelInfo` — matching Swift's `registerModelFromUrl`
 * which delegates to this same ABI. Returns null when the WASM export is not yet
 * available (WASM rebuild pending), allowing the caller to fall back.
 */
function registerModelInfoViaWasm(
  request: RegisterModelFromUrlRequest,
): ModelInfo | null {
  type RegisterModule = ReturnType<typeof tryRunanywhereModule> & RegisterModelFromUrlModule;
  const mod = tryRunanywhereModule() as RegisterModule | null;
  if (!mod) return null;
  if (typeof mod._rac_register_model_from_url_proto !== 'function') return null;

  const bridge = new ProtoWasmBridge(mod, _storageLogger);
  const requestBytes = RegisterModelFromUrlRequestCodec.encode(request).finish();
  return bridge.withHeapBytes(requestBytes, (ptr, size) => (
    bridge.callResultProto(
      ModelInfoCodec,
      (outBuffer) => mod._rac_register_model_from_url_proto!(ptr, size, outBuffer),
      'rac_register_model_from_url_proto',
    )
  ));
}

/**
 * Fallback id derivation used only when the WASM export is unavailable.
 * Matches the subset of `rac_model_generate_id` that strips known model
 * extensions (.gguf, .onnx, .ort, .bin) in addition to .gz/.bz2.
 */
function deriveIdFromUrlFallback(url: string): string {
  const trailing = url.split('?')[0].split('/').pop() ?? '';
  if (!trailing) return `model-${Date.now()}`;
  return trailing
    .replace(/\.(gz|bz2|tar|zip)$/i, '')
    .replace(/\.(gguf|onnx|ort|bin)$/i, '');
}

function toMultiFileArtifact(
  files: readonly RegisterModelFile[],
): { artifact: MultiFileArtifact; expected: ExpectedModelFiles; descriptors: ModelFileDescriptor[] } {
  const descriptors: ModelFileDescriptor[] = files.map((file) => ({
    url: file.url,
    filename: file.filename,
    isRequired: file.isRequired ?? true,
    sizeBytes: file.sizeBytes,
    relativePath: file.filename,
    destinationPath: file.filename,
    role: file.role,
  }));
  return {
    artifact: { files: descriptors },
    expected: {
      files: descriptors,
      rootDirectory: '',
      requiredPatterns: descriptors.filter((f) => f.isRequired).map((f) => f.filename),
      optionalPatterns: descriptors.filter((f) => !f.isRequired).map((f) => f.filename),
      description: '',
    },
    descriptors,
  };
}

/**
 * Build a hand-rolled `ModelInfo` for a single-file remote model. Used as
 * a fallback when the `_rac_register_model_from_url_proto` WASM export is
 * not yet available (WASM rebuild pending). The id produced here does strip
 * the most common model extensions to reduce cross-SDK divergence, but full
 * parity requires the WASM export.
 */
function buildSingleFileModelInfoFallback(
  url: string,
  name: string,
  framework: InferenceFramework,
  options: RegisterModelOptions,
): ModelInfo {
  const now = Date.now();
  const id = options.id ?? deriveIdFromUrlFallback(url);
  const downloadSize = options.downloadSizeBytes ?? options.memoryRequirement ?? 0;
  return {
    id,
    name,
    category: options.modality ?? ModelCategory.MODEL_CATEGORY_LANGUAGE,
    format: options.format ?? ModelFormat.MODEL_FORMAT_UNSPECIFIED,
    framework,
    downloadUrl: url,
    localPath: '',
    downloadSizeBytes: downloadSize,
    contextLength: options.contextLength ?? 0,
    supportsThinking: options.supportsThinking ?? false,
    supportsLora: options.supportsLora ?? false,
    description: options.description ?? '',
    source: options.source ?? ModelSource.MODEL_SOURCE_REMOTE,
    createdAtUnixMs: now,
    updatedAtUnixMs: now,
    memoryRequiredBytes: options.memoryRequirement,
    artifactType: options.artifactType ?? ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
  };
}

function buildMultiFileModelInfo(options: RegisterMultiFileOptions): ModelInfo {
  const now = Date.now();
  const { artifact, expected } = toMultiFileArtifact(options.files);
  expected.rootDirectory = options.id;
  expected.description = `${options.name} primary model and companion artifacts`;
  const downloadSize = options.downloadSizeBytes ?? totalFileSize(options.files);
  // Pick the first PRIMARY_MODEL url for downloadUrl (or first file) so the
  // existing single-URL planners can still resolve a head pointer.
  const primary = options.files.find((f) => f.role === ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL)
    ?? options.files[0];
  return {
    id: options.id,
    name: options.name,
    category: options.modality ?? ModelCategory.MODEL_CATEGORY_LANGUAGE,
    format: options.format ?? ModelFormat.MODEL_FORMAT_UNSPECIFIED,
    framework: options.framework,
    downloadUrl: primary?.url ?? '',
    localPath: '',
    downloadSizeBytes: downloadSize,
    contextLength: options.contextLength ?? 0,
    supportsThinking: options.supportsThinking ?? false,
    supportsLora: options.supportsLora ?? false,
    description: options.description ?? '',
    source: options.source ?? ModelSource.MODEL_SOURCE_REMOTE,
    createdAtUnixMs: now,
    updatedAtUnixMs: now,
    memoryRequiredBytes: options.memoryRequirement,
    multiFile: artifact,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE,
    expectedFiles: expected,
  };
}

/**
 * Register a single-file remote model by URL. Mirrors Swift's
 * `RunAnywhere.registerModel(id:name:url:framework:...)`.
 *
 * Delegates the build-and-save flow to `rac_register_model_from_url_proto`
 * in the commons WASM (matching Swift which delegates to the same C ABI).
 * The WASM call handles id generation (extension stripping), format detection,
 * and framework→category mapping — ensuring cross-SDK catalog parity.
 *
 * After the WASM call, any options fields not yet modelled by
 * `RegisterModelFromUrlRequest` (id override, memoryRequirement,
 * supportsThinking, supportsLora, artifactType, contextLength, description,
 * downloadSizeBytes) are applied as a needsResave overlay and the updated
 * entry is persisted via `ModelRegistry.updateModel`, mirroring Swift's
 * needsResave pattern.
 *
 * When the WASM export is not yet available (WASM rebuild pending), falls
 * back to the previous hand-rolled path to keep existing apps working.
 */
export function registerModelFromUrl(
  url: string,
  name: string,
  framework: InferenceFramework,
  options: RegisterModelOptions = {},
): ModelInfo {
  const request: RegisterModelFromUrlRequest = {
    url,
    name,
    framework,
    category: options.modality,
    source: options.source,
  };

  const wasmModel = registerModelInfoViaWasm(request);

  if (wasmModel) {
    const now = Date.now();
    let model = wasmModel;
    let needsResave = false;

    if (options.id !== undefined && options.id !== model.id) {
      model = { ...model, id: options.id };
      needsResave = true;
    }
    if (options.memoryRequirement !== undefined) {
      model = { ...model, downloadSizeBytes: options.memoryRequirement, memoryRequiredBytes: options.memoryRequirement };
      needsResave = true;
    }
    if (options.downloadSizeBytes !== undefined && options.memoryRequirement === undefined) {
      model = { ...model, downloadSizeBytes: options.downloadSizeBytes };
      needsResave = true;
    }
    if (options.supportsThinking) {
      model = { ...model, supportsThinking: true };
      needsResave = true;
    }
    if (options.supportsLora) {
      model = { ...model, supportsLora: true };
      needsResave = true;
    }
    if (options.artifactType !== undefined) {
      model = { ...model, artifactType: options.artifactType };
      needsResave = true;
    }
    if (options.contextLength !== undefined) {
      model = { ...model, contextLength: options.contextLength };
      needsResave = true;
    }
    if (options.description !== undefined && options.description !== '') {
      model = { ...model, description: options.description };
      needsResave = true;
    }
    if (needsResave) {
      model = { ...model, updatedAtUnixMs: now };
      if (!ModelRegistry.updateModel(model)) {
        throw SDKException.backendNotAvailable(
          'registerModel',
          `Model registry update rejected '${model.id}'. Ensure a backend module is registered before calling RunAnywhere.registerModel().`,
        );
      }
    }
    schedulePostRegisterHydrate();
    return model;
  }

  const model = buildSingleFileModelInfoFallback(url, name, framework, options);
  if (!ModelRegistry.registerModel(model)) {
    throw SDKException.backendNotAvailable(
      'registerModel',
      `Model registry rejected '${model.id}'. Ensure a backend module is registered before calling RunAnywhere.registerModel().`,
    );
  }
  schedulePostRegisterHydrate();
  return model;
}

/**
 * Register an archive-packaged model (tar.gz / zip / tar.xz). The SDK
 * patches the `artifactType` onto the resulting `ModelInfo` so the
 * download orchestrator can route through its extraction path.
 */
export function registerModelArchive(
  url: string,
  name: string,
  framework: InferenceFramework,
  archiveType: ModelArtifactType,
  options: RegisterModelOptions = {},
): ModelInfo {
  return registerModelFromUrl(url, name, framework, {
    ...options,
    artifactType: archiveType,
  });
}

/**
 * Register a multi-file model (VLM = primary GGUF + mmproj sidecar,
 * embedding = `model.onnx` + `vocab.txt`). The SDK assembles the
 * `MultiFileArtifact` proto + `ExpectedModelFiles` manifest from the
 * provided file list — example apps must not build those structures.
 */
export function registerModelMultiFile(options: RegisterMultiFileOptions): ModelInfo {
  if (options.files.length === 0) {
    throw new Error('registerModel(multiFile): files must not be empty');
  }
  const model = buildMultiFileModelInfo(options);
  if (!ModelRegistry.registerModel(model)) {
    throw SDKException.backendNotAvailable(
      'registerModel',
      `Model registry rejected '${model.id}'. Ensure a backend module is registered before calling RunAnywhere.registerModel().`,
    );
  }
  schedulePostRegisterHydrate();
  return model;
}
