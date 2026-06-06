/**
 * RunAnywhere+PluginLoader.ts
 *
 * Runtime plugin loader capability surface.
 * Matches Swift: RunAnywhere+PluginLoader.swift.
 */

import { SDKException } from '../../Foundation/Errors/SDKException';
import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import type { PluginInfo } from '@runanywhere/proto-ts/plugin_loader';

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

export const pluginLoader: PluginLoaderCapability = {
  get apiVersion(): Promise<number> {
    return requirePluginLoaderNative().pluginLoaderApiVersion();
  },

  get registeredCount(): Promise<number> {
    return requirePluginLoaderNative().pluginLoaderRegisteredCount();
  },

  async registeredNames(): Promise<string[]> {
    return JSON.parse(
      await requirePluginLoaderNative().pluginLoaderRegisteredNames()
    ) as string[];
  },

  async listLoaded(): Promise<PluginInfo[]> {
    return JSON.parse(
      await requirePluginLoaderNative().pluginLoaderListLoaded()
    ) as PluginInfo[];
  },

  async load(path: string): Promise<PluginInfo> {
    if (!path.trim()) {
      throw SDKException.invalidInput('Plugin path is required');
    }
    return JSON.parse(
      await requirePluginLoaderNative().pluginLoaderLoad(path)
    ) as PluginInfo;
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
