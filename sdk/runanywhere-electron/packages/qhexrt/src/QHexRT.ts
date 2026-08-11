/**
 * QHexRT — Electron backend package registration (Qualcomm Hexagon NPU).
 *
 * Call from the Electron **main** process before `RunAnywhereMain.connect()`:
 *
 * ```ts
 * import { QHexRT } from '@runanywhere/electron-qhexrt';
 * QHexRT.register();
 * ```
 *
 * Records the absolute path to `runanywhere_qhexrt.dll` and updates
 * `RUNANYWHERE_PLUGIN_PATHS` for the utility-host fork. Does **not** load the
 * plugin over RPC.
 *
 * ## What this backend needs beside the plugin, and why
 *
 * QHexRT runs prebuilt QNN context binaries on a Hexagon NPU. On Windows on
 * ARM64 (Snapdragon X / X2 Elite) that is a *real* NPU target, not a simulator:
 * QAIRT ships a native `aarch64-windows-msvc` HTP stack and published `v81`
 * bundles load unmodified. Three packaging rules follow, and all three are
 * enforced by shipping the runtime **in this package's prebuild directory**:
 *
 *  1. **One flat folder.** `QnnHtp.dll`, `QnnSystem.dll`, `QnnHtpPrepare.dll`
 *     and `QnnHtpV<arch>Stub.dll` (from `lib/aarch64-windows-msvc/`) sit beside
 *     `libQnnHtpV<arch>Skel.so` **and `libqnnhtpv<arch>.cat`** (from
 *     `lib/hexagon-v<arch>/unsigned/`). There is no `ADSP_LIBRARY_PATH` on
 *     Windows — the loader resolves through the DLL's own directory.
 *  2. **The `.cat` is mandatory.** Without it the skel fails signature
 *     verification, and the failure surfaces with no message naming the catalog
 *     — it reads exactly like a corrupt bundle.
 *  3. **The engine opens QNN by bare name at runtime** (`LoadLibraryW("QnnHtp.dll")`),
 *     which searches the *executable's* directory, the system dirs, then PATH —
 *     never beside the addon. `bridge.ts` prepends every registered plugin
 *     directory to PATH for exactly this reason, so staging the flat set here is
 *     what makes the NPU visible at all.
 *
 * The deployed QAIRT must also be **>= the QAIRT that compiled the bundle**. A
 * v81 bundle compiled on 2.47 fails `contextCreateFromBinary` with `err=0x1388`
 * on 2.41 and loads on 2.48; the only actionable text is in the backend's
 * stderr, never in the status code.
 *
 * Bundles are arch-pinned (`dsp_arch` + `soc_model` are baked in): a `v79`
 * context binary does not *load* on a `v81` device. That is a load failure, not
 * wrong output.
 */

import * as path from 'node:path';

import {
  BackendPluginId,
  isBackendPluginRegistered,
  recordBackendPlugin,
  resolvePluginArtifactPath,
  unregisterBackendPlugin,
} from '@runanywhere/electron/backend';

export interface QHexRTRegisterOptions {
  /** Absolute override for the loadable plugin; defaults to this package's prebuild. */
  pluginPath?: string;
}

const PACKAGE_ROOT = path.join(__dirname, '..');

export const QHexRT = {
  get moduleId(): typeof BackendPluginId.QHexRT {
    return BackendPluginId.QHexRT;
  },

  get isRegistered(): boolean {
    return isBackendPluginRegistered(BackendPluginId.QHexRT);
  },

  /**
   * Record this package's plugin path for the next utility-host fork.
   * Idempotent for the same path; a different `pluginPath` replaces the prior entry.
   */
  register(options: QHexRTRegisterOptions = {}): void {
    const pluginPath =
      options.pluginPath ??
      resolvePluginArtifactPath({
        id: BackendPluginId.QHexRT,
        packageRoot: PACKAGE_ROOT,
      });
    recordBackendPlugin({ id: BackendPluginId.QHexRT, pluginPath });
  },

  /** Remove this backend from the main-process registry (and fork env). */
  unregister(): void {
    unregisterBackendPlugin(BackendPluginId.QHexRT);
  },
};
