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
  ModelFileDescriptor,
  ModelInfo,
  MultiFileArtifact,
} from '@runanywhere/proto-ts/model_types';
import {
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelSource,
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
import { ModelRegistry } from './RunAnywhere+ModelRegistry';

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

function deriveIdFromUrl(url: string): string {
  const trailing = url.split('?')[0].split('/').pop() ?? '';
  return trailing.length > 0 ? trailing : `model-${Date.now()}`;
}

function totalFileSize(files: readonly RegisterModelFile[]): number {
  return files.reduce((acc, file) => acc + (file.sizeBytes || 0), 0);
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

function buildSingleFileModelInfo(
  url: string,
  name: string,
  framework: InferenceFramework,
  options: RegisterModelOptions,
): ModelInfo {
  const now = Date.now();
  const id = options.id ?? deriveIdFromUrl(url);
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
 * `RunAnywhere.registerModel(id:name:url:framework:...)` — the SDK builds
 * the full `ModelInfo` proto so example apps only describe the catalog
 * entry, never assemble the proto message themselves.
 */
export function registerModelFromUrl(
  url: string,
  name: string,
  framework: InferenceFramework,
  options: RegisterModelOptions = {},
): ModelInfo {
  const model = buildSingleFileModelInfo(url, name, framework, options);
  if (!ModelRegistry.registerModel(model)) {
    throw SDKException.backendNotAvailable(
      'registerModel',
      `Model registry rejected '${model.id}'. Ensure a backend module is registered before calling RunAnywhere.registerModel().`,
    );
  }
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
  return model;
}
