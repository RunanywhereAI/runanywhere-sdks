/**
 * `@runanywhere/electron/backend` — narrow contract for independently packaged
 * Electron backend packages (`@runanywhere/electron-llamacpp`, `-onnx`, `-sherpa`).
 *
 * Application main process:
 *   import { LlamaCPP } from '@runanywhere/electron-llamacpp';
 *   LlamaCPP.register(); // before RunAnywhereMain.connect()
 *
 * Backend packages call {@link recordBackendPlugin}; the core never
 * optionalDepends on backends. Paths cross into the utility host only via
 * `RUNANYWHERE_PLUGIN_PATHS` at `utilityProcess.fork` — never via RPC.
 */

export {
  BackendPluginId,
  RUNANYWHERE_PLUGIN_PATHS_ENV,
  backendPluginPathsEnvValue,
  backendPluginSidecarDirs,
  commonsLibraryFileName,
  isBackendPluginId,
  isBackendPluginRegistered,
  orderedBackendPlugins,
  pluginArtifactExists,
  pluginLibraryFileName,
  pluginPrebuildDir,
  recordBackendPlugin,
  recordedBackendPlugins,
  resolvePluginArtifactPath,
  unregisterBackendPlugin,
} from './backend/plugin-registry';
export type {
  BackendPluginRegistration,
  PluginArtifactLocator,
} from './backend/plugin-registry';
export {
  FAT_ADDON_FRAMEWORKS,
  assertBackendEnginesRegistered,
  backendsForRegistry,
  frameworksFromPluginNames,
  noBackendEnginesException,
  unavailableCapabilities,
} from './backend/engines';
export type { EngineRegistrySnapshot, RegisteredEngines } from './backend/engines';
