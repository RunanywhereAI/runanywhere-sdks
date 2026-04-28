/**
 * RunAnywhere+PluginLoader.ts
 *
 * Runtime plugin loader. Mirrors Swift `RunAnywhere+PluginLoader.swift`.
 *
 * React Native does not currently expose `rac_registry_load_plugin`
 * across the Nitro bridge — every method here returns
 * `SDKException.notImplemented` so call sites can compile against the
 * canonical surface. When the C++ bridge ships the loader (B31/GAP-03),
 * these forwarders should swap to the native call without altering
 * caller signatures.
 */

import { SDKException } from '../../Foundation/ErrorTypes/SDKException';

/**
 * Compile-time plugin API version this build of RACommons was built
 * against. The Nitro bridge does not currently expose
 * `rac_plugin_api_version()`; returns 0 until wired.
 */
export function pluginApiVersion(): number {
  return 0;
}

/**
 * Load a shared library at `path` and register the plugin entrypoint
 * it exposes with the in-process plugin registry.
 *
 * iOS / Android RN apps cannot dlopen third-party libraries at runtime
 * (App Store policy, Android sandboxing). On those platforms this
 * always throws `SDKException.notImplemented` — bundle the engine via
 * SwiftPM / Gradle instead.
 */
export async function loadPlugin(_path: string): Promise<void> {
  throw SDKException.notImplemented(
    'PluginLoader.load — RN host does not expose rac_registry_load_plugin yet'
  );
}

/** Unregister a plugin previously loaded by `loadPlugin`. */
export async function unloadPlugin(_name: string): Promise<void> {
  throw SDKException.notImplemented(
    'PluginLoader.unload — RN host does not expose rac_registry_unload_plugin yet'
  );
}

/** Number of plugins currently registered. */
export function registeredPluginCount(): number {
  return 0;
}

/** Snapshot of currently-registered plugin names. */
export function registeredPluginNames(): readonly string[] {
  return [];
}
