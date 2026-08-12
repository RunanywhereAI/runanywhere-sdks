/**
 * NitroModulesGlobalInit.ts
 *
 * Global singleton for NitroModules initialization.
 * Caches the NitroModules proxy installed by react-native-nitro-modules,
 * preventing duplicate native install() calls for the same JS runtime.
 *
 * All packages should import and use this for safe NitroModules access.
 */

import { NitroModules as NitroModulesNamed } from 'react-native-nitro-modules';
import type { NitroModulesProxy } from 'react-native-nitro-modules/lib/typescript/NitroModulesProxy';
import { SDKLogger } from '../Foundation/Logging';

/**
 * The NitroModules proxy used by the SDK. Typed as a structural subset of
 * `NitroModulesProxy` to avoid depending on non-exported implementation types.
 */
export type NitroProxy = Pick<NitroModulesProxy, 'createHybridObject'>;

/** Global promise that tracks NitroModules installation */
let _nitroInstallationPromise: Promise<NitroProxy> | null = null;

/** Cached NitroModules proxy after successful installation */
let _nitroModulesProxy: NitroProxy | null = null;

/**
 * Initialize NitroModules globally, ensuring the SDK caches one proxy instance.
 * This MUST be called before any other modules try to access NitroModules.
 *
 * @returns Promise resolving to NitroModules proxy
 */
export async function initializeNitroModulesGlobally(): Promise<NitroProxy> {
  // If already initialized, return cached proxy
  if (_nitroModulesProxy !== null) {
    return _nitroModulesProxy;
  }

  // If initialization is in progress, return the existing promise
  if (_nitroInstallationPromise !== null) {
    return _nitroInstallationPromise;
  }

  // Create the initialization promise
  _nitroInstallationPromise = (async () => {
    try {
      SDKLogger.core.debug('[NitroModulesGlobalInit] Starting global initialization...');

      // Importing react-native-nitro-modules installs Nitro into the current
      // runtime. Calling NativeModules.NitroModules.install() again for the same
      // Hermes runtime logs a false duplicate __nitroDispatcher failure.
      _nitroModulesProxy = NitroModulesNamed as unknown as NitroProxy;

      if (!_nitroModulesProxy) {
        throw new Error(
          'NitroModules is not available after initialization. ' +
          'Make sure react-native-nitro-modules is properly installed and linked.'
        );
      }

      SDKLogger.core.debug('[NitroModulesGlobalInit] Global initialization successful');
      return _nitroModulesProxy;
    } catch (error) {
      SDKLogger.core.error('[NitroModulesGlobalInit] Failed to initialize NitroModules', { error });
      _nitroInstallationPromise = null; // Reset on error to allow retry
      throw error;
    }
  })();

  return _nitroInstallationPromise;
}

/**
 * Get the NitroModules proxy synchronously.
 *
 * Falls back to the static `react-native-nitro-modules` import (and caches it)
 * when `initializeNitroModulesGlobally()` has not run yet. The proxy is the
 * synchronous import object — the same value the async initializer assigns — so
 * this fallback is equivalent and idempotent. Without it, callers that run
 * before `RunAnywhere.initialize()` (e.g. backend `register()` during app
 * bootstrap) incorrectly see "native module not available".
 *
 * @returns NitroModules proxy, or null only if the import itself is unavailable
 */
export function getNitroModulesProxySync(): NitroProxy | null {
  if (_nitroModulesProxy === null && NitroModulesNamed) {
    _nitroModulesProxy = NitroModulesNamed as unknown as NitroProxy;
  }
  return _nitroModulesProxy;
}

/**
 * Check if NitroModules has been initialized
 */
export function isNitroModulesInitialized(): boolean {
  return _nitroModulesProxy !== null;
}
