/**
 * LlamaCPP — Electron backend package registration.
 *
 * Call from the Electron **main** process before `RunAnywhereMain.connect()`:
 *
 * ```ts
 * import { LlamaCPP } from '@runanywhere/electron-llamacpp';
 * LlamaCPP.register();
 * ```
 *
 * Records the absolute path to `librunanywhere_llamacpp.*` and updates
 * `RUNANYWHERE_PLUGIN_PATHS` for the utility-host fork. Does **not** load the
 * plugin over RPC.
 *
 * Dual path: until Track A ships shared `librac_commons` + a thin addon, the
 * fat `runanywhere_native.node` already links llamacpp. `register()` still
 * records the canonical plugin path so apps can adopt the multi-package API
 * now; the host ignores missing artifacts while the fat addon is in use.
 */

import * as path from 'node:path';

import {
  BackendPluginId,
  isBackendPluginRegistered,
  recordBackendPlugin,
  resolvePluginArtifactPath,
  unregisterBackendPlugin,
} from '@runanywhere/electron/backend';

export interface LlamaCPPRegisterOptions {
  /** Absolute override for the loadable plugin; defaults to this package's prebuild. */
  pluginPath?: string;
}

const PACKAGE_ROOT = path.join(__dirname, '..');

export const LlamaCPP = {
  get moduleId(): typeof BackendPluginId.LlamaCPP {
    return BackendPluginId.LlamaCPP;
  },

  get isRegistered(): boolean {
    return isBackendPluginRegistered(BackendPluginId.LlamaCPP);
  },

  /**
   * Record this package's plugin path for the next utility-host fork.
   * Idempotent for the same path; a different `pluginPath` replaces the prior entry.
   */
  register(options: LlamaCPPRegisterOptions = {}): void {
    const pluginPath =
      options.pluginPath ??
      resolvePluginArtifactPath({
        id: BackendPluginId.LlamaCPP,
        packageRoot: PACKAGE_ROOT,
      });
    recordBackendPlugin({ id: BackendPluginId.LlamaCPP, pluginPath });
  },

  /** Remove this backend from the main-process registry (and fork env). */
  unregister(): void {
    unregisterBackendPlugin(BackendPluginId.LlamaCPP);
  },
};
