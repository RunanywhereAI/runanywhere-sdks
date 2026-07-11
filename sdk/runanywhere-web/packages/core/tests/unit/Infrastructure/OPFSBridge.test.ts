import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  OPFSBridge,
  type ModuleLike,
} from '../../../src/Infrastructure/OPFSBridge.js';

const MODEL_PATH = '/opfs/Models/model.gguf';
const BUNDLE_PATH = '/opfs/Models/speech-bundle';
const FILE_MODE = 0o100000;
const DIRECTORY_MODE = 0o040000;

interface FakeMemfsModule {
  module: ModuleLike;
  files: Map<string, Uint8Array>;
  writeFile: (path: string, data: Uint8Array) => void;
}

describe('OPFSBridge multi-module hydration', () => {
  afterEach(() => {
    OPFSBridge.setPersistentRoot(null);
    vi.restoreAllMocks();
  });

  it('hydrates a replacement module even when a surviving sibling already has the model', async () => {
    const persisted = new Uint8Array([7, 4, 2, 9]);
    const getFile = installPersistentFile(persisted);
    const sibling = createMemfsModule({ [MODEL_PATH]: persisted });
    const replacement = createMemfsModule();

    await OPFSBridge.ensureModelPathReadyForLoad([
      sibling.module,
      replacement.module,
      {}, // Registered objects without an FS surface are not hydration targets.
    ], MODEL_PATH);

    expect(replacement.files.get(MODEL_PATH)).toEqual(persisted);
    expect(replacement.writeFile).toHaveBeenCalledOnce();
    expect(getFile).toHaveBeenCalledOnce();
  });

  it('does not read OPFS when every filesystem module already has the model', async () => {
    const persisted = new Uint8Array([1, 2, 3]);
    const getDirectoryHandle = vi.fn(() => {
      throw new Error('OPFS should not be read on the all-modules-ready fast path');
    });
    OPFSBridge.setPersistentRoot({
      kind: 'directory',
      name: 'root',
      getDirectoryHandle,
    } as unknown as FileSystemDirectoryHandle);
    const first = createMemfsModule({ [MODEL_PATH]: persisted });
    const second = createMemfsModule({ [MODEL_PATH]: persisted });

    await OPFSBridge.ensureModelPathReadyForLoad(
      [first.module, second.module],
      MODEL_PATH,
    );

    expect(getDirectoryHandle).not.toHaveBeenCalled();
    expect(first.writeFile).not.toHaveBeenCalled();
    expect(second.writeFile).not.toHaveBeenCalled();
  });

  it('rejects when any replacement filesystem cannot receive the restored model', async () => {
    const persisted = new Uint8Array([8, 6, 7, 5, 3, 0, 9]);
    installPersistentFile(persisted);
    const sibling = createMemfsModule({ [MODEL_PATH]: persisted });
    const replacement = createMemfsModule({}, true);

    await expect(OPFSBridge.ensureModelPathReadyForLoad(
      [sibling.module, replacement.module],
      MODEL_PATH,
    )).rejects.toThrow('missing from 1 MEMFS module');
  });

  it('completes a partially hydrated directory from the full persisted bundle', async () => {
    const model = new Uint8Array([1, 3, 3, 7]);
    const tokens = new Uint8Array([2, 4, 6, 8]);
    installPersistentDirectory({
      'model.onnx': model,
      'tokens.txt': tokens,
    });
    const partial = createMemfsModule({
      [`${BUNDLE_PATH}/model.onnx`]: model,
    });

    await OPFSBridge.ensureModelPathReadyForLoad([partial.module], BUNDLE_PATH);

    expect(partial.files.get(`${BUNDLE_PATH}/model.onnx`)).toEqual(model);
    expect(partial.files.get(`${BUNDLE_PATH}/tokens.txt`)).toEqual(tokens);
    expect(partial.writeFile).toHaveBeenCalledOnce();
  });

  it('rejects a directory restore when any required companion file cannot be written', async () => {
    const model = new Uint8Array([1, 3, 3, 7]);
    const tokens = new Uint8Array([2, 4, 6, 8]);
    installPersistentDirectory({
      'model.onnx': model,
      'tokens.txt': tokens,
    });
    const partial = createMemfsModule({
      [`${BUNDLE_PATH}/model.onnx`]: model,
    }, true);

    await expect(OPFSBridge.ensureModelPathReadyForLoad(
      [partial.module],
      BUNDLE_PATH,
    )).rejects.toThrow('forced MEMFS write failure');
  });
});

function installPersistentFile(bytes: Uint8Array): ReturnType<typeof vi.fn> {
  const owned = new Uint8Array(bytes.byteLength);
  owned.set(bytes);
  const getFile = vi.fn().mockResolvedValue(new Blob([owned.buffer]));
  const fileHandle = {
    kind: 'file',
    name: 'model.gguf',
    getFile,
  } as unknown as FileSystemFileHandle;
  const modelDirectory = {
    kind: 'directory',
    name: 'Models',
    getDirectoryHandle: vi.fn().mockRejectedValue(
      new DOMException('not a directory', 'NotFoundError'),
    ),
    getFileHandle: vi.fn().mockResolvedValue(fileHandle),
  } as unknown as FileSystemDirectoryHandle;
  const root = {
    kind: 'directory',
    name: 'root',
    getDirectoryHandle: vi.fn().mockImplementation(async (name: string) => {
      if (name === 'Models') return modelDirectory;
      throw new DOMException(`Missing directory: ${name}`, 'NotFoundError');
    }),
  } as unknown as FileSystemDirectoryHandle;
  OPFSBridge.setPersistentRoot(root);
  return getFile;
}

function installPersistentDirectory(files: Record<string, Uint8Array>): void {
  const fileHandles = new Map<string, FileSystemFileHandle>(
    Object.entries(files).map(([name, bytes]) => {
      const owned = new Uint8Array(bytes.byteLength);
      owned.set(bytes);
      return [name, {
        kind: 'file',
        name,
        getFile: vi.fn().mockResolvedValue(new Blob([owned.buffer])),
      } as unknown as FileSystemFileHandle];
    }),
  );
  const bundleDirectory = {
    kind: 'directory',
    name: 'speech-bundle',
    entries: async function* entries(): AsyncIterableIterator<[
      string,
      FileSystemHandle,
    ]> {
      for (const [name, handle] of fileHandles) yield [name, handle];
    },
  } as unknown as FileSystemDirectoryHandle;
  const modelDirectory = {
    kind: 'directory',
    name: 'Models',
    getDirectoryHandle: vi.fn().mockImplementation(async (name: string) => {
      if (name === 'speech-bundle') return bundleDirectory;
      throw new DOMException(`Missing directory: ${name}`, 'NotFoundError');
    }),
  } as unknown as FileSystemDirectoryHandle;
  const root = {
    kind: 'directory',
    name: 'root',
    getDirectoryHandle: vi.fn().mockImplementation(async (name: string) => {
      if (name === 'Models') return modelDirectory;
      throw new DOMException(`Missing directory: ${name}`, 'NotFoundError');
    }),
  } as unknown as FileSystemDirectoryHandle;
  OPFSBridge.setPersistentRoot(root);
}

function createMemfsModule(
  initialFiles: Record<string, Uint8Array> = {},
  failWrites = false,
): FakeMemfsModule {
  const files = new Map<string, Uint8Array>(
    Object.entries(initialFiles).map(([path, bytes]) => [path, new Uint8Array(bytes)]),
  );
  const directories = new Set(['/', '/opfs', '/opfs/Models']);
  const writeFile = vi.fn((path: string, data: Uint8Array) => {
    if (failWrites) throw new Error('forced MEMFS write failure');
    files.set(path, new Uint8Array(data));
  });
  const fs = {
    readFile(path: string): Uint8Array {
      const bytes = files.get(path);
      if (!bytes) throw new Error(`ENOENT: ${path}`);
      return new Uint8Array(bytes);
    },
    writeFile,
    mkdir(path: string): void {
      directories.add(path);
    },
    unlink(path: string): void {
      files.delete(path);
    },
    stat(path: string): { size: number; mode: number } {
      const bytes = files.get(path);
      if (bytes) return { size: bytes.byteLength, mode: FILE_MODE };
      if (directories.has(path)) return { size: 4096, mode: DIRECTORY_MODE };
      throw new Error(`ENOENT: ${path}`);
    },
    analyzePath(path: string): { exists: boolean } {
      return { exists: files.has(path) || directories.has(path) };
    },
  };
  return {
    module: { FS: fs },
    files,
    writeFile,
  };
}
