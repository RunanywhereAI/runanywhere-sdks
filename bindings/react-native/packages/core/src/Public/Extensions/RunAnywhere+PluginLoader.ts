/**
 * RunAnywhere+PluginLoader.ts
 *
 * Runtime plugin loader capability surface.
 * Matches Swift: RunAnywhere+PluginLoader.swift.
 */

import { SDKException } from '../../Foundation/Errors/SDKException';
import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import type { PluginInfo } from '@runanywhere/proto-ts/plugin_loader';
import { isJsonObject } from '../../services/JSONValidation';

/**
 * Information about a loaded plugin.
 * Generated from idl/plugin_loader.proto (`@runanywhere/proto-ts/plugin_loader`).
 * Matches Swift: PluginInfo.
 */
export type { PluginInfo };

/**
 * Runtime plugin management namespace.
 * Access via RunAnywhere.pluginLoader.
 */
export interface PluginLoaderCapability {
  readonly apiVersion: Promise<number>;
  readonly registeredCount: Promise<number>;
  registeredNames(): Promise<string[]>;
  listLoaded(): Promise<PluginInfo[]>;
  load(path: string): Promise<PluginInfo>;
  unload(name: string): Promise<void>;
}

function invalidPluginLoaderResponse(operation: string): never {
  throw SDKException.processingFailed(
    `${operation} returned an invalid JSON result`
  );
}

function parseNativeJSON(json: string, operation: string): unknown {
  try {
    const parsed: unknown = JSON.parse(json);
    return parsed;
  } catch {
    return invalidPluginLoaderResponse(operation);
  }
}

function decodePluginInfoValue(value: unknown, operation: string): PluginInfo {
  if (
    !isJsonObject(value) ||
    typeof value.name !== 'string' ||
    typeof value.path !== 'string'
  ) {
    return invalidPluginLoaderResponse(operation);
  }
  return { name: value.name, path: value.path };
}

/** Decode and validate the native registered-plugin name list. */
export function decodeRegisteredPluginNamesJSON(json: string): string[] {
  const operation = 'pluginLoader.registeredNames';
  const parsed = parseNativeJSON(json, operation);
  if (!Array.isArray(parsed) || !parsed.every((value) => typeof value === 'string')) {
    return invalidPluginLoaderResponse(operation);
  }
  return parsed;
}

/** Decode and validate the native loaded-plugin list. */
export function decodeLoadedPluginsJSON(json: string): PluginInfo[] {
  const operation = 'pluginLoader.listLoaded';
  const parsed = parseNativeJSON(json, operation);
  if (!Array.isArray(parsed)) {
    return invalidPluginLoaderResponse(operation);
  }
  return parsed.map((value) => decodePluginInfoValue(value, operation));
}

/** Decode and validate the native result of loading one plugin. */
export function decodeLoadedPluginJSON(json: string): PluginInfo {
  const operation = 'pluginLoader.load';
  return decodePluginInfoValue(parseNativeJSON(json, operation), operation);
}

export const pluginLoader: PluginLoaderCapability = {
  get apiVersion(): Promise<number> {
    return requirePluginLoaderNative().pluginLoaderApiVersion();
  },

  get registeredCount(): Promise<number> {
    return requirePluginLoaderNative().pluginLoaderRegisteredCount();
  },

  async registeredNames(): Promise<string[]> {
    return decodeRegisteredPluginNamesJSON(
      await requirePluginLoaderNative().pluginLoaderRegisteredNames()
    );
  },

  async listLoaded(): Promise<PluginInfo[]> {
    return decodeLoadedPluginsJSON(
      await requirePluginLoaderNative().pluginLoaderListLoaded()
    );
  },

  async load(path: string): Promise<PluginInfo> {
    if (!path.trim()) {
      throw SDKException.invalidInput('Plugin path is required');
    }
    return decodeLoadedPluginJSON(
      await requirePluginLoaderNative().pluginLoaderLoad(path)
    );
  },

  async unload(name: string): Promise<void> {
    if (!name.trim()) {
      throw SDKException.invalidInput('Plugin name is required');
    }
    await requirePluginLoaderNative().pluginLoaderUnload(name);
  },
};

type NativePluginLoader = {
  pluginLoaderApiVersion(): Promise<number>;
  pluginLoaderRegisteredCount(): Promise<number>;
  pluginLoaderRegisteredNames(): Promise<string>;
  pluginLoaderListLoaded(): Promise<string>;
  pluginLoaderLoad(path: string): Promise<string>;
  pluginLoaderUnload(name: string): Promise<void>;
};

function requirePluginLoaderNative(): NativePluginLoader {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule() as unknown as NativePluginLoader;
}
