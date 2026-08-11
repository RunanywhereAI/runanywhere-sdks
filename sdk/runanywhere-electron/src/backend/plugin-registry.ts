// plugin-registry.ts — main-process ordered registration queue for backend plugins.
//
// App main calls LlamaCPP.register() / ONNX.register() / Sherpa.register() from
// the backend packages. Those append absolute plugin paths here. RunAnywhereMain
// then copies existing paths into RUNANYWHERE_PLUGIN_PATHS on utilityProcess.fork
// — never via a renderer RPC (no v3.registerBackendPlugin).
//
// Dual path (Track A landing shared commons + thin addon):
//   • Fat addon (today): backends are already linked into runanywhere_native.node.
//     register() records the canonical path; missing artifacts are omitted from
//     the fork env so host initialize() stays green.
//   • Thin addon: host reads RUNANYWHERE_PLUGIN_PATHS and calls
//     rac_registry_load_plugin(path) for each existing entry against shared
//     librac_commons. Re-fork replays the same queue from main.

import * as fs from 'node:fs';
import * as path from 'node:path';

/** Stable backend identifiers — match engine OUTPUT_NAME stems under engines/. */
export const BackendPluginId = {
  LlamaCPP: 'llamacpp',
  ONNX: 'onnx',
  Sherpa: 'sherpa',
} as const;

export type BackendPluginId = (typeof BackendPluginId)[keyof typeof BackendPluginId];

const BACKEND_PLUGIN_IDS: ReadonlySet<string> = new Set(Object.values(BackendPluginId));

export function isBackendPluginId(value: string): value is BackendPluginId {
  return BACKEND_PLUGIN_IDS.has(value);
}

/** One recorded plugin ready to hand to the utility host at fork time. */
export interface BackendPluginRegistration {
  readonly id: BackendPluginId;
  /** Absolute path to librunanywhere_<id>.{dylib,so,dll}. */
  readonly pluginPath: string;
}

/**
 * Inputs for resolving the staged plugin artifact inside a backend package.
 * `packageRoot` is the package directory that owns `prebuilds/<plat>-<arch>/`.
 */
export interface PluginArtifactLocator {
  readonly id: BackendPluginId;
  readonly packageRoot: string;
  /** Override platform (defaults to `process.platform`). */
  readonly platform?: NodeJS.Platform;
  /** Override arch (defaults to `process.arch`). */
  readonly arch?: string;
}

const ENV_PLUGIN_PATHS = 'RUNANYWHERE_PLUGIN_PATHS' as const;

/** Canonical id order used when no insertion history is needed. */
const CANONICAL_ORDER: readonly BackendPluginId[] = [
  BackendPluginId.LlamaCPP,
  BackendPluginId.ONNX,
  BackendPluginId.Sherpa,
];

/** Insertion-ordered queue (id → registration). Replace keeps position. */
const _queue = new Map<BackendPluginId, BackendPluginRegistration>();

/** Filename commons' plugin loader expects for a given backend id. */
export function pluginLibraryFileName(
  id: BackendPluginId,
  platform: NodeJS.Platform = process.platform
): string {
  const stem = `runanywhere_${id}`;
  if (platform === 'win32') return `${stem}.dll`;
  if (platform === 'darwin') return `lib${stem}.dylib`;
  return `lib${stem}.so`;
}

/** Shared commons sidecar beside a thin addon (`librac_commons.*`). */
export function commonsLibraryFileName(platform: NodeJS.Platform = process.platform): string {
  if (platform === 'win32') return 'rac_commons.dll';
  if (platform === 'darwin') return 'librac_commons.dylib';
  return 'librac_commons.so';
}

/** `prebuilds/<platform>-<arch>` under a backend package root. */
export function pluginPrebuildDir(locator: PluginArtifactLocator): string {
  const platform = locator.platform ?? process.platform;
  const arch = locator.arch ?? process.arch;
  return path.join(locator.packageRoot, 'prebuilds', `${platform}-${arch}`);
}

/**
 * Absolute path where Track A stages the loadable plugin. Does not require
 * the file to exist yet — fat-addon builds leave this empty until the shared
 * dylib spike lands.
 */
export function resolvePluginArtifactPath(locator: PluginArtifactLocator): string {
  const platform = locator.platform ?? process.platform;
  return path.join(pluginPrebuildDir(locator), pluginLibraryFileName(locator.id, platform));
}

/** Whether the resolved artifact is present on disk (thin-addon ready). */
export function pluginArtifactExists(locator: PluginArtifactLocator): boolean {
  return isExistingFile(resolvePluginArtifactPath(locator));
}

function isExistingFile(filePath: string): boolean {
  try {
    return fs.statSync(filePath).isFile();
  } catch {
    return false;
  }
}

/**
 * Append (or replace) a backend plugin path in the ordered registration queue
 * and refresh the fork env var. Main-process only.
 */
export function recordBackendPlugin(registration: BackendPluginRegistration): void {
  if (!path.isAbsolute(registration.pluginPath)) {
    throw new Error(
      `backend plugin path for ${registration.id} must be absolute (got ${registration.pluginPath})`
    );
  }
  _queue.set(registration.id, {
    id: registration.id,
    pluginPath: registration.pluginPath,
  });
  syncPluginPathsEnv();
}

/** Drop one backend (or all when omitted) and refresh the fork env var. */
export function unregisterBackendPlugin(id?: BackendPluginId): void {
  if (id === undefined) _queue.clear();
  else _queue.delete(id);
  syncPluginPathsEnv();
}

/**
 * Snapshot of every recorded registration in queue (insertion) order.
 * Replacing an id keeps its original position.
 */
export function recordedBackendPlugins(): readonly BackendPluginRegistration[] {
  return [..._queue.values()];
}

/**
 * Same registrations as {@link recordedBackendPlugins}, preferring canonical
 * id order for deterministic host loads when callers want a stable sequence.
 */
export function orderedBackendPlugins(): readonly BackendPluginRegistration[] {
  const byId = new Map(_queue);
  const out: BackendPluginRegistration[] = [];
  for (const id of CANONICAL_ORDER) {
    const entry = byId.get(id);
    if (entry) {
      out.push(entry);
      byId.delete(id);
    }
  }
  for (const entry of byId.values()) out.push(entry);
  return out;
}

export function isBackendPluginRegistered(id: BackendPluginId): boolean {
  return _queue.has(id);
}

/**
 * Absolute plugin paths that exist on disk, joined for RUNANYWHERE_PLUGIN_PATHS.
 * Missing artifacts (fat dual-path before Track A stages dylibs) are omitted so
 * the host does not try to dlopen a non-existent file. `undefined` when empty.
 */
export function backendPluginPathsEnvValue(): string | undefined {
  const paths = orderedBackendPlugins()
    .map((r) => r.pluginPath)
    .filter(isExistingFile);
  return paths.length > 0 ? paths.join(path.delimiter) : undefined;
}

/** Directories that hold registered plugin libs (for PATH / rpath sidecars). */
export function backendPluginSidecarDirs(): readonly string[] {
  const dirs = new Set<string>();
  for (const reg of orderedBackendPlugins()) {
    if (isExistingFile(reg.pluginPath)) dirs.add(path.dirname(reg.pluginPath));
  }
  return [...dirs];
}

/** Env key the utility host reads at startup (main→fork only). */
export const RUNANYWHERE_PLUGIN_PATHS_ENV = ENV_PLUGIN_PATHS;

function syncPluginPathsEnv(): void {
  const value = backendPluginPathsEnvValue();
  if (value === undefined) delete process.env[ENV_PLUGIN_PATHS];
  else process.env[ENV_PLUGIN_PATHS] = value;
}
