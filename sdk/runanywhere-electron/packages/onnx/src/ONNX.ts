/**
 * ONNX — Electron backend package registration.
 *
 * Call from the Electron **main** process before `RunAnywhereMain.connect()`:
 *
 * ```ts
 * import { ONNX } from '@runanywhere/electron-onnx';
 * ONNX.register();
 * ```
 *
 * Records the absolute path to `librunanywhere_onnx.*` for the utility-host
 * fork via `RUNANYWHERE_PLUGIN_PATHS`. Speech (STT/TTS/VAD) lives in the
 * separate `@runanywhere/electron-sherpa` package.
 */

import * as path from 'node:path';

import {
  BackendPluginId,
  isBackendPluginRegistered,
  recordBackendPlugin,
  resolvePluginArtifactPath,
  unregisterBackendPlugin,
} from '@runanywhere/electron/backend';

export interface ONNXRegisterOptions {
  /** Absolute override for the loadable plugin; defaults to this package's prebuild. */
  pluginPath?: string;
}

const PACKAGE_ROOT = path.join(__dirname, '..');

export const ONNX = {
  get moduleId(): typeof BackendPluginId.ONNX {
    return BackendPluginId.ONNX;
  },

  get isRegistered(): boolean {
    return isBackendPluginRegistered(BackendPluginId.ONNX);
  },

  register(options: ONNXRegisterOptions = {}): void {
    const pluginPath =
      options.pluginPath ??
      resolvePluginArtifactPath({
        id: BackendPluginId.ONNX,
        packageRoot: PACKAGE_ROOT,
      });
    recordBackendPlugin({ id: BackendPluginId.ONNX, pluginPath });
  },

  unregister(): void {
    unregisterBackendPlugin(BackendPluginId.ONNX);
  },
};
