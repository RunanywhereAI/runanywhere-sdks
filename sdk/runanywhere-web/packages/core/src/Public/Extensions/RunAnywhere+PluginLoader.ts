/**
 * RunAnywhere+PluginLoader.ts
 *
 * Top-level plugin/extension management API — mirrors Swift's
 * `RunAnywhere+PluginLoader` extension. Exposes the canonical
 * `RunAnywhere.pluginLoader.*` namespace defined in CANONICAL_API.md §12.
 *
 * Surface:
 *   - `pluginLoader.apiVersion: number` — engine ABI version constant
 *   - `pluginLoader.load(path) → PluginInfo` — call rac_registry_load_plugin
 *   - `pluginLoader.unload(name) → void` — call rac_registry_unload_plugin
 *   - `pluginLoader.registeredCount: number`
 *   - `pluginLoader.registeredNames(): string[]`
 *
 * In addition the namespace keeps the web-specific `register / hasProvider /
 * hasCapability / cleanupAll` helpers backend packages use to install
 * themselves at runtime.
 */

import { SDKException } from '../../Foundation/SDKException';
import { ExtensionRegistry, type SDKExtension } from '../../Infrastructure/ExtensionRegistry';
import { ExtensionPoint, BackendCapability } from '../../Infrastructure/ExtensionPoint';
import type { ProviderCapability } from '../../Infrastructure/ProviderTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';

const logger = new SDKLogger('PluginLoader');

/** Minimal plugin descriptor — mirrors `rac_plugin_info_t` (commons C ABI). */
export interface PluginInfo {
  name: string;
  apiVersion: number;
  path?: string;
}

/**
 * Backend-supplied hook that wires the `rac_registry_load_plugin /
 * rac_registry_unload_plugin / rac_registry_get_plugin_count` C ABI calls.
 * Until a backend installs one of these, `load / unload / registeredCount /
 * registeredNames` throw `backendNotAvailable`.
 */
export interface PluginLoaderProvider {
  apiVersion?(): number;
  load?(path: string): Promise<PluginInfo>;
  unload?(name: string): Promise<void>;
  registeredCount?(): number;
  registeredNames?(): string[];
}

let _provider: PluginLoaderProvider | null = null;

/** Backend hook: register the plugin loader implementation. */
export function setPluginLoaderProvider(provider: PluginLoaderProvider | null): void {
  _provider = provider;
}

function requireMethod<TKey extends keyof PluginLoaderProvider>(
  method: TKey,
): NonNullable<PluginLoaderProvider[TKey]> {
  if (_provider == null || _provider[method] == null) {
    throw SDKException.backendNotAvailable(
      `PluginLoader.${String(method)}`,
      'No plugin-loader backend registered. Backend packages call ' +
      '`setPluginLoaderProvider(...)` after their WASM module exports ' +
      'the rac_registry_* symbols.',
    );
  }
  return _provider[method] as NonNullable<PluginLoaderProvider[TKey]>;
}

/**
 * Canonical `RunAnywhere.pluginLoader.*` namespace — mirrors Swift /
 * Kotlin / Flutter / RN.
 */
export const PluginLoader = {
  /**
   * The plugin engine ABI version. Defaults to 0 if no backend is
   * registered (matches commons `RAC_PLUGIN_API_VERSION = 0` for v0.20).
   */
  get apiVersion(): number {
    return _provider?.apiVersion?.() ?? 0;
  },

  /** Load a plugin from a path; throws `backendNotAvailable` if unset. */
  async load(path: string): Promise<PluginInfo> {
    return requireMethod('load')(path);
  },

  /** Unload a plugin by name; throws `backendNotAvailable` if unset. */
  async unload(name: string): Promise<void> {
    await requireMethod('unload')(name);
  },

  /**
   * Number of registered plugins reported by the backend.
   * Falls back to the JS-side `ExtensionRegistry` count when no backend
   * provider is installed (the JS extension count is a reasonable lower
   * bound for the canonical "plugins live in this process" question).
   */
  get registeredCount(): number {
    if (_provider?.registeredCount) return _provider.registeredCount();
    return ExtensionRegistry.getAll().length;
  },

  /** Names of registered plugins; falls back to JS extension names. */
  registeredNames(): string[] {
    if (_provider?.registeredNames) return _provider.registeredNames();
    return ExtensionRegistry.getAll().map((e) => e.extensionName);
  },

  // -------------------------------------------------------------------------
  // Web-specific helpers backend packages use to install themselves.
  // Not part of the canonical surface but kept here so backends don't have
  // to import a separate registry path.
  // -------------------------------------------------------------------------

  /** Register a `SDKExtension` so its `cleanup()` runs during `RunAnywhere.shutdown()`. */
  register(extension: SDKExtension): void {
    ExtensionRegistry.register(extension);
    logger.info(`Plugin registered: ${extension.extensionName}`);
  },

  /** Whether a provider for the given JS capability is currently registered. */
  hasProvider(capability: ProviderCapability): boolean {
    return ExtensionPoint.getProvider(capability) != null;
  },

  /** Whether a backend extension with the given capability is registered. */
  hasCapability(capability: BackendCapability): boolean {
    return ExtensionPoint.hasCapability(capability);
  },

  /**
   * Cleanup all registered extensions and reset the registry. Called by
   * `RunAnywhere.shutdown()` — exposed here for tests that want to tear
   * down extensions without a full shutdown.
   */
  cleanupAll(): void {
    ExtensionRegistry.cleanupAll();
    ExtensionPoint.cleanupAll();
    ExtensionRegistry.reset();
    ExtensionPoint.reset();
  },
};
