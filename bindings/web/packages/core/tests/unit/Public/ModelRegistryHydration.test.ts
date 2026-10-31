import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  InferenceFramework,
  ModelInfo,
  ModelRegistryStatus,
} from '@runanywhere/proto-ts/model_types';
import { SDKCore } from '../../../src/Public/SDKCore.js';
import { ModelRegistry } from '../../../src/Public/Extensions/RunAnywhere+ModelRegistry.js';
import { OPFSBridge } from '../../../src/Infrastructure/OPFSBridge.js';
import * as FrameworkOPFSPaths from '../../../src/Infrastructure/FrameworkOPFSPaths.js';
import { EventBus } from '../../../src/Foundation/EventBus.js';

const MODEL_DIR = 'RunAnywhere/Models/LlamaCpp/test-model';
const MODEL_PATH = `/opfs/${MODEL_DIR}/model.gguf`;
const DOWNLOADED = ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED;
const LOADED = ModelRegistryStatus.MODEL_REGISTRY_STATUS_LOADED;
const REGISTERED = ModelRegistryStatus.MODEL_REGISTRY_STATUS_REGISTERED;

/** Persistent file handles only: no MEMFS module or byte restoration is installed. */
function installPersistentFiles(files: Record<string, number>): void {
  const directory = (prefix: string): FileSystemDirectoryHandle => {
    const children = (): string[] => [...new Set(Object.keys(files)
      .filter((path) => path.startsWith(prefix))
      .map((path) => path.slice(prefix.length).split('/')[0]))];
    const file = (name: string): FileSystemFileHandle => ({
      kind: 'file',
      name,
      getFile: async () => new File([new Uint8Array(files[`${prefix}${name}`])], name),
    } as unknown as FileSystemFileHandle);
    return {
      kind: 'directory',
      name: prefix,
      getDirectoryHandle: async (name: string) => {
        if (Object.keys(files).some((path) => path.startsWith(`${prefix}${name}/`))) {
          return directory(`${prefix}${name}/`);
        }
        throw new DOMException('Missing directory', 'NotFoundError');
      },
      getFileHandle: async (name: string) => {
        if (`${prefix}${name}` in files) return file(name);
        throw new DOMException('Missing file', 'NotFoundError');
      },
      values: async function* () {
        for (const name of children()) {
          yield `${prefix}${name}` in files ? file(name) : directory(`${prefix}${name}/`);
        }
      },
    } as unknown as FileSystemDirectoryHandle;
  };
  OPFSBridge.setPersistentRoot(directory(''));
}

function installRegistry(overrides: Partial<ModelInfo> = {}) {
  let model = ModelInfo.fromPartial({
    id: 'test-model',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    downloadUrl: 'https://example.test/model.gguf',
    downloadSizeBytes: 100,
    localPath: MODEL_PATH,
    registryStatus: DOWNLOADED,
    ...overrides,
  });
  vi.spyOn(ModelRegistry, 'listModels').mockImplementation(() => ({ models: [model] }));
  vi.spyOn(ModelRegistry, 'getModel').mockImplementation((id) => id === model.id ? model : null);
  const update = vi.spyOn(ModelRegistry, 'updateDownloadStatus').mockImplementation((id, path) => {
    expect(id).toBe(model.id);
    model = {
      ...model,
      localPath: path ?? '',
      registryStatus: path ? DOWNLOADED : REGISTERED,
    };
    return true;
  });
  return { update, current: () => model };
}

describe('OPFS model registry hydration and reconciliation', () => {
  beforeEach(() => {
    vi.spyOn(FrameworkOPFSPaths, 'frameworkOPFSDir').mockReturnValue('LlamaCpp');
  });

  afterEach(() => {
    OPFSBridge.setPersistentRoot(null);
    vi.restoreAllMocks();
  });

  it.each([DOWNLOADED, LOADED])(
    'preserves healthy OPFS-only downloads with registry status %s',
    async (registryStatus) => {
      installPersistentFiles({ [`${MODEL_DIR}/model.gguf`]: 100 });
      const registry = installRegistry({ registryStatus });
      const restore = vi.spyOn(OPFSBridge, 'restoreToMemfsAll');
      const publish = vi.spyOn(EventBus.shared, 'publish');

      await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(0);

      expect(registry.update).not.toHaveBeenCalled();
      expect(registry.current()).toMatchObject({ localPath: MODEL_PATH, registryStatus });
      expect(restore).not.toHaveBeenCalled();
      expect(publish).toHaveBeenCalledWith('models.hydrated', expect.any(Number), { count: 0 });
    },
  );

  it('links a previous-session OPFS download without materializing MEMFS and is idempotent', async () => {
    installPersistentFiles({ [`${MODEL_DIR}/model.gguf`]: 100 });
    const registry = installRegistry({ localPath: '', registryStatus: REGISTERED });

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(1);
    expect(registry.update).toHaveBeenCalledExactlyOnceWith('test-model', MODEL_PATH);
    expect(registry.current()).toMatchObject({ localPath: MODEL_PATH, registryStatus: DOWNLOADED });
    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(0);
    expect(registry.update).toHaveBeenCalledTimes(1);
  });

  it.each([DOWNLOADED, LOADED])('clears genuinely missing OPFS downloads with status %s', async (registryStatus) => {
    installPersistentFiles({});
    const registry = installRegistry({ registryStatus });

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(1);
    expect(registry.update).toHaveBeenCalledExactlyOnceWith('test-model', null);
    expect(registry.current()).toMatchObject({ localPath: '', registryStatus: REGISTERED });
    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(0);
  });

  it.each([0, 79])('clears an incomplete OPFS file containing %s of 100 expected bytes', async (size) => {
    installPersistentFiles({ [`${MODEL_DIR}/model.gguf`]: size });
    const registry = installRegistry();

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(1);
    expect(registry.update).toHaveBeenCalledExactlyOnceWith('test-model', null);
  });

  it('preserves an OPFS file at the existing 80 percent completeness threshold', async () => {
    installPersistentFiles({ [`${MODEL_DIR}/model.gguf`]: 80 });
    const registry = installRegistry();

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(0);
    expect(registry.update).not.toHaveBeenCalled();
  });

  it('does not link a partial OPFS download into a registered catalog row', async () => {
    installPersistentFiles({ [`${MODEL_DIR}/model.gguf`]: 10 });
    const registry = installRegistry({ localPath: '', registryStatus: REGISTERED });

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(0);
    expect(registry.update).not.toHaveBeenCalled();
  });

  it('links a nested extracted archive without requiring the removed archive blob', async () => {
    installPersistentFiles({ [`${MODEL_DIR}/nested/model.onnx`]: 100 });
    const registry = installRegistry({
      downloadUrl: 'https://example.test/model.tar.gz',
      localPath: '',
      registryStatus: REGISTERED,
    });

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(1);
    expect(registry.update).toHaveBeenCalledExactlyOnceWith('test-model', `/opfs/${MODEL_DIR}`);
  });

  it('clears a missing extracted archive directory', async () => {
    installPersistentFiles({});
    const registry = installRegistry({
      downloadUrl: 'https://example.test/model.tar.gz',
      localPath: `/opfs/${MODEL_DIR}`,
    });

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(1);
    expect(registry.update).toHaveBeenCalledExactlyOnceWith('test-model', null);
  });

  it.each([79, 100])('reconciles a multi-file model with %s primary-file bytes', async (size) => {
    installPersistentFiles({
      [`${MODEL_DIR}/model.gguf`]: size,
      [`${MODEL_DIR}/config.json`]: 10,
    });
    const registry = installRegistry({
      localPath: `/opfs/${MODEL_DIR}`,
      multiFile: {
        files: [
          { filename: 'model.gguf', url: '', isOptional: false, sizeBytes: 100 },
          { filename: 'config.json', url: '', isOptional: false, sizeBytes: 10 },
        ],
      },
    });

    await expect(SDKCore.hydrateModelRegistry()).resolves.toBe(size < 80 ? 1 : 0);
    if (size < 80) {
      expect(registry.update).toHaveBeenCalledExactlyOnceWith('test-model', null);
    } else {
      expect(registry.update).not.toHaveBeenCalled();
    }
  });
});
