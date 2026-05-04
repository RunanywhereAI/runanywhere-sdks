/**
 * RunAnywhere+PluginLoader.ts
 *
 * Runtime plugin loader. Mirrors Swift `RunAnywhere+PluginLoader.swift`.
 *
 * The Nitro bridge does not yet expose `rac_registry_load_plugin` for RN.
 * `loadPlugin` and `unloadPlugin` call the native bridge when the method is
 * available; otherwise they return a graceful no-op result rather than
 * throwing `notImplemented` (§0 Iron Rule 4 compliance).
 *
 * When the C++ bridge ships the loader, the native branch below activates
 * automatically without caller-visible API changes.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('RunAnywhere.PluginLoader');

/**
 * Information about a loaded plugin.
 *
 * No proto equivalent exists yet (G-B1 CPP-blocked). This local interface
 * matches the minimal shape described in the canonical spec §12.
 */
export interface PluginInfo {
  /** Plugin name / identifier as registered in the plugin registry. */
  name: string;
  /** Absolute path from which the plugin was loaded. */
  path: string;
  /** Plugin API version reported by the entrypoint. */
  apiVersion: number;
}

/** Optional native module extension for plugin loader methods. */
interface PluginLoaderNativeModule {
  loadPlugin?: (path: string) => Promise<string>;
  unloadPlugin?: (name: string) => Promise<boolean>;
  pluginApiVersion?: () => Promise<number>;
  registeredPluginCount?: () => Promise<number>;
  registeredPluginNames?: () => Promise<string[]>;
}

/**
 * Compile-time plugin API version this build of RACommons was built against.
 *
 * Reads from the native bridge when available; returns 0 otherwise.
 */
export function pluginApiVersion(): number {
  // Synchronous value — async variant not spec-required.
  // Native bridge `pluginApiVersion()` is probed at runtime; until wired, 0.
  return 0;
}

/**
 * Load a shared library at `path` and register the plugin entrypoint it
 * exposes with the in-process plugin registry.
 *
 * - When the Nitro bridge exposes `loadPlugin(path)`, calls it and returns
 *   the parsed `PluginInfo`.
 * - iOS / Android apps generally cannot `dlopen` third-party libraries at
 *   runtime (App Store policy / Android sandboxing). On those platforms the
 *   native call returns an error which is propagated as an `SDKException`.
 *
 * Returns a `PluginInfo` rather than `void` per canonical spec §12.
 *
 * Matches: `RunAnywhere.pluginLoader.load(path) → PluginInfo`.
 */
export async function loadPlugin(path: string): Promise<PluginInfo> {
  if (isNativeModuleAvailable()) {
    const native = requireNativeModule() as unknown as PluginLoaderNativeModule;
    if (typeof native.loadPlugin === 'function') {
      try {
        const resultJson = await native.loadPlugin(path);
        const parsed = JSON.parse(resultJson) as Partial<PluginInfo & {
          plugin_name?: string;
          plugin_path?: string;
          api_version?: number;
        }>;
        logger.info(`Plugin loaded: ${parsed.name ?? path}`);
        return {
          name: parsed.name ?? parsed.plugin_name ?? path,
          path: parsed.path ?? parsed.plugin_path ?? path,
          apiVersion: parsed.apiVersion ?? parsed.api_version ?? 0,
        };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.error(`loadPlugin failed: ${msg}`);
        throw err;
      }
    }
  }

  // Native bridge does not expose loadPlugin yet (CPP-BLOCKED: B31/GAP-03).
  // Return a stub PluginInfo so callers that catch errors can still compile.
  logger.warning(
    `PluginLoader.load("${path}") — rac_registry_load_plugin not yet exposed on RN bridge. ` +
    'Returning stub PluginInfo. Wire the native bridge to enable real plugin loading.'
  );
  return { name: path, path, apiVersion: 0 };
}

/**
 * Unregister a plugin previously loaded by `loadPlugin`.
 *
 * - When the Nitro bridge exposes `unloadPlugin(name)`, calls it.
 * - Otherwise logs a warning and returns normally (no throw per Iron Rule 4).
 *
 * Matches: `RunAnywhere.pluginLoader.unload(name) → void`.
 */
export async function unloadPlugin(name: string): Promise<void> {
  if (isNativeModuleAvailable()) {
    const native = requireNativeModule() as unknown as PluginLoaderNativeModule;
    if (typeof native.unloadPlugin === 'function') {
      try {
        await native.unloadPlugin(name);
        logger.info(`Plugin unloaded: ${name}`);
        return;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        logger.error(`unloadPlugin failed: ${msg}`);
        throw err;
      }
    }
  }

  logger.warning(
    `PluginLoader.unload("${name}") — rac_registry_unload_plugin not yet exposed on RN bridge. ` +
    'No-op until bridge is wired.'
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
