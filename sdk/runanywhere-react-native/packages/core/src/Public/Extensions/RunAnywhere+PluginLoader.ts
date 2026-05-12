/**
 * RunAnywhere+PluginLoader.ts
 *
 * Runtime plugin loader capability surface.
 * Matches Swift: RunAnywhere+PluginLoader.swift.
 */

import { ErrorCode as ErrorCodeProto } from '@runanywhere/proto-ts/errors';
import { SDKException } from '../../Foundation/Errors/SDKException';

/**
 * Information about a loaded plugin.
 * Matches Swift: PluginInfo.
 */
export interface PluginInfo {
  name: string;
  path: string;
}

/**
 * Runtime plugin management namespace.
 * Access via RunAnywhere.pluginLoader.
 */
export interface PluginLoaderCapability {
  readonly apiVersion: number;
  readonly registeredCount: number;
  registeredNames(): Promise<string[]>;
  listLoaded(): Promise<PluginInfo[]>;
  load(path: string): Promise<PluginInfo>;
  unload(name: string): Promise<void>;
}

export const pluginLoader: PluginLoaderCapability = {
  get apiVersion(): number {
    throw pluginLoaderUnavailable('apiVersion');
  },

  get registeredCount(): number {
    throw pluginLoaderUnavailable('registeredCount');
  },

  async registeredNames(): Promise<string[]> {
    throw pluginLoaderUnavailable('registeredNames');
  },

  async listLoaded(): Promise<PluginInfo[]> {
    throw pluginLoaderUnavailable('listLoaded');
  },

  async load(path: string): Promise<PluginInfo> {
    if (!path.trim()) {
      throw SDKException.invalidInput('Plugin path is required');
    }
    throw pluginLoaderUnavailable('load');
  },

  async unload(name: string): Promise<void> {
    if (!name.trim()) {
      throw SDKException.invalidInput('Plugin name is required');
    }
    throw pluginLoaderUnavailable('unload');
  },
};

function pluginLoaderUnavailable(operation: string): SDKException {
  return SDKException.of(
    ErrorCodeProto.ERROR_CODE_FEATURE_NOT_AVAILABLE,
    `PluginLoader.${operation} unavailable on React Native: native plugin loading is not implemented`
  );
}
