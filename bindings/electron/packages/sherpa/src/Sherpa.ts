/**
 * Sherpa — Electron backend package registration.
 *
 * Call from the Electron **main** process before `RunAnywhereMain.connect()`:
 *
 * ```ts
 * import { Sherpa } from '@runanywhere/electron-sherpa';
 * Sherpa.register();
 * ```
 *
 * Records the absolute path to `librunanywhere_sherpa.*` for the utility-host
 * fork via `RUNANYWHERE_PLUGIN_PATHS`.
 */

import * as path from 'node:path';

import {
  BackendPluginId,
  isBackendPluginRegistered,
  recordBackendPlugin,
  resolvePluginArtifactPath,
  unregisterBackendPlugin,
} from '@runanywhere/electron/backend';

export interface SherpaRegisterOptions {
  /** Absolute override for the loadable plugin; defaults to this package's prebuild. */
  pluginPath?: string;
}

const PACKAGE_ROOT = path.join(__dirname, '..');

export const Sherpa = {
  get moduleId(): typeof BackendPluginId.Sherpa {
    return BackendPluginId.Sherpa;
  },

  get isRegistered(): boolean {
    return isBackendPluginRegistered(BackendPluginId.Sherpa);
  },

  register(options: SherpaRegisterOptions = {}): void {
    const pluginPath =
      options.pluginPath ??
      resolvePluginArtifactPath({
        id: BackendPluginId.Sherpa,
        packageRoot: PACKAGE_ROOT,
      });
    recordBackendPlugin({ id: BackendPluginId.Sherpa, pluginPath });
  },

  unregister(): void {
    unregisterBackendPlugin(BackendPluginId.Sherpa);
  },
};
