import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  ModelArtifactType,
  ModelCategory,
  ModelInfo as ModelInfoMessage,
} from '@runanywhere/proto-ts/model_types';
import {
  StorageDeleteRequest,
  StorageDeleteResult,
  StorageInfoRequest,
} from '@runanywhere/proto-ts/storage_types';
import {
  BrowserStorageAnalyzerAdapter,
  StorageAdapter,
  type BrowserStorageAnalyzerModule,
} from '../../../src/Adapters/StorageAdapter';
import { ModelLifecycleAdapter } from '../../../src/Adapters/ModelLifecycleAdapter';
import { ModelRegistryAdapter } from '../../../src/Adapters/ModelRegistryAdapter';

type Trampoline = (...args: number[]) => number | bigint | void;

const CALLBACKS = {
  size: 68,
  calculateDirSize: 8,
  getFileSize: 16,
  pathExists: 4,
  getAvailableSpace: 28,
  getTotalSpace: 24,
  deletePath: 44,
  isModelLoaded: 52,
  unloadModel: 60,
  userData: 64,
} as const;

const DIRECTORY_MODE = 0o040000;
const FILE_MODE = 0o100000;

interface FSNode {
  readonly kind: 'directory' | 'file';
  readonly size: number;
}

class MemoryFS {
  private readonly nodes = new Map<string, FSNode>();

  addDirectory(path: string): void {
    this.nodes.set(path, { kind: 'directory', size: 0 });
  }

  addFile(path: string, size: number): void {
    this.nodes.set(path, { kind: 'file', size });
  }

  analyzePath(path: string): { exists: boolean } {
    return { exists: this.nodes.has(path) };
  }

  stat(path: string): { size: number; mode: number } {
    const node = this.nodes.get(path);
    if (!node) throw new Error(`ENOENT: ${path}`);
    return {
      size: node.size,
      mode: node.kind === 'directory' ? DIRECTORY_MODE : FILE_MODE,
    };
  }

  readdir(path: string): string[] {
    const node = this.nodes.get(path);
    if (!node || node.kind !== 'directory') throw new Error(`ENOTDIR: ${path}`);
    const prefix = path.endsWith('/') ? path : `${path}/`;
    const names = new Set<string>();
    for (const candidate of this.nodes.keys()) {
      if (!candidate.startsWith(prefix)) continue;
      const relative = candidate.slice(prefix.length);
      if (relative && !relative.includes('/')) names.add(relative);
    }
    return ['.', '..', ...names];
  }

  isDir(mode: number): boolean {
    return (mode & 0o170000) === DIRECTORY_MODE;
  }

  unlink(path: string): void {
    const node = this.nodes.get(path);
    if (!node || node.kind !== 'file') throw new Error(`ENOENT: ${path}`);
    this.nodes.delete(path);
  }

  rmdir(path: string): void {
    const node = this.nodes.get(path);
    if (!node || node.kind !== 'directory') throw new Error(`ENOTDIR: ${path}`);
    if (this.readdir(path).length > 2) throw new Error(`ENOTEMPTY: ${path}`);
    this.nodes.delete(path);
  }
}

interface FakeModuleHandle {
  readonly module: BrowserStorageAnalyzerModule;
  readonly fs: MemoryFS;
  readonly trampolines: Map<number, Trampoline>;
  readonly lifecycle: string[];
  readonly callbacksPtr: number;
  allocateString(value: string): number;
  readI32(ptr: number): number;
  setNativeDeletePath(path: string): void;
}

function createFakeModule(fs: MemoryFS): FakeModuleHandle {
  const memory = new ArrayBuffer(1 << 20);
  const heap = new Uint8Array(memory);
  const view = new DataView(memory);
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  const trampolines = new Map<number, Trampoline>();
  const lifecycle: string[] = [];
  let nextPtr = 512;
  let nextTrampoline = 10_000;
  let callbacksPtr = 0;
  let nativeDeletePath = '';

  const allocate = (size: number): number => {
    const ptr = nextPtr;
    nextPtr += Math.max(8, (size + 7) & ~7);
    return ptr;
  };
  const allocateString = (value: string): number => {
    const bytes = encoder.encode(value);
    const ptr = allocate(bytes.length + 1);
    heap.set(bytes, ptr);
    heap[ptr + bytes.length] = 0;
    return ptr;
  };
  const readString = (ptr: number): string => {
    let end = ptr;
    while (end < heap.length && heap[end] !== 0) end += 1;
    return decoder.decode(heap.subarray(ptr, end));
  };
  const writeDeleteResult = (
    outResultPtr: number,
    result: ReturnType<typeof StorageDeleteResult.fromPartial>,
  ): void => {
    const bytes = StorageDeleteResult.encode(result).finish();
    const dataPtr = allocate(Math.max(bytes.length, 1));
    heap.set(bytes, dataPtr);
    view.setInt32(outResultPtr, dataPtr, true);
    view.setInt32(outResultPtr + 4, bytes.length, true);
    view.setInt32(outResultPtr + 8, 0, true);
    view.setInt32(outResultPtr + 12, 0, true);
  };

  const moduleShape: Partial<BrowserStorageAnalyzerModule> = {
    HEAPU8: heap,
    HEAPU32: new Uint32Array(memory),
    HEAP32: new Int32Array(memory),
    FS: fs,
    _malloc: allocate,
    _free(ptr: number): void { lifecycle.push(`free:${ptr}`); },
    addFunction(callback: Trampoline): number {
      const ptr = nextTrampoline++;
      trampolines.set(ptr, callback);
      return ptr;
    },
    removeFunction(ptr: number): void {
      lifecycle.push(`remove:${ptr}`);
      trampolines.delete(ptr);
    },
    setValue(ptr: number, value: number, type: string): void {
      if (type === 'i8') view.setInt8(ptr, value);
      else view.setInt32(ptr, value, true);
    },
    getValue(ptr: number): number { return view.getInt32(ptr, true); },
    UTF8ToString: readString,
    stringToUTF8(value: string, ptr: number, maxBytes: number): number {
      const bytes = encoder.encode(value).subarray(0, Math.max(0, maxBytes - 1));
      heap.set(bytes, ptr);
      heap[ptr + bytes.length] = 0;
      return bytes.length;
    },
    lengthBytesUTF8(value: string): number { return encoder.encode(value).length; },

    _rac_storage_analyzer_create(ptr: number, outHandlePtr: number): number {
      callbacksPtr = ptr;
      view.setInt32(outHandlePtr, 777, true);
      lifecycle.push('create');
      return 0;
    },
    _rac_storage_analyzer_destroy(handle: number): void {
      lifecycle.push(`destroy:${handle}`);
    },
    _rac_get_model_registry: () => 333,

    _rac_proto_buffer_init(bufferPtr: number): void {
      for (let offset = 0; offset < 16; offset += 4) {
        view.setInt32(bufferPtr + offset, 0, true);
      }
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_storage_analyzer_delete_proto(
      _handle: number,
      _registryHandle: number,
      requestPtr: number,
      requestSize: number,
      outResultPtr: number,
    ): number {
      lifecycle.push('native-delete');
      const request = StorageDeleteRequest.decode(heap.slice(requestPtr, requestPtr + requestSize));
      const deletedModelIds: string[] = [];
      const failedModelIds: string[] = [];
      for (const modelId of request.modelIds) {
        const loadedPointer = view.getInt32(callbacksPtr + CALLBACKS.isModelLoaded, true);
        const loadedCallback = trampolines.get(loadedPointer);
        const modelIdPtr = allocateString(modelId);
        const outIsLoadedPtr = allocate(4);
        view.setInt32(outIsLoadedPtr, 0, true);
        const loadedResult = Number(loadedCallback?.(modelIdPtr, outIsLoadedPtr, 0) ?? -1);
        if (loadedResult !== 0 || view.getInt32(outIsLoadedPtr, true) !== 0) {
          failedModelIds.push(modelId);
          continue;
        }
        const deletePointer = view.getInt32(callbacksPtr + CALLBACKS.deletePath, true);
        const deleteCallback = trampolines.get(deletePointer);
        const pathPtr = allocateString(nativeDeletePath);
        lifecycle.push('memfs-delete');
        const result = Number(deleteCallback?.(pathPtr, 1, 0) ?? -1);
        if (result === 0) deletedModelIds.push(modelId);
        else failedModelIds.push(modelId);
      }
      writeDeleteResult(outResultPtr, StorageDeleteResult.fromPartial({
        success: failedModelIds.length === 0,
        deletedModelIds,
        failedModelIds,
        filesDeleted: deletedModelIds.length > 0,
        registryUpdated: deletedModelIds.length > 0,
      }));
      return 0;
    },

    _rac_wasm_sizeof_storage_callbacks: () => CALLBACKS.size,
    _rac_wasm_offsetof_storage_callbacks_calculate_dir_size: () => CALLBACKS.calculateDirSize,
    _rac_wasm_offsetof_storage_callbacks_get_file_size: () => CALLBACKS.getFileSize,
    _rac_wasm_offsetof_storage_callbacks_path_exists: () => CALLBACKS.pathExists,
    _rac_wasm_offsetof_storage_callbacks_get_available_space: () => CALLBACKS.getAvailableSpace,
    _rac_wasm_offsetof_storage_callbacks_get_total_space: () => CALLBACKS.getTotalSpace,
    _rac_wasm_offsetof_storage_callbacks_delete_path: () => CALLBACKS.deletePath,
    _rac_wasm_offsetof_storage_callbacks_is_model_loaded: () => CALLBACKS.isModelLoaded,
    _rac_wasm_offsetof_storage_callbacks_unload_model: () => CALLBACKS.unloadModel,
    _rac_wasm_offsetof_storage_callbacks_user_data: () => CALLBACKS.userData,
  };

  return {
    module: moduleShape as BrowserStorageAnalyzerModule,
    fs,
    trampolines,
    lifecycle,
    get callbacksPtr() { return callbacksPtr; },
    allocateString,
    readI32: (ptr: number) => view.getInt32(ptr, true),
    setNativeDeletePath: (path: string) => { nativeDeletePath = path; },
  };
}

function callback(handle: FakeModuleHandle, offset: number): Trampoline {
  const tableIndex = handle.readI32(handle.callbacksPtr + offset);
  const trampoline = handle.trampolines.get(tableIndex);
  if (!trampoline) throw new Error(`Missing callback at table index ${tableIndex}`);
  return trampoline;
}

function populateModelTree(fs: MemoryFS, modelId: string): string {
  const paths = [
    '/opfs',
    '/opfs/RunAnywhere',
    '/opfs/RunAnywhere/Models',
    '/opfs/RunAnywhere/Models/ONNX',
    `/opfs/RunAnywhere/Models/ONNX/${modelId}`,
  ];
  for (const path of paths) fs.addDirectory(path);
  const modelPath = paths[paths.length - 1];
  fs.addFile(`${modelPath}/model.onnx`, 11);
  fs.addDirectory(`${modelPath}/tokens`);
  fs.addFile(`${modelPath}/tokens/tokens.txt`, 7);
  return modelPath;
}

describe('BrowserStorageAnalyzerAdapter', () => {
  let removeEntry: ReturnType<typeof vi.fn>;
  let getDirectory: ReturnType<typeof vi.fn>;
  let directory: FileSystemDirectoryHandle;

  beforeEach(() => {
    removeEntry = vi.fn(async () => undefined);
    const directoryShape: Partial<FileSystemDirectoryHandle> = {
      kind: 'directory',
      name: 'root',
      getDirectoryHandle: vi.fn(async () => directory),
      getFileHandle: vi.fn(async () => ({
        kind: 'file',
        name: 'model.onnx',
        getFile: async () => new File([], 'model.onnx'),
      }) as FileSystemFileHandle),
      removeEntry,
    };
    directory = directoryShape as FileSystemDirectoryHandle;
    getDirectory = vi.fn(async () => directory);
    vi.stubGlobal('navigator', {
      storage: {
        estimate: vi.fn(async () => ({ usage: 1_024, quota: 4_096 })),
        getDirectory,
      },
    });
  });

  afterEach(() => {
    StorageAdapter.clearDefaultHandles();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('scans diarization and segmentation lifecycle categories', async () => {
    const scanned: ModelCategory[] = [];
    vi.spyOn(ModelLifecycleAdapter, 'fromModule').mockReturnValue({
      supportsProtoLifecycle: () => true,
      currentModel: ({ category }: { category: ModelCategory }) => {
        scanned.push(category);
        return { found: false, modelId: '' };
      },
    } as unknown as ModelLifecycleAdapter);

    const handle = createFakeModule(new MemoryFS());
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    adapter.refreshLoadedModelState();

    expect(scanned).toContain(ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION);
    expect(scanned).toContain(ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION);
    adapter.cleanup();
  });

  it('uses compiler offsets for recursive MEMFS sizes and cached quota', async () => {
    const fs = new MemoryFS();
    const modelPath = populateModelTree(fs, 'vad-layout');
    const handle = createFakeModule(fs);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    const pathPtr = handle.allocateString(modelPath);
    const filePtr = handle.allocateString(`${modelPath}/model.onnx`);
    const isDirectoryPtr = handle.allocateString('    ');

    expect(callback(handle, CALLBACKS.calculateDirSize)(pathPtr, 0)).toBe(18n);
    expect(callback(handle, CALLBACKS.getFileSize)(filePtr, 0)).toBe(11n);
    expect(callback(handle, CALLBACKS.pathExists)(pathPtr, isDirectoryPtr, 0)).toBe(1);
    expect(handle.readI32(isDirectoryPtr)).toBe(1);
    expect(callback(handle, CALLBACKS.getTotalSpace)(0)).toBe(4_096n);
    expect(callback(handle, CALLBACKS.getAvailableSpace)(0)).toBe(3_072n);
    expect(StorageAdapter.tryDefault()).not.toBeNull();

    adapter.cleanup();
  });

  it('awaits recursive OPFS removal before committing the MEMFS deletion', async () => {
    const fs = new MemoryFS();
    const modelPath = populateModelTree(fs, 'vad-delete');
    const handle = createFakeModule(fs);
    vi.spyOn(ModelRegistryAdapter, 'tryDefault').mockReturnValue({
      list: () => ({
        models: [ModelInfoMessage.fromPartial({
          id: 'vad-delete',
          name: 'VAD delete',
          localPath: modelPath,
          isDownloaded: true,
          downloadSizeBytes: 18,
          artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
        })],
      }),
    } as unknown as ModelRegistryAdapter);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    const pathPtr = handle.allocateString(modelPath);

    await adapter.prepareDelete(StorageDeleteRequest.fromPartial({
      modelIds: ['vad-delete'],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
      allowPlatformDelete: true,
    }));
    expect(removeEntry).toHaveBeenCalledWith('vad-delete', { recursive: true });
    expect(callback(handle, CALLBACKS.deletePath)(pathPtr, 1, 0)).toBe(0);
    expect(fs.analyzePath(modelPath).exists).toBe(false);
    adapter.finishDelete();

    const unsafePtr = handle.allocateString('/tmp/not-a-model');
    expect(callback(handle, CALLBACKS.deletePath)(unsafePtr, 1, 0)).toBe(-259);
    adapter.cleanup();
  });

  it('leaves MEMFS intact and reports failure when persistent removal is denied', async () => {
    const fs = new MemoryFS();
    const modelPath = populateModelTree(fs, 'vad-denied');
    removeEntry.mockRejectedValueOnce(new DOMException('denied', 'NotAllowedError'));
    const handle = createFakeModule(fs);
    vi.spyOn(ModelRegistryAdapter, 'tryDefault').mockReturnValue({
      list: () => ({
        models: [ModelInfoMessage.fromPartial({
          id: 'vad-denied',
          name: 'VAD denied',
          localPath: modelPath,
          isDownloaded: true,
          downloadSizeBytes: 18,
          artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
        })],
      }),
    } as unknown as ModelRegistryAdapter);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    const pathPtr = handle.allocateString(modelPath);

    await adapter.prepareDelete(StorageDeleteRequest.fromPartial({
      modelIds: ['vad-denied'],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
      allowPlatformDelete: true,
    }));

    expect(callback(handle, CALLBACKS.deletePath)(pathPtr, 1, 0)).toBe(-187);
    expect(fs.analyzePath(modelPath).exists).toBe(true);
    adapter.finishDelete();
    adapter.cleanup();
  });

  it('drains a pending delete before shutdown destroys its analyzer', async () => {
    let resolveRemoval!: () => void;
    removeEntry.mockImplementationOnce(() => new Promise<void>((resolve) => {
      resolveRemoval = resolve;
    }));
    const fs = new MemoryFS();
    const modelPath = populateModelTree(fs, 'vad-shutdown');
    const handle = createFakeModule(fs);
    handle.setNativeDeletePath(modelPath);
    vi.spyOn(ModelRegistryAdapter, 'tryDefault').mockReturnValue({
      list: () => ({
        models: [ModelInfoMessage.fromPartial({
          id: 'vad-shutdown',
          name: 'VAD shutdown',
          localPath: modelPath,
          isDownloaded: true,
          downloadSizeBytes: 18,
          artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
        })],
      }),
      updateDownloadStatus: () => true,
    } as unknown as ModelRegistryAdapter);
    const browserAdapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    const storage = StorageAdapter.tryDefault();
    expect(storage).not.toBeNull();

    const deletion = storage!.delete(StorageDeleteRequest.fromPartial({
      modelIds: ['vad-shutdown'],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
      allowPlatformDelete: true,
    }));
    await vi.waitFor(() => expect(removeEntry).toHaveBeenCalledOnce());

    let shutdownSettled = false;
    const shutdown = StorageAdapter.prepareForShutdown(handle.module).then(() => {
      shutdownSettled = true;
      browserAdapter.cleanup();
    });
    await Promise.resolve();
    expect(shutdownSettled).toBe(false);
    expect(handle.lifecycle).not.toContain('destroy:777');

    resolveRemoval();
    const result = await deletion;
    await shutdown;

    expect(result?.success).toBe(true);
    expect(handle.lifecycle.indexOf('native-delete')).toBeGreaterThanOrEqual(0);
    expect(handle.lifecycle.indexOf('destroy:777')).toBeGreaterThan(
      handle.lifecycle.indexOf('native-delete'),
    );
    const staleInfo = vi.fn(() => 0);
    handle.module._rac_storage_analyzer_info_proto = staleInfo;
    expect(storage!.supportsProtoStorage()).toBe(false);
    expect(storage!.info(StorageInfoRequest.fromPartial({}))).toBeNull();
    expect(staleInfo).not.toHaveBeenCalled();
    await expect(storage!.delete(StorageDeleteRequest.fromPartial({
      modelIds: ['vad-shutdown'],
      deleteFiles: true,
      allowPlatformDelete: true,
    }))).rejects.toThrow('shutting down');

    const nextHandle = createFakeModule(new MemoryFS());
    const nextAdapter = await BrowserStorageAnalyzerAdapter.install(nextHandle.module);
    expect(StorageAdapter.tryDefault()).not.toBeNull();
    nextAdapter.cleanup();
  });

  it('rechecks loaded state after OPFS yields before touching MEMFS', async () => {
    let resolveRemoval!: () => void;
    removeEntry.mockImplementationOnce(() => new Promise<void>((resolve) => {
      resolveRemoval = resolve;
    }));
    let loaded = false;
    const unload = vi.fn(() => ({ success: true }));
    vi.spyOn(ModelLifecycleAdapter, 'fromModule').mockReturnValue({
      supportsProtoLifecycle: () => true,
      currentModel: ({ category }: { category: ModelCategory }) => (
        loaded && category === ModelCategory.MODEL_CATEGORY_LANGUAGE
          ? { found: true, modelId: 'vad-reloaded' }
          : { found: false, modelId: '' }
      ),
      unload,
    } as unknown as ModelLifecycleAdapter);
    const fs = new MemoryFS();
    const modelPath = populateModelTree(fs, 'vad-reloaded');
    const handle = createFakeModule(fs);
    handle.setNativeDeletePath(modelPath);
    vi.spyOn(ModelRegistryAdapter, 'tryDefault').mockReturnValue({
      list: () => ({
        models: [ModelInfoMessage.fromPartial({
          id: 'vad-reloaded',
          name: 'VAD reloaded',
          localPath: modelPath,
          isDownloaded: true,
          downloadSizeBytes: 18,
          artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
        })],
      }),
    } as unknown as ModelRegistryAdapter);
    const browserAdapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    const storage = StorageAdapter.tryDefault();
    expect(storage).not.toBeNull();

    const deletion = storage!.delete(StorageDeleteRequest.fromPartial({
      modelIds: ['vad-reloaded'],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
      allowPlatformDelete: true,
    }));
    await vi.waitFor(() => expect(removeEntry).toHaveBeenCalledOnce());

    // Simulate another task loading the model while removeEntry() owns the
    // browser event loop. Native must see this fresh state and refuse MEMFS
    // deletion rather than relying on prepareDelete's earlier snapshot.
    loaded = true;
    resolveRemoval();
    const result = await deletion;

    expect(result?.success).toBe(false);
    expect(result?.failedModelIds).toContain('vad-reloaded');
    expect(handle.lifecycle).not.toContain('memfs-delete');
    expect(fs.analyzePath(modelPath).exists).toBe(true);
    expect(unload).not.toHaveBeenCalled();
    browserAdapter.cleanup();
  });

  it('does not unload or pre-delete bytes for a stale attached delete plan', async () => {
    const fs = new MemoryFS();
    const modelPath = populateModelTree(fs, 'vad-stale-plan');
    const handle = createFakeModule(fs);
    const unload = vi.fn(() => ({ success: true }));
    vi.spyOn(ModelLifecycleAdapter, 'fromModule').mockReturnValue({
      supportsProtoLifecycle: () => true,
      currentModel: ({ category }: { category: ModelCategory }) => (
        category === ModelCategory.MODEL_CATEGORY_LANGUAGE
          ? { found: true, modelId: 'vad-stale-plan' }
          : { found: false, modelId: '' }
      ),
      unload,
    } as unknown as ModelLifecycleAdapter);
    vi.spyOn(ModelRegistryAdapter, 'tryDefault').mockReturnValue({
      list: () => ({
        models: [ModelInfoMessage.fromPartial({
          id: 'vad-stale-plan',
          name: 'VAD stale plan',
          localPath: modelPath,
          isDownloaded: true,
          downloadSizeBytes: 18,
          artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
        })],
      }),
    } as unknown as ModelRegistryAdapter);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);

    await adapter.prepareDelete(StorageDeleteRequest.fromPartial({
      modelIds: ['vad-stale-plan'],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
      allowPlatformDelete: true,
      requirePlanMatch: true,
      plan: {
        candidates: [{
          modelId: 'vad-stale-plan',
          localPath: `${modelPath}-old`,
        }],
      },
    }));

    expect(removeEntry).not.toHaveBeenCalled();
    expect(unload).not.toHaveBeenCalled();
    expect(fs.analyzePath(modelPath).exists).toBe(true);
    adapter.finishDelete();
    adapter.cleanup();
  });

  it('uses the native last-wins rule for duplicate plan candidates', async () => {
    const fs = new MemoryFS();
    const modelPath = populateModelTree(fs, 'vad-duplicate-plan');
    const handle = createFakeModule(fs);
    const unload = vi.fn(() => ({ success: true }));
    vi.spyOn(ModelLifecycleAdapter, 'fromModule').mockReturnValue({
      supportsProtoLifecycle: () => true,
      currentModel: ({ category }: { category: ModelCategory }) => (
        category === ModelCategory.MODEL_CATEGORY_LANGUAGE
          ? { found: true, modelId: 'vad-duplicate-plan' }
          : { found: false, modelId: '' }
      ),
      unload,
    } as unknown as ModelLifecycleAdapter);
    vi.spyOn(ModelRegistryAdapter, 'tryDefault').mockReturnValue({
      list: () => ({
        models: [ModelInfoMessage.fromPartial({
          id: 'vad-duplicate-plan',
          name: 'VAD duplicate plan',
          localPath: modelPath,
          isDownloaded: true,
          downloadSizeBytes: 18,
          artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_DIRECTORY,
        })],
      }),
    } as unknown as ModelRegistryAdapter);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);

    await adapter.prepareDelete(StorageDeleteRequest.fromPartial({
      modelIds: ['vad-duplicate-plan'],
      deleteFiles: true,
      clearRegistryPaths: true,
      unloadIfLoaded: true,
      allowPlatformDelete: true,
      requirePlanMatch: true,
      plan: {
        candidates: [
          { modelId: 'vad-duplicate-plan', localPath: modelPath },
          { modelId: 'vad-duplicate-plan', localPath: `${modelPath}-stale` },
        ],
      },
    }));

    expect(removeEntry).not.toHaveBeenCalled();
    expect(unload).not.toHaveBeenCalled();
    expect(fs.analyzePath(modelPath).exists).toBe(true);
    adapter.finishDelete();
    adapter.cleanup();
  });

  it('uses downloaded registry metadata on a cold start without restoring OPFS bytes', async () => {
    const fs = new MemoryFS();
    const handle = createFakeModule(fs);
    const localPath = '/opfs/RunAnywhere/Models/ONNX/cold-vad';
    const model = ModelInfoMessage.fromPartial({
      id: 'cold-vad',
      name: 'Cold VAD',
      localPath,
      isDownloaded: true,
      downloadSizeBytes: 1_000,
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE,
      multiFile: {
        files: [
          { filename: 'model.onnx', relativePath: 'model.onnx', sizeBytes: 600 },
          { filename: 'tokens.txt', relativePath: 'tokens/tokens.txt', sizeBytes: 400 },
        ],
      },
    });
    vi.spyOn(ModelRegistryAdapter, 'tryDefault').mockReturnValue({
      list: () => ({ models: [model] }),
    } as unknown as ModelRegistryAdapter);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    const pathPtr = handle.allocateString(localPath);
    const childPtr = handle.allocateString(`${localPath}/model.onnx`);
    const modelsRootPtr = handle.allocateString('/opfs/RunAnywhere/Models');
    const isDirectoryPtr = handle.allocateString('    ');

    adapter.refreshStorageState();

    expect(callback(handle, CALLBACKS.calculateDirSize)(pathPtr, 0)).toBe(1_000n);
    expect(callback(handle, CALLBACKS.calculateDirSize)(modelsRootPtr, 0)).toBe(1_000n);
    expect(callback(handle, CALLBACKS.getFileSize)(childPtr, 0)).toBe(600n);
    expect(callback(handle, CALLBACKS.pathExists)(pathPtr, isDirectoryPtr, 0)).toBe(1);
    expect(handle.readI32(isDirectoryPtr)).toBe(1);
    expect(getDirectory).not.toHaveBeenCalled();
    adapter.cleanup();
  });

  it('reports cached lifecycle state without re-entering native callbacks', async () => {
    const fs = new MemoryFS();
    const handle = createFakeModule(fs);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);
    const modelIdPtr = handle.allocateString('not-loaded');
    const outLoadedPtr = handle.allocateString('    ');

    adapter.refreshLoadedModelState();
    expect(callback(handle, CALLBACKS.isModelLoaded)(modelIdPtr, outLoadedPtr, 0)).toBe(0);
    expect(handle.readI32(outLoadedPtr)).toBe(0);
    expect(callback(handle, CALLBACKS.unloadModel)(modelIdPtr, 0)).toBe(0);
    adapter.cleanup();
  });

  it('destroys the analyzer before releasing callback trampolines', async () => {
    const fs = new MemoryFS();
    const handle = createFakeModule(fs);
    const adapter = await BrowserStorageAnalyzerAdapter.install(handle.module);

    adapter.cleanup();

    const destroyIndex = handle.lifecycle.indexOf('destroy:777');
    const firstRemovalIndex = handle.lifecycle.findIndex((entry) => entry.startsWith('remove:'));
    expect(destroyIndex).toBeGreaterThanOrEqual(0);
    expect(firstRemovalIndex).toBeGreaterThan(destroyIndex);
    expect(StorageAdapter.tryDefault()).toBeNull();
  });
});
