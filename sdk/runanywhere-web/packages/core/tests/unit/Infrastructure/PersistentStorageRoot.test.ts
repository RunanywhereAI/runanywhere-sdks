import { afterEach, describe, expect, it, vi } from 'vitest';

import { LocalFileStorage } from '../../../src/Infrastructure/LocalFileStorage.js';
import { OPFSBridge } from '../../../src/Infrastructure/OPFSBridge.js';

interface LocalFileStorageInternals {
  dirHandle: FileSystemDirectoryHandle | null;
  _isReady: boolean;
  _hasStoredHandle: boolean;
}

function directoryHandle(name: string): FileSystemDirectoryHandle {
  return { name, kind: 'directory' } as FileSystemDirectoryHandle;
}

describe('persistent browser storage root', () => {
  afterEach(() => {
    OPFSBridge.setPersistentRoot(null);
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('commits a picked directory only after its handle is persisted', async () => {
    const previous = directoryHandle('previous');
    const selected = directoryHandle('selected');
    vi.stubGlobal('window', {
      showDirectoryPicker: vi.fn().mockResolvedValue(selected),
    });
    vi.stubGlobal('indexedDB', {
      open: vi.fn(() => {
        throw new Error('IndexedDB unavailable');
      }),
    });

    const storage = new LocalFileStorage();
    const internals = storage as unknown as LocalFileStorageInternals;
    internals.dirHandle = previous;
    internals._isReady = true;
    internals._hasStoredHandle = true;

    await expect(storage.chooseDirectory()).resolves.toBe(false);
    expect(storage.writableDirectoryHandle).toBe(previous);
    expect(storage.directoryName).toBe('previous');
  });

  it('routes persistent writes through the granted selected root', async () => {
    const write = vi.fn().mockResolvedValue(undefined);
    const close = vi.fn().mockResolvedValue(undefined);
    const fileHandle = {
      kind: 'file',
      name: 'model.onnx',
      createWritable: vi.fn().mockResolvedValue({ write, close }),
    } as unknown as FileSystemFileHandle;
    const modelDirectory = {
      kind: 'directory',
      name: 'Models',
      getFileHandle: vi.fn().mockResolvedValue(fileHandle),
    } as unknown as FileSystemDirectoryHandle;
    const selectedRoot = {
      kind: 'directory',
      name: 'selected',
      getDirectoryHandle: vi.fn().mockResolvedValue(modelDirectory),
    } as unknown as FileSystemDirectoryHandle;
    const defaultRoot = vi.fn();
    vi.stubGlobal('navigator', { storage: { getDirectory: defaultRoot } });

    OPFSBridge.setPersistentRoot(selectedRoot);
    await OPFSBridge.writeFileToOPFS(
      ['Models', 'model.onnx'],
      new Uint8Array([1, 2, 3]),
    );

    expect(defaultRoot).not.toHaveBeenCalled();
    expect(selectedRoot.getDirectoryHandle).toHaveBeenCalledWith('Models', { create: true });
    expect(modelDirectory.getFileHandle).toHaveBeenCalledWith('model.onnx', { create: true });
    expect(write).toHaveBeenCalledOnce();
    expect(close).toHaveBeenCalledOnce();
  });

  it('captures deletion roots and does not tombstone the same path in another folder', async () => {
    let finishRemoval: (() => void) | undefined;
    const removeFromA = vi.fn(() => new Promise<void>((resolve) => {
      finishRemoval = resolve;
    }));
    const directoryA = {
      kind: 'directory',
      name: 'Models',
      removeEntry: removeFromA,
    } as unknown as FileSystemDirectoryHandle;
    const rootA = {
      kind: 'directory',
      name: 'root-a',
      getDirectoryHandle: vi.fn().mockResolvedValue(directoryA),
    } as unknown as FileSystemDirectoryHandle;

    const modelInB = { kind: 'file', name: 'model.onnx' } as FileSystemFileHandle;
    const removeFromB = vi.fn();
    const directoryB = {
      kind: 'directory',
      name: 'Models',
      getFileHandle: vi.fn().mockResolvedValue(modelInB),
      removeEntry: removeFromB,
    } as unknown as FileSystemDirectoryHandle;
    const rootB = {
      kind: 'directory',
      name: 'root-b',
      getDirectoryHandle: vi.fn().mockResolvedValue(directoryB),
    } as unknown as FileSystemDirectoryHandle;

    OPFSBridge.setPersistentRoot(rootA);
    const removal = OPFSBridge.scheduleRemovePath('/opfs/Models/model.onnx');
    OPFSBridge.setPersistentRoot(rootB);

    await expect(OPFSBridge.exists('/opfs/Models/model.onnx')).resolves.toBe(true);
    await vi.waitFor(() => expect(removeFromA).toHaveBeenCalledOnce());
    expect(removeFromB).not.toHaveBeenCalled();
    finishRemoval?.();
    await removal;
    expect(removeFromA).toHaveBeenCalledWith('model.onnx', { recursive: true });
  });
});
