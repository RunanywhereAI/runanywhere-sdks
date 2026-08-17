/**
 * NeuRT — Electron backend package registration (Apple Neural Engine via Core ML).
 *
 * Call from the Electron **main** process before `RunAnywhereMain.connect()`:
 *
 * ```ts
 * import { NeuRT } from '@runanywhere/electron-neurt';
 * NeuRT.register();
 * ```
 *
 * Records the absolute path to `runanywhere_neurt.dylib` and updates
 * `RUNANYWHERE_PLUGIN_PATHS` for the utility-host fork. Does **not** load the
 * plugin over RPC.
 *
 * ## What this backend needs, and why
 *
 * NeuRT runs prebuilt Core ML graphs on the Apple Neural Engine — macOS only
 * (`darwin-arm64`; there is no ANE on Intel Macs or any other platform). Unlike
 * QHexRT, there is no separate vendor runtime to stage beside the plugin: Core ML
 * is a system framework, and the actual `.mlpackage`/`.mlmodelc` graphs are
 * downloaded per model through the catalog, never baked into this package. Off
 * platform, the engine reports `BACKEND_UNAVAILABLE` and the router never
 * selects it, so a cross-platform app can depend on this package unconditionally.
 *
 * The FRAMEWORK a NeuRT catalog row declares is `COREML`, not `NEURT` — NeuRT is
 * the engine's identity (the codebase it wraps, matching `engines/neurt/`), Core
 * ML is the framework it executes, and only the framework has a proto ordinal
 * (`INFERENCE_FRAMEWORK_COREML`). This mirrors iOS, which registers the exact
 * same models with `framework: .coreml`.
 */

import * as path from 'node:path';

import {
  BackendPluginId,
  isBackendPluginRegistered,
  recordBackendPlugin,
  resolvePluginArtifactPath,
  unregisterBackendPlugin,
} from '@runanywhere/electron/backend';

export interface NeuRTRegisterOptions {
  /** Absolute override for the loadable plugin; defaults to this package's prebuild. */
  pluginPath?: string;
}

const PACKAGE_ROOT = path.join(__dirname, '..');

export const NeuRT = {
  get moduleId(): typeof BackendPluginId.NeuRT {
    return BackendPluginId.NeuRT;
  },

  get isRegistered(): boolean {
    return isBackendPluginRegistered(BackendPluginId.NeuRT);
  },

  /**
   * Record this package's plugin path for the next utility-host fork.
   * Idempotent for the same path; a different `pluginPath` replaces the prior entry.
   */
  register(options: NeuRTRegisterOptions = {}): void {
    const pluginPath =
      options.pluginPath ??
      resolvePluginArtifactPath({
        id: BackendPluginId.NeuRT,
        packageRoot: PACKAGE_ROOT,
      });
    recordBackendPlugin({ id: BackendPluginId.NeuRT, pluginPath });
  },

  /** Remove this backend from the main-process registry (and fork env). */
  unregister(): void {
    unregisterBackendPlugin(BackendPluginId.NeuRT);
  },
};
