/**
 * SherpaFsStaging — read model files / directory trees from the V2
 * commons MEMFS (where the platform adapter writes downloaded models)
 * and stage them into the standalone Sherpa module's MEMFS so its
 * libc `fopen` / `stat` calls can resolve them.
 *
 * The standalone Sherpa Emscripten module exposes the FS plumbing as
 * `FS_createDataFile` / `FS_createPath` / `FS_unlink` (Emscripten 5.x
 * style — the legacy `FS.{writeFile,mkdir}` namespace is not bundled
 * with the nodejs WASM target). We bridge file content from the
 * RACommons module's `module.FS.readFile` API into the Sherpa module
 * via these helpers.
 *
 * When the file is not present in the RACommons MEMFS (e.g. the SDK
 * has not yet downloaded it, or the spec is bundling a fixture from
 * the test harness directly), callers can pre-populate the bytes and
 * pass them in via `stageBytes`.
 */

import { SDKLogger, tryRunanywhereModule, type EmscriptenRunanywhereModule } from '@runanywhere/web/internal';
import type { StandaloneSherpaModule } from './StandaloneSherpaModule';

const logger = new SDKLogger('SherpaFsStaging');

interface CommonsFsModule extends EmscriptenRunanywhereModule {
  FS?: {
    readFile(path: string): Uint8Array;
    readdir(path: string): string[];
    stat(path: string): { mode: number };
    isDir?(mode: number): boolean;
    analyzePath?(path: string): { exists: boolean; object?: { isFolder?: boolean } };
  };
}

/** Tracks staged paths so we can unlink them on unload. */
const _staged = new WeakMap<StandaloneSherpaModule, Set<string>>();

function getStagedSet(module: StandaloneSherpaModule): Set<string> {
  let set = _staged.get(module);
  if (!set) {
    set = new Set<string>();
    _staged.set(module, set);
  }
  return set;
}

/**
 * Stage a single file blob into the Sherpa MEMFS at `<parent>/<name>`.
 * Idempotent — if the same target path was staged before, it is unlinked
 * and replaced.
 */
export function stageBytes(
  module: StandaloneSherpaModule,
  parent: string,
  name: string,
  data: Uint8Array,
): string {
  ensureParentDirs(module, parent);
  const target = parent.endsWith('/') ? parent + name : parent + '/' + name;
  const set = getStagedSet(module);
  if (set.has(target)) {
    try {
      module.FS_unlink(target);
    } catch {
      /* file may have been removed already */
    }
  }
  module.FS_createDataFile(parent, name, data, true, true, true);
  set.add(target);
  return target;
}

/**
 * Resolve a model file path that the RACommons download orchestrator
 * produced (typically a `/opfs/RunAnywhere/Models/...` MEMFS path) and
 * stage it into the Sherpa module's MEMFS at the same path.
 *
 * If the path is a directory in RACommons MEMFS, the entire subtree is
 * mirrored. Returns the canonical Sherpa-side path that should be used
 * for subsequent C API calls.
 */
export function stageFromCommonsFs(
  module: StandaloneSherpaModule,
  sourcePath: string,
): string {
  const commons = tryRunanywhereModule() as CommonsFsModule | null;
  if (!commons || !commons.FS || typeof commons.FS.readFile !== 'function') {
    throw new Error(
      `SherpaFsStaging: cannot stage "${sourcePath}" — RACommons module FS bridge is not installed.`,
    );
  }

  const stat = safeStat(commons, sourcePath);
  if (!stat) {
    throw new Error(`SherpaFsStaging: source path "${sourcePath}" does not exist in RACommons MEMFS.`);
  }

  if (isDirectoryPath(commons, sourcePath, stat.mode)) {
    mirrorDirectory(module, commons, sourcePath, sourcePath);
  } else {
    const bytes = commons.FS.readFile(sourcePath);
    const slash = sourcePath.lastIndexOf('/');
    const parent = slash > 0 ? sourcePath.slice(0, slash) : '/';
    const name = slash >= 0 ? sourcePath.slice(slash + 1) : sourcePath;
    stageBytes(module, parent, name, bytes);
  }

  return sourcePath;
}

function isDirectoryPath(
  commons: CommonsFsModule,
  path: string,
  mode: number,
): boolean {
  if (!commons.FS) return false;
  // Prefer FS.isDir(mode) when exposed; some Emscripten builds omit the
  // helper from the runtime exports list. Fall back to FS.analyzePath, then
  // to readdir() (which throws ENOTDIR on regular files).
  if (typeof commons.FS.isDir === 'function') {
    return commons.FS.isDir(mode);
  }
  if (typeof commons.FS.analyzePath === 'function') {
    const analysis = commons.FS.analyzePath(path);
    if (analysis?.object?.isFolder !== undefined) {
      return analysis.object.isFolder;
    }
  }
  try {
    commons.FS.readdir(path);
    return true;
  } catch {
    return false;
  }
}

function safeStat(commons: CommonsFsModule, path: string): { mode: number } | null {
  if (!commons.FS) return null;
  try {
    return commons.FS.stat(path);
  } catch {
    return null;
  }
}

function mirrorDirectory(
  module: StandaloneSherpaModule,
  commons: CommonsFsModule,
  sourceRoot: string,
  currentDir: string,
): void {
  if (!commons.FS) return;
  ensureParentDirs(module, currentDir);
  const entries = commons.FS.readdir(currentDir);
  let mirroredFiles = 0;
  let mirroredDirs = 0;
  for (const entry of entries) {
    if (entry === '.' || entry === '..') continue;
    const childPath = currentDir.endsWith('/') ? currentDir + entry : currentDir + '/' + entry;
    const childStat = safeStat(commons, childPath);
    if (!childStat) continue;
    if (isDirectoryPath(commons, childPath, childStat.mode)) {
      mirroredDirs += 1;
      mirrorDirectory(module, commons, sourceRoot, childPath);
    } else {
      try {
        const bytes = commons.FS.readFile(childPath);
        stageBytes(module, currentDir, entry, bytes);
        mirroredFiles += 1;
      } catch (err) {
        logger.warning(
          `Failed to mirror "${childPath}" into Sherpa MEMFS: ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
    }
  }
  if (mirroredFiles + mirroredDirs > 0) {
    logger.debug(
      `Mirrored ${mirroredFiles} files + ${mirroredDirs} subdirs from ${currentDir}`,
    );
  }
}

/** Idempotently create a directory tree on the Sherpa side. */
export function ensureParentDirs(module: StandaloneSherpaModule, dirPath: string): void {
  if (!dirPath || dirPath === '/' || dirPath === '.' || dirPath === '') return;
  const parts = dirPath.split('/').filter((p) => p.length > 0);
  let current = '';
  for (const part of parts) {
    const parent = current.length === 0 ? '/' : current;
    try {
      module.FS_createPath(parent, part, true, true);
    } catch {
      /* createPath throws when the path already exists; that's fine. */
    }
    current = current.length === 0 ? `/${part}` : `${current}/${part}`;
  }
}

/** Forget previously staged files (does not actually unlink — Sherpa keeps them
 * in MEMFS for the lifetime of the module). */
export function clearStagedTracking(module: StandaloneSherpaModule): void {
  _staged.delete(module);
}
