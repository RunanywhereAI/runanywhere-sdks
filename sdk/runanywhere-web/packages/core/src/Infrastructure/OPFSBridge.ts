/**
 * OPFSBridge - persists Emscripten MEMFS files to the Origin Private
 * File System (OPFS) so model downloads survive tab reloads.
 *
 * Background
 * ----------
 * The C++ download orchestrator writes bytes via `std::ofstream` (see
 * `sdk/runanywhere-commons/src/infrastructure/http/rac_http_download.cpp`).
 * On native SDKs (iOS / Android / desktop) this lands on the real
 * filesystem because libc maps to it. Inside an Emscripten WASM module,
 * `std::ofstream` lands on MEMFS — an in-memory filesystem that is
 * destroyed on tab reload and invisible to `navigator.storage.estimate()`.
 *
 * The path prefix `/opfs/` (set on `g_base_dir` via
 * `rac_model_paths_set_base_dir` during `_initRACommons`) is therefore
 * misleading: bytes do NOT persist to the browser's Origin Private File
 * System until something explicitly copies them there.
 *
 * OPFSBridge is that something. After a successful download the SDK
 * facade calls `OPFSBridge.flushFromMemfs(module, '/opfs/<path>')` to
 * read the bytes out of MEMFS and persist them in OPFS at the
 * matching relative path. Before a model load, the SDK calls
 * `OPFSBridge.restoreToMemfs(module, '/opfs/<path>')` so the C++ engine
 * loader (which uses `fopen`/`mmap` against the MEMFS-visible path)
 * sees the bytes again.
 *
 * Architectural alignment
 * -----------------------
 * The C++ core treats `std::ofstream` as a platform abstraction. Each
 * SDK is responsible for backing that abstraction with a real
 * filesystem. iOS and Android get one from libc; Web is supplied here
 * via OPFS. The C++ download/extract logic stays untouched.
 *
 * Scope / limits
 * --------------
 * - Bridges the full file through a `Uint8Array` between MEMFS and
 *   OPFS, so the file must fit in WASM heap during the flush/restore
 *   step (currently bounded by `MAXIMUM_MEMORY=4 GB` — see
 *   `sdk/runanywhere-web/wasm/CMakeLists.txt`).
 * - Uses `FileSystemFileHandle.createWritable()` when available
 *   (main thread) and falls back to `createSyncAccessHandle()` for
 *   worker contexts.
 * - All paths are absolute under the synthetic `/opfs/` prefix; the
 *   leading `/opfs/` is stripped before being used as the OPFS-relative
 *   path so OPFS sees `RunAnywhere/Models/...` directly.
 */

import { SDKLogger } from '../Foundation/SDKLogger.js';

const logger = new SDKLogger('OPFSBridge');

/** Synthetic prefix shared with C++ (see `rac_model_paths_set_base_dir`). */
const OPFS_PREFIX = '/opfs';

/**
 * Persistent root selected by the host through the File System Access API.
 * When absent, the bridge resolves the origin-private root as before. Keeping
 * this override inside the bridge is important: every download, hydrate,
 * model load, and delete must resolve the same synthetic `/opfs/` path tree.
 */
let persistentRootOverride: FileSystemDirectoryHandle | null = null;
const persistentRootIds = new WeakMap<FileSystemDirectoryHandle, number>();
let nextPersistentRootId = 1;

function persistentRootKey(root: FileSystemDirectoryHandle | null): string {
  if (root === null) return 'origin-private';
  let id = persistentRootIds.get(root);
  if (id === undefined) {
    id = nextPersistentRootId;
    nextPersistentRootId += 1;
    persistentRootIds.set(root, id);
  }
  return `selected-${id}`;
}

function scopedPathKey(rootKey: string, path: string): string {
  return `${rootKey}\u0000${path}`;
}

interface SuppressedPersistentPath {
  path: string;
  rootKey: string;
}

/** Minimal Emscripten FS surface OPFSBridge needs at runtime. */
interface EmscriptenFS {
  readFile(path: string, opts?: { encoding?: string }): Uint8Array;
  writeFile(path: string, data: Uint8Array): void;
  mkdir(path: string, mode?: number): void;
  unlink(path: string): void;
  stat(path: string): { size: number; mode: number };
  analyzePath?(path: string): { exists: boolean };
  readdir?(path: string): string[];
  isDir?(mode: number): boolean;
}

/** Local structural type for the browser's async directory iterator surface. */
interface IterableFileSystemDirectoryHandle {
  entries?(): AsyncIterableIterator<[string, FileSystemHandle]>;
  values?(): AsyncIterableIterator<FileSystemHandle>;
}

/** Emscripten POSIX-style file-mode bit for "is directory" (S_IFDIR). */
const S_IFDIR = 0o040000;

function isMemfsDirectory(fs: EmscriptenFS, path: string): boolean {
  try {
    if (fs.analyzePath && !fs.analyzePath(path)?.exists) return false;
    const mode = fs.stat(path).mode;
    if (typeof fs.isDir === 'function') return fs.isDir(mode);
    return (mode & S_IFDIR) === S_IFDIR;
  } catch {
    return false;
  }
}

function listMemfsDirectory(fs: EmscriptenFS, path: string): string[] {
  if (typeof fs.readdir !== 'function') return [];
  try {
    return fs.readdir(path).filter((name) => name !== '.' && name !== '..');
  } catch {
    return [];
  }
}

/**
 * Loose module shape — `FS` is added by Emscripten when the WASM target
 * is built with `-sFORCE_FILESYSTEM=1` (see
 * `sdk/runanywhere-web/wasm/CMakeLists.txt`) and exported via the
 * `-sEXPORTED_RUNTIME_METHODS=[..., "FS", ...]` list. We accept any
 * object and narrow at the call site so the bridge stays usable from any
 * Emscripten module type (commons, llamacpp, onnx-sherpa) without
 * depending on a specific module typing.
 */
export type ModuleLike = object;

function getFS(module: ModuleLike): EmscriptenFS | null {
  const candidate = (module as { FS?: unknown }).FS;
  if (candidate && typeof candidate === 'object') {
    const fs = candidate as Partial<EmscriptenFS>;
    if (typeof fs.readFile === 'function' && typeof fs.writeFile === 'function'
      && typeof fs.mkdir === 'function' && typeof fs.stat === 'function') {
      return fs as EmscriptenFS;
    }
  }
  return null;
}

/**
 * Copy `src` into a fresh `ArrayBuffer` and return the buffer directly.
 * The OPFS write APIs accept `ArrayBuffer` and reject views backed by
 * `SharedArrayBuffer`; bytes returned from Emscripten's `FS.readFile`
 * can be backed by `SharedArrayBuffer` when the build is
 * `-pthread`-enabled, so the copy is unavoidable.
 */
function toOwnedArrayBuffer(src: Uint8Array): ArrayBuffer {
  const owned = new ArrayBuffer(src.byteLength);
  new Uint8Array(owned).set(src);
  return owned;
}

/** True when the browser supports the Origin Private File System. */
function isOPFSSupported(
  root: FileSystemDirectoryHandle | null = persistentRootOverride,
): boolean {
  return root !== null || (typeof navigator !== 'undefined'
    && 'storage' in navigator
    && typeof navigator.storage?.getDirectory === 'function');
}

/**
 * Strip the synthetic `/opfs/` prefix and return the OPFS-relative path
 * components. `/opfs/RunAnywhere/Models/foo/bar.gguf` →
 * ['RunAnywhere', 'Models', 'foo', 'bar.gguf'].
 *
 * Returns null when `path` does not live under the `/opfs/` prefix —
 * caller should skip the OPFS step (the file was not written through
 * the synthetic-prefix path so OPFS would not be the right home for it).
 */
function pathToOPFSSegments(path: string): string[] | null {
  if (!path.startsWith(`${OPFS_PREFIX}/`)) return null;
  const relative = path.slice(OPFS_PREFIX.length + 1);
  if (relative.length === 0) return null;
  return relative.split('/').filter((segment) => segment.length > 0);
}

/**
 * Walk the OPFS tree from the root to the directory that should hold
 * `fileName`. Creates intermediate directories when `create` is true.
 */
async function resolveOPFSDirectory(
  segments: string[],
  create: boolean,
  root: FileSystemDirectoryHandle | null = persistentRootOverride,
): Promise<FileSystemDirectoryHandle | null> {
  if (!isOPFSSupported(root)) {
    return null;
  }
  let dir = root ?? await navigator.storage.getDirectory();
  for (const segment of segments) {
    dir = await dir.getDirectoryHandle(segment, { create });
  }
  return dir;
}

/** Recursively ensure `path` exists in MEMFS as a directory. */
function ensureMemfsDirectory(fs: EmscriptenFS, path: string): void {
  if (path === '' || path === '/' || path === '.') return;
  if (fs.analyzePath?.(path)?.exists) return;
  const lastSlash = path.lastIndexOf('/');
  if (lastSlash > 0) {
    ensureMemfsDirectory(fs, path.slice(0, lastSlash));
  }
  try {
    fs.mkdir(path);
  } catch (err) {
    // mkdir throws if the path already exists — race-safe ignore.
    const message = err instanceof Error ? err.message : String(err);
    if (!message.includes('EEXIST') && !message.includes('exists')) {
      throw err;
    }
  }
}

/** Write `bytes` to the OPFS file handle. Prefers `createWritable` (main
 *  thread); falls back to `createSyncAccessHandle` (worker contexts /
 *  Safari where the writable stream is gated behind a permission). */
async function writeBytesToOPFSFile(
  handle: FileSystemFileHandle,
  bytes: Uint8Array,
): Promise<void> {
  // createWritable is the easy path. It is async, but it does not
  // require a sync-access handle (i.e. no main-thread restrictions on
  // Chrome / Firefox).
  if (typeof (handle as { createWritable?: unknown }).createWritable === 'function') {
    try {
      const writable = await handle.createWritable({ keepExistingData: false });
      await writable.write(toOwnedArrayBuffer(bytes));
      await writable.close();
      return;
    } catch (err) {
      logger.debug(
        `OPFS createWritable failed, falling back to sync-access handle: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }
  }

  // Sync-access handle path. Requires the call site to run in a Worker
  // on Safari; on Chrome it works on the main thread too. We use it as
  // a fallback so the OPFS persistence still works when `createWritable`
  // is unavailable or fails. The cast goes through `unknown` because the
  // standard `FileSystemFileHandle` lib type does not yet declare
  // `createSyncAccessHandle` in every tsconfig target.
  const syncCapable = handle as unknown as {
    createSyncAccessHandle?: () => Promise<{
      write(data: ArrayBufferView | ArrayBuffer, opts?: { at?: number }): number;
      truncate(size: number): void;
      flush(): void;
      close(): void;
    }>;
  };
  if (typeof syncCapable.createSyncAccessHandle !== 'function') {
    throw new Error('OPFS: neither createWritable nor createSyncAccessHandle is available on this FileSystemFileHandle');
  }
  const sync = await syncCapable.createSyncAccessHandle();
  try {
    sync.truncate(0);
    sync.write(toOwnedArrayBuffer(bytes), { at: 0 });
    sync.flush();
  } finally {
    sync.close();
  }
}

/** Read all bytes from the OPFS file handle. */
async function readBytesFromOPFSFile(handle: FileSystemFileHandle): Promise<Uint8Array> {
  // FileSystemFileHandle.getFile() returns a regular Blob, so this works
  // both on the main thread and inside Workers.
  const file = await handle.getFile();
  const buffer = await file.arrayBuffer();
  return new Uint8Array(buffer);
}

export class OPFSBridge {
  /**
   * Paths whose synchronous MEMFS deletion has committed but whose async OPFS
   * removal is still pending. Hydration/restore treats these as absent from
   * the moment the native delete callback returns, preventing a stale OPFS
   * copy from resurrecting the registry entry in the same browser lifetime.
   */
  private static readonly suppressedPaths = new Map<string, SuppressedPersistentPath>();
  private static readonly pendingRemovals = new Map<string, Promise<void>>();

  /** Whether the browser supports the OPFS APIs OPFSBridge needs. */
  static get isSupported(): boolean {
    return isOPFSSupported();
  }

  /**
   * Route the synthetic `/opfs/` tree through a user-selected persistent
   * directory. Passing `null` restores the origin-private browser root.
   * The caller owns permission checks and only installs granted handles.
   */
  static setPersistentRoot(handle: FileSystemDirectoryHandle | null): void {
    persistentRootOverride = handle;
  }

  /**
   * Commit a logical deletion immediately and remove its OPFS counterpart on
   * the browser event loop. The storage analyzer callback is synchronous, so
   * it cannot await FileSystemDirectoryHandle.removeEntry().
   */
  static scheduleRemovePath(path: string): Promise<void> {
    return OPFSBridge.queueRemovePath(path, true);
  }

  /**
   * Remove a persistent path transactionally. Unlike the legacy scheduled
   * callback path, rejection clears the temporary tombstone because callers
   * have not yet committed the matching MEMFS or registry deletion.
   */
  static async removePath(path: string): Promise<void> {
    await OPFSBridge.queueRemovePath(path, false);
  }

  private static queueRemovePath(
    path: string,
    retainSuppressionOnFailure: boolean,
  ): Promise<void> {
    const segments = pathToOPFSSegments(path);
    if (!segments) return Promise.resolve();
    // Capture both the root handle and its logical identity. Resolving the
    // mutable global root later could delete the same path from a folder the
    // user selected after this callback returned.
    const root = persistentRootOverride;
    const rootKey = persistentRootKey(root);
    const scopedKey = scopedPathKey(rootKey, path);
    OPFSBridge.suppressedPaths.set(scopedKey, { path, rootKey });
    const previous = OPFSBridge.pendingRemovals.get(scopedKey);
    const removal = (previous ? previous.catch(() => undefined) : Promise.resolve())
      .then(() => OPFSBridge.removePathFromOPFS(segments, path, root));
    OPFSBridge.pendingRemovals.set(scopedKey, removal);
    void removal.then(
      () => {
        if (OPFSBridge.pendingRemovals.get(scopedKey) === removal) {
          OPFSBridge.pendingRemovals.delete(scopedKey);
          // Physical absence now enforces the deletion, so the temporary
          // logical tombstone is no longer needed and cannot leak forever.
          OPFSBridge.suppressedPaths.delete(scopedKey);
        }
      },
      (error: unknown) => {
        logger.warning(
          `${retainSuppressionOnFailure ? 'Scheduled' : 'Transactional'} OPFS deletion failed for '${path}': ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
        if (OPFSBridge.pendingRemovals.get(scopedKey) === removal) {
          OPFSBridge.pendingRemovals.delete(scopedKey);
          if (!retainSuppressionOnFailure) {
            OPFSBridge.suppressedPaths.delete(scopedKey);
          }
          // Scheduled callback deletions retain the tombstone on failure so a
          // stale file cannot be hydrated after the synchronous side already
          // committed. Transactional callers clear it because nothing else
          // has been committed yet.
        }
      },
    );
    return removal;
  }

  private static async removePathFromOPFS(
    segments: string[],
    path: string,
    root: FileSystemDirectoryHandle | null,
  ): Promise<void> {
    if (!isOPFSSupported(root)) return;
    try {
      const dir = await resolveOPFSDirectory(segments.slice(0, -1), false, root);
      if (!dir) return;
      await dir.removeEntry(segments[segments.length - 1], { recursive: true });
      logger.info(`OPFS removed '${path}'`);
    } catch (error) {
      if (error instanceof DOMException && error.name === 'NotFoundError') return;
      throw error;
    }
  }

  private static isSuppressed(path: string): boolean {
    const rootKey = persistentRootKey(persistentRootOverride);
    for (const suppressed of OPFSBridge.suppressedPaths.values()) {
      if (suppressed.rootKey !== rootKey) continue;
      if (path === suppressed.path || path.startsWith(`${suppressed.path}/`)) return true;
    }
    return false;
  }

  /**
   * Serialize a new persistent write behind any scheduled deletion that owns
   * the same path. This prevents a late removeEntry() from deleting bytes that
   * a user immediately re-downloaded after deletion.
   */
  private static async preparePathForWrite(path: string): Promise<void> {
    const rootKey = persistentRootKey(persistentRootOverride);
    const pending: Promise<void>[] = [];
    for (const [key, suppressed] of OPFSBridge.suppressedPaths) {
      if (
        suppressed.rootKey === rootKey
        && (path === suppressed.path || path.startsWith(`${suppressed.path}/`))
      ) {
        const removal = OPFSBridge.pendingRemovals.get(key);
        if (removal) pending.push(removal);
      }
    }
    await Promise.all(pending);
    for (const [key, suppressed] of OPFSBridge.suppressedPaths) {
      if (
        suppressed.rootKey === rootKey
        && (path === suppressed.path || path.startsWith(`${suppressed.path}/`))
      ) {
        OPFSBridge.suppressedPaths.delete(key);
      }
    }
  }

  /** Byte length of `path` in a module's MEMFS, or 0 when missing/unreadable. */
  static memfsFileSize(module: ModuleLike, path: string): number {
    const fs = getFS(module);
    if (!fs) return 0;
    try {
      if (fs.analyzePath && !fs.analyzePath(path)?.exists) return 0;
      return fs.stat(path).size;
    } catch {
      return 0;
    }
  }

  /** Largest MEMFS size for `path` across `modules`. */
  static maxMemfsFileSizeAcrossModules(modules: ModuleLike[], path: string): number {
    let max = 0;
    for (const module of modules) {
      const size = OPFSBridge.memfsFileSize(module, path);
      if (size > max) max = size;
    }
    return max;
  }

  /** Modules that expose the Emscripten filesystem required for hydration. */
  private static filesystemModules(modules: ModuleLike[]): ModuleLike[] {
    return modules.filter((module) => getFS(module) !== null);
  }

  /** FS-bearing modules whose private MEMFS does not contain the artifact. */
  private static modulesMissingPath(modules: ModuleLike[], path: string): ModuleLike[] {
    return modules.filter((module) => OPFSBridge.memfsFileSize(module, path) === 0);
  }

  /**
   * After a download completes, flush MEMFS → OPFS and mirror bytes into every
   * backend module's MEMFS. Throws when persistence cannot be verified so
   * callers cannot race `loadModel` against an in-flight OPFS write.
   */
  static async ensureDownloadPersisted(
    localPath: string,
    downloaderModule: ModuleLike,
    allModules: ModuleLike[],
  ): Promise<void> {
    const opfsExpected = pathToOPFSSegments(localPath) !== null && isOPFSSupported();
    const downloaderFs = getFS(downloaderModule);
    const isDirectoryArtifact = downloaderFs ? isMemfsDirectory(downloaderFs, localPath) : false;

    if (opfsExpected) {
      const flushed = await OPFSBridge.flushFromMemfs(downloaderModule, localPath);

      if (isDirectoryArtifact) {
        const segments = pathToOPFSSegments(localPath) ?? [];
        const hasArtifacts = await OPFSBridge.directoryHasArtifacts(segments);
        if (!hasArtifacts) {
          throw new Error(
            `Download persist failed: directory '${localPath}' has no artifacts in OPFS after flush`,
          );
        }
      } else {
        const downloaderMemfs = OPFSBridge.memfsFileSize(downloaderModule, localPath);
        if (flushed === 0 && downloaderMemfs === 0) {
          const exists = await OPFSBridge.exists(localPath);
          if (!exists) {
            throw new Error(
              `Download persist failed: '${localPath}' is absent from MEMFS and OPFS`,
            );
          }
        }
        if (!(await OPFSBridge.exists(localPath))) {
          throw new Error(
            `Download persist failed: '${localPath}' missing from OPFS after flush`,
          );
        }
      }
    }

    const filesystemModules = OPFSBridge.filesystemModules(allModules);
    if (filesystemModules.length === 0) return;

    // Directory artifacts: mirror the entire tree into every module's MEMFS so
    // a subsequent loadModel that runs in a non-downloader module (e.g. Sherpa
    // STT loading a directory that commons extracted) can find the files.
    if (isDirectoryArtifact) {
      // Replay the complete OPFS tree to every target. The restore validates
      // each persisted file, so a module containing only one companion file
      // cannot masquerade as a fully hydrated model bundle.
      await OPFSBridge.restoreDirectoryToMemfsAll(filesystemModules, localPath);
      return;
    }

    let missingModules = OPFSBridge.modulesMissingPath(filesystemModules, localPath);
    if (missingModules.length === 0) return;
    await OPFSBridge.restoreToMemfsAll(missingModules, localPath);
    missingModules = OPFSBridge.modulesMissingPath(missingModules, localPath);
    if (missingModules.length === 0) return;

    const downloaderOnly = OPFSBridge.memfsFileSize(downloaderModule, localPath);
    if (downloaderOnly > 0 && opfsExpected) {
      await OPFSBridge.flushFromMemfs(downloaderModule, localPath);
      await OPFSBridge.restoreToMemfsAll(missingModules, localPath);
    }

    const stillMissing = OPFSBridge.modulesMissingPath(missingModules, localPath);
    if (stillMissing.length > 0) {
      throw new Error(
        `Download persist failed: '${localPath}' is missing from `
        + `${stillMissing.length} MEMFS module(s) after OPFS restore`,
      );
    }
  }

  /**
   * Before C++ `fopen`, ensure `path` is mirrored from OPFS into every module's
   * MEMFS with non-zero size. No-op when the path is not under `/opfs/`.
   */
  static async ensureModelPathReadyForLoad(
    modules: ModuleLike[],
    path: string,
  ): Promise<void> {
    const filesystemModules = OPFSBridge.filesystemModules(modules);
    if (filesystemModules.length === 0) return;
    const segments = pathToOPFSSegments(path);
    if (!segments) return;
    if (OPFSBridge.isSuppressed(path)) {
      throw new Error(`Model load failed: '${path}' was deleted from browser storage`);
    }

    let missingModules = OPFSBridge.modulesMissingPath(filesystemModules, path);
    const anyMemfsDirectory = filesystemModules.some((module) => {
      const fs = getFS(module);
      return fs !== null && isMemfsDirectory(fs, path);
    });
    // Preserve the zero-I/O fast path for single-file models. Directories must
    // still be compared against the complete OPFS tree because one surviving
    // companion file does not prove the bundle is fully hydrated.
    if (missingModules.length === 0 && !anyMemfsDirectory) return;

    // Detect whether the OPFS counterpart is a file or a directory (tar.gz
    // extract). Sherpa STT/TTS and VLM artifacts are directories; the
    // file-only restore path leaves MEMFS empty so the C++ backend fails
    // with "Model path does not exist".
    const opfsSupported = isOPFSSupported();
    if (opfsSupported) {
      if (await OPFSBridge.isOPFSDirectory(segments)) {
        await OPFSBridge.restoreDirectoryToMemfsAll(filesystemModules, path);
        return;
      }
    }

    // Each Emscripten artifact owns a private MEMFS. A surviving sibling may
    // retain model bytes after an acceleration switch while the replacement
    // llama.cpp module is empty, so only return when every FS-bearing module
    // has the artifact.
    if (missingModules.length === 0) return;

    if (opfsSupported && !(await OPFSBridge.exists(path))) {
      throw new Error(`Model load failed: '${path}' not found in OPFS`);
    }

    await OPFSBridge.restoreToMemfsAll(missingModules, path);
    missingModules = OPFSBridge.modulesMissingPath(missingModules, path);
    if (missingModules.length > 0) {
      throw new Error(
        `Model load failed: '${path}' is missing from `
        + `${missingModules.length} MEMFS module(s) after OPFS restore`,
      );
    }
  }

  /** True when `segments` resolves to a directory handle in OPFS. */
  static async isOPFSDirectory(segments: string[]): Promise<boolean> {
    if (!isOPFSSupported()) return false;
    if (OPFSBridge.isSuppressed(`${OPFS_PREFIX}/${segments.join('/')}`)) return false;
    try {
      const dir = await resolveOPFSDirectory(segments, false);
      return dir != null;
    } catch {
      return false;
    }
  }

  /**
   * Recursively restore every file under an OPFS directory tree into the
   * matching MEMFS path of each module. Directory entries are mkdir'd; file
   * entries are read from OPFS and written via FS.writeFile.
   */
  static async restoreDirectoryToMemfsAll(
    modules: ModuleLike[],
    dirPath: string,
  ): Promise<void> {
    if (!isOPFSSupported()) return;
    if (OPFSBridge.isSuppressed(dirPath)) return;
    const segments = pathToOPFSSegments(dirPath);
    if (!segments) return;
    const dir = await resolveOPFSDirectory(segments, false);
    if (!dir) return;
    for (const module of modules) {
      const fs = getFS(module);
      if (!fs) continue;
      ensureMemfsDirectory(fs, dirPath);
      const restoredArtifacts = await OPFSBridge.restoreOPFSDirToFs(dir, dirPath, fs);
      if (restoredArtifacts === 0) {
        throw new Error(
          `OPFS directory '${dirPath}' contains no non-empty model artifacts`,
        );
      }
    }
  }

  private static async restoreOPFSDirToFs(
    dir: FileSystemDirectoryHandle,
    dirPath: string,
    fs: EmscriptenFS,
  ): Promise<number> {
    const iterable = dir as unknown as IterableFileSystemDirectoryHandle;
    const entries = iterable.entries?.() ?? null;
    if (!entries) {
      throw new Error(`OPFS directory iteration is unavailable for '${dirPath}'`);
    }
    let artifactCount = 0;
    for await (const [name, handle] of entries) {
      const childPath = `${dirPath}/${name}`;
      if (handle.kind === 'file') {
        const fileHandle = handle as FileSystemFileHandle;
        const file = await fileHandle.getFile();
        if (file.size === 0) {
          throw new Error(`OPFS model artifact '${childPath}' is empty`);
        }
        let currentSize = 0;
        try {
          currentSize = fs.stat(childPath).size;
        } catch {
          // Missing from this module's MEMFS — restore below.
        }
        if (currentSize !== file.size) {
          const bytes = new Uint8Array(await file.arrayBuffer());
          const parent = childPath.slice(0, childPath.lastIndexOf('/')) || '/';
          ensureMemfsDirectory(fs, parent);
          fs.writeFile(childPath, bytes);
        }
        const restoredSize = fs.stat(childPath).size;
        if (restoredSize !== file.size) {
          throw new Error(
            `MEMFS restore size mismatch for '${childPath}': `
            + `expected ${file.size}, received ${restoredSize}`,
          );
        }
        artifactCount += 1;
      } else if (handle.kind === 'directory') {
        ensureMemfsDirectory(fs, childPath);
        artifactCount += await OPFSBridge.restoreOPFSDirToFs(
          handle as FileSystemDirectoryHandle,
          childPath,
          fs,
        );
      }
    }
    return artifactCount;
  }

  /**
   * Flush a file from Emscripten MEMFS into the Origin Private File
   * System so the bytes persist across tab reloads.
   *
   * Returns the number of bytes persisted on success, or 0 when the
   * path is not under `/opfs/` (no-op) or the browser does not support
   * OPFS. Throws on actual I/O failures so the caller can surface them.
   */
  static async flushFromMemfs(module: ModuleLike, path: string): Promise<number> {
    const fs = getFS(module);
    if (!fs) {
      logger.debug(`flushFromMemfs: module has no FS surface (path=${path}); skipping`);
      return 0;
    }
    const segments = pathToOPFSSegments(path);
    if (!segments) {
      logger.debug(`flushFromMemfs: path '${path}' is not under '${OPFS_PREFIX}/'; skipping`);
      return 0;
    }
    await OPFSBridge.preparePathForWrite(path);
    if (!isOPFSSupported()) {
      logger.warning(`flushFromMemfs: OPFS not supported in this browser; '${path}' will not persist`);
      return 0;
    }

    // tar.gz / multi-file model artifacts expand into a directory rather than a
    // single file. Walk the directory in MEMFS and flush each contained file
    // individually so OPFS mirrors the full extract.
    if (isMemfsDirectory(fs, path)) {
      return OPFSBridge.flushDirectoryFromMemfs(fs, path);
    }

    let bytes: Uint8Array;
    try {
      bytes = fs.readFile(path);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.warning(`flushFromMemfs: FS.readFile('${path}') failed: ${message}`);
      return 0;
    }

    const fileName = segments[segments.length - 1];
    const dirSegments = segments.slice(0, -1);
    const dir = await resolveOPFSDirectory(dirSegments, true);
    if (!dir) {
      return 0;
    }
    const fileHandle = await dir.getFileHandle(fileName, { create: true });
    await writeBytesToOPFSFile(fileHandle, bytes);
    logger.info(`OPFS persisted ${bytes.length} bytes for '${path}'`);
    return bytes.length;
  }

  /** Recursively flush every file under a MEMFS directory to its OPFS twin. */
  private static async flushDirectoryFromMemfs(
    fs: EmscriptenFS,
    dirPath: string,
  ): Promise<number> {
    const names = listMemfsDirectory(fs, dirPath);
    if (names.length === 0) {
      logger.debug(`flushFromMemfs: directory '${dirPath}' is empty in MEMFS`);
      return 0;
    }
    let total = 0;
    for (const name of names) {
      const childPath = `${dirPath}/${name}`;
      const written = await OPFSBridge.flushFromMemfs({ FS: fs } as ModuleLike, childPath);
      total += written;
    }
    logger.info(`OPFS persisted directory '${dirPath}' (${total} bytes across ${names.length} entries)`);
    return total;
  }

  /**
   * Restore a file from OPFS into Emscripten MEMFS at `path` so the
   * C++ engine loader (which opens `fopen`/`mmap` against MEMFS-visible
   * paths) can find it after a tab reload.
   *
   * No-op when the file already exists in MEMFS, when the browser does
   * not support OPFS, or when no matching file is found in OPFS.
   * Returns the number of bytes restored, or 0 in any of those cases.
   */
  static async restoreToMemfs(module: ModuleLike, path: string): Promise<number> {
    const fs = getFS(module);
    if (!fs) return 0;
    if (OPFSBridge.isSuppressed(path)) return 0;

    // Already present in MEMFS with real bytes — nothing to do.
    if (fs.analyzePath?.(path)?.exists) {
      try {
        const size = fs.stat(path).size;
        if (size > 0) {
          logger.debug(`restoreToMemfs: '${path}' already in MEMFS (${size} bytes)`);
          return 0;
        }
      } catch {
        // stat failed — fall through and rebuild from OPFS.
      }
    }

    const segments = pathToOPFSSegments(path);
    if (!segments || !isOPFSSupported()) return 0;

    const fileName = segments[segments.length - 1];
    const dirSegments = segments.slice(0, -1);

    let fileHandle: FileSystemFileHandle;
    try {
      const dir = await resolveOPFSDirectory(dirSegments, false);
      if (!dir) return 0;
      fileHandle = await dir.getFileHandle(fileName, { create: false });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.debug(`restoreToMemfs: OPFS lookup failed for '${path}': ${message}`);
      return 0;
    }

    const bytes = await readBytesFromOPFSFile(fileHandle);
    const dirPath = path.slice(0, path.lastIndexOf('/'));
    ensureMemfsDirectory(fs, dirPath);
    fs.writeFile(path, bytes);
    logger.info(`OPFS restored ${bytes.length} bytes to '${path}'`);
    return bytes.length;
  }

  /**
   * Fan out a single OPFS restore across a list of modules.
   *
   * Each Emscripten WASM artifact (commons, llamacpp, onnx-sherpa)
   * owns a private MEMFS — writing into one is invisible to another.
   * The model-load path in C++ runs inside the backend WASM that owns
   * the engine vtable (e.g. llamacpp), so restoring into the commons
   * module alone leaves the backend's `fopen` returning ENOENT. To
   * match the per-WASM isolation, mirror the file into every backend
   * module the SDK has installed.
   *
   * Reads the file from OPFS exactly once and reuses the bytes across
   * every MEMFS write so we do not pay N x OPFS-read cost.
   *
   * Returns the number of bytes restored to each module (max across
   * all modules) — 0 means OPFS lookup failed or no module had an FS
   * surface.
   */
  static async restoreToMemfsAll(modules: ModuleLike[], path: string): Promise<number> {
    if (modules.length === 0) return 0;
    if (OPFSBridge.isSuppressed(path)) return 0;
    const segments = pathToOPFSSegments(path);
    if (!segments || !isOPFSSupported()) return 0;

    const fileName = segments[segments.length - 1];
    const dirSegments = segments.slice(0, -1);

    let fileHandle: FileSystemFileHandle;
    try {
      const dir = await resolveOPFSDirectory(dirSegments, false);
      if (!dir) return 0;
      fileHandle = await dir.getFileHandle(fileName, { create: false });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger.debug(`restoreToMemfsAll: OPFS lookup failed for '${path}': ${message}`);
      return 0;
    }

    const bytes = await readBytesFromOPFSFile(fileHandle);
    const dirPath = path.slice(0, path.lastIndexOf('/'));
    let maxWritten = 0;
    for (const module of modules) {
      const fs = getFS(module);
      if (!fs) continue;
      if (fs.analyzePath?.(path)?.exists) {
        try {
          const size = fs.stat(path).size;
          if (size > 0) {
            logger.debug(
              `restoreToMemfsAll: '${path}' already in MEMFS (${size} bytes); skipping module`,
            );
            if (size > maxWritten) maxWritten = size;
            continue;
          }
        } catch {
          // stat failed — fall through and rewrite from OPFS bytes.
        }
      }
      try {
        ensureMemfsDirectory(fs, dirPath);
        fs.writeFile(path, bytes);
        if (bytes.length > maxWritten) maxWritten = bytes.length;
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        logger.warning(`restoreToMemfsAll: MEMFS write failed for '${path}' on a module: ${message}`);
      }
    }
    if (maxWritten > 0) {
      logger.info(`OPFS restored ${maxWritten} bytes to '${path}' across ${modules.length} module(s)`);
    }
    return maxWritten;
  }

  /**
   * Check whether a path is currently present in OPFS. Useful when the
   * caller wants to decide between download and load-from-cache without
   * paying the cost of reading bytes back.
   */
  static async exists(path: string): Promise<boolean> {
    if (OPFSBridge.isSuppressed(path)) return false;
    const segments = pathToOPFSSegments(path);
    if (!segments || !isOPFSSupported()) return false;
    const fileName = segments[segments.length - 1];
    const dirSegments = segments.slice(0, -1);
    try {
      const dir = await resolveOPFSDirectory(dirSegments, false);
      if (!dir) return false;
      await dir.getFileHandle(fileName, { create: false });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * True when an OPFS model directory contains at least one file anywhere in
   * its tree (post tar.gz extract). Some Sherpa archives wrap their contents
   * in a nested directory of the same name, so a shallow file-only check is
   * not sufficient; recurse into subdirectories.
   */
  static async directoryHasArtifacts(dirSegments: string[]): Promise<boolean> {
    if (!isOPFSSupported()) return false;
    if (OPFSBridge.isSuppressed(`${OPFS_PREFIX}/${dirSegments.join('/')}`)) return false;
    try {
      const dir = await resolveOPFSDirectory(dirSegments, false);
      if (!dir) return false;
      return await OPFSBridge.opfsDirectoryHasAnyFile(dir);
    } catch {
      return false;
    }
  }

  private static async opfsDirectoryHasAnyFile(
    dir: FileSystemDirectoryHandle,
  ): Promise<boolean> {
    const iterable = dir as unknown as IterableFileSystemDirectoryHandle;
    const entries = iterable.values?.() ?? null;
    if (!entries) return false;
    for await (const handle of entries) {
      if (!handle) continue;
      if (handle.kind === 'file') return true;
      if (handle.kind === 'directory') {
        const child = handle as FileSystemDirectoryHandle;
        if (await OPFSBridge.opfsDirectoryHasAnyFile(child)) return true;
      }
    }
    return false;
  }

  /**
   * Write `bytes` directly to an OPFS file at the given path segments.
   * Creates intermediate directories as needed.
   * Used by the SDK's multi-file download path to persist each file
   * individually without going through Emscripten MEMFS.
   */
  static async writeFileToOPFS(segments: string[], bytes: Uint8Array): Promise<void> {
    if (!isOPFSSupported()) return;
    await OPFSBridge.preparePathForWrite(`${OPFS_PREFIX}/${segments.join('/')}`);
    const dir = await resolveOPFSDirectory(segments.slice(0, -1), true);
    if (!dir) return;
    const fileName = segments[segments.length - 1];
    const handle = await dir.getFileHandle(fileName, { create: true });
    await writeBytesToOPFSFile(handle, bytes);
  }

  /**
   * Remove a download partial from every module's MEMFS and from OPFS.
   *
   * The native SDKs delete an oversize partial with a plain `unlink` on the
   * real filesystem. On Web the bytes live in each Emscripten module's
   * private MEMFS (written by the C++ `std::ofstream`) and, once persisted,
   * in OPFS under the synthetic `/opfs/` prefix. The download-planner
   * self-heal in `RunAnywhere.downloadModel` calls this so a re-plan no
   * longer sees the oversize partial. Best-effort: a missing file in either
   * filesystem is not an error.
   */
  static async removeFile(modules: ModuleLike[], path: string): Promise<void> {
    for (const module of modules) {
      const fs = getFS(module);
      if (!fs) continue;
      try {
        if (fs.analyzePath && !fs.analyzePath(path)?.exists) continue;
        fs.unlink(path);
      } catch (err) {
        logger.debug(
          `removeFile: MEMFS unlink failed for '${path}': ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
    }

    const segments = pathToOPFSSegments(path);
    if (!segments || !isOPFSSupported()) return;
    try {
      const dir = await resolveOPFSDirectory(segments.slice(0, -1), false);
      if (!dir) return;
      await dir.removeEntry(segments[segments.length - 1]);
    } catch (err) {
      logger.debug(
        `removeFile: OPFS removeEntry failed for '${path}': ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }
  }
}
