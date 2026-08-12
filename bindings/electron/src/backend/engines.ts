// engines.ts — runtime engine-registry helpers for the thin-addon / core-alone path.
//
// Fat builds statically link backends into runanywhere_native.node; thin builds
// load librunanywhere_* via rac_registry_load_plugin. When thin + zero plugins,
// initialize() must still succeed, but ensure()/capability probes throw a typed
// SDKException (never a crash). B5 wires capabilities() fully; this module is
// the shared probe both paths use.

import type { UnavailablePlugin } from '../bridge';
import { SDKException } from '../errors';
import { InferenceFramework } from '../api/types';
import type { UnavailableCapability } from '../api/types';
import { BackendPluginId } from './plugin-registry';

/**
 * What is serving right now — all a routing decision needs.
 *
 * Kept separate from {@link EngineRegistrySnapshot} so the load-path guards
 * below depend only on this: whether a backend failed is irrelevant to "can I
 * load a model", and a guard that demanded the failure list too would force
 * every caller to fetch data it does not use.
 */
export interface RegisteredEngines {
  /** True when the .node was built with RAC_ELECTRON_THIN_ADDON. */
  readonly thinAddon: boolean;
  /** Engine names currently in commons' plugin registry (`listPlugins()`). */
  readonly pluginNames: readonly string[];
}

/** Snapshot used by capabilities probes: what serves, plus what failed. */
export interface EngineRegistrySnapshot extends RegisteredEngines {
  /**
   * Backends that tried to register and were refused
   * (`listUnavailablePlugins()`). Empty on a healthy build. Kept beside
   * `pluginNames` because "what is serving" and "what is broken" are two
   * halves of the same answer — without this half, a backend that failed to
   * load is indistinguishable from one the app never asked for.
   */
  readonly unavailablePlugins: readonly UnavailablePlugin[];
}

/**
 * Map registry / package ids to {@link InferenceFramework} values.
 * Unknown names are ignored (cloud/mlx/neurt shells, test plugins, …).
 */
export function frameworksFromPluginNames(
  names: readonly string[]
): readonly InferenceFramework[] {
  const out: InferenceFramework[] = [];
  const seen = new Set<InferenceFramework>();
  for (const raw of names) {
    const id = normalizePluginName(raw);
    const framework = frameworkForPluginId(id);
    if (framework === undefined || seen.has(framework)) continue;
    seen.add(framework);
    out.push(framework);
  }
  return out;
}

function normalizePluginName(name: string): string {
  const trimmed = name.trim().toLowerCase();
  // Accept "llamacpp", "runanywhere_llamacpp", "librunanywhere_llamacpp".
  const stripped = trimmed
    .replace(/^lib/, '')
    .replace(/^runanywhere_/, '');
  return stripped;
}

function frameworkForPluginId(id: string): InferenceFramework | undefined {
  switch (id) {
    case BackendPluginId.LlamaCPP:
    case 'llama.cpp':
    case 'llama_cpp':
      return InferenceFramework.LLAMA_CPP;
    case BackendPluginId.ONNX:
      return InferenceFramework.ONNX;
    case BackendPluginId.Sherpa:
    case 'sherpa-onnx':
      return InferenceFramework.SHERPA;
    // The engine's CMake target is rac_backend_qhexrt, so a registry that
    // reports the target stem rather than the plugin stem still maps here.
    case BackendPluginId.QHexRT:
    case 'rac_backend_qhexrt':
      return InferenceFramework.QHEXRT;
    default:
      return undefined;
  }
}

/** Fat-addon default: all three engines are linked into the .node. */
export const FAT_ADDON_FRAMEWORKS: readonly InferenceFramework[] = [
  InferenceFramework.LLAMA_CPP,
  InferenceFramework.ONNX,
  InferenceFramework.SHERPA,
];

/**
 * {@link RegisteredEngines} plus the ledger, when the caller has it.
 *
 * The ledger is optional rather than required so the load-path guards keep
 * their narrower dependency: {@link EngineRegistrySnapshot} satisfies this
 * type, and a caller that only knows what is registered still gets an answer.
 */
type BackendQuery = RegisteredEngines & {
  readonly unavailablePlugins?: readonly UnavailablePlugin[];
};

/**
 * Backends this process can actually reach.
 *
 * Thin + empty registry → `[]` (core-alone). Fat starts from the compile-time
 * set, because a statically linked engine is a fact about the binary that is
 * true even before `initialize()` has populated the registry.
 *
 * Then the ledger subtracts. A statically linked backend can still be REFUSED
 * at registration (a stub build whose `capability_check` declines, an
 * unsupported machine) — and `UnavailablePlugin.path` is empty for exactly
 * that case, so there is no path to filter on, only the name. Without this
 * subtraction a refused engine is reported as both available (its modalities)
 * and unavailable (the ledger entry) in the same capability snapshot, which is
 * worse than either answer alone: an app that trusts `modalities` calls a
 * feature that cannot work.
 */
export function backendsForRegistry(snapshot: BackendQuery): readonly InferenceFramework[] {
  const base = snapshot.thinAddon
    ? frameworksFromPluginNames(snapshot.pluginNames)
    : FAT_ADDON_FRAMEWORKS;
  const refused = snapshot.unavailablePlugins;
  if (refused === undefined || refused.length === 0) return base;
  const refusedFrameworks = new Set(frameworksFromPluginNames(refused.map((p) => p.name)));
  if (refusedFrameworks.size === 0) return base;
  // The registry is the stronger witness. Commons drops a ledger entry the
  // moment the same name registers successfully
  // (`rac_plugin_availability_forget`), so a framework in BOTH lists is
  // serving — a stale entry must never retract a backend that answers.
  const serving = new Set(frameworksFromPluginNames(snapshot.pluginNames));
  return base.filter((framework) => !refusedFrameworks.has(framework) || serving.has(framework));
}

/**
 * `rac_result_t` values a refused backend actually comes back with, in the
 * words an app can show a user. Anything else falls back to the raw code —
 * better an unfamiliar number than a confident wrong explanation.
 */
const UNAVAILABLE_REASONS: ReadonlyMap<number, string> = new Map([
  // RAC_ERROR_CAPABILITY_UNSUPPORTED
  [
    -811,
    'the plugin declined registration (capability_check) — this build of the backend ' +
      'was compiled without its engine, or the hardware does not support it',
  ],
  // RAC_ERROR_PLUGIN_LOAD_FAILED
  [
    -820,
    'the plugin library could not be loaded (missing file, wrong architecture, or unresolved symbols)',
  ],
  // RAC_ERROR_ABI_VERSION_MISMATCH
  [-810, 'the plugin was built against a different plugin ABI than this SDK'],
  // RAC_ERROR_BACKEND_UNAVAILABLE
  [-604, 'the backend reported itself unavailable on this machine'],
]);

/**
 * Render commons' unavailability ledger as capability entries.
 *
 * This is what turns "speech silently does nothing" into "sherpa is
 * unavailable, and here is why" at the one place apps already look.
 */
export function unavailableCapabilities(
  plugins: readonly UnavailablePlugin[]
): UnavailableCapability[] {
  return plugins.map((plugin) => ({
    name: `backend:${plugin.name}`,
    reason:
      UNAVAILABLE_REASONS.get(plugin.status) ??
      `the plugin failed to register (rac_result_t ${plugin.status})`,
  }));
}

/** Typed failure when a thin core has no registered engines. */
export function noBackendEnginesException(): SDKException {
  return SDKException.noBackendEngines();
}

/**
 * Guard for model load / ensure paths.
 * Fat addons always pass. Thin addons with an empty registry throw
 * {@link noBackendEnginesException}.
 */
export function assertBackendEnginesRegistered(snapshot: RegisteredEngines): void {
  if (!snapshot.thinAddon) return;
  if (snapshot.pluginNames.length > 0) return;
  throw noBackendEnginesException();
}
