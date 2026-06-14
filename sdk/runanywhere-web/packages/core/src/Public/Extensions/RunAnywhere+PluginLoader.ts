/**
 * RunAnywhere+PluginLoader.ts
 *
 * Runtime plugin-loader namespace. WebAssembly cannot dlopen arbitrary shared
 * libraries, so load/unload report feature-unavailable unless a future WASM
 * host exposes the dynamic loader ABI.
 */

import type { PluginInfo } from '@runanywhere/proto-ts/plugin_loader';
import { SDKException } from '../../Foundation/SDKException';
import {
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule';

export type { PluginInfo };

interface PluginLoaderModule extends EmscriptenRunanywhereModule {
  _rac_plugin_api_version?(): number;
  _rac_registry_plugin_count?(): number;
  _rac_registry_load_plugin?(pathPtr: number): number;
  _rac_registry_unload_plugin?(namePtr: number): number;
  _rac_registry_list_plugins?(outNamesPtr: number, outCountPtr: number): number;
  _rac_registry_free_plugin_list?(namesPtr: number, count: number): void;
}

function activeModule(): PluginLoaderModule | null {
  return tryRunanywhereModule() as PluginLoaderModule | null;
}

function missing(feature: string): never {
  throw SDKException.backendNotAvailable(
    feature,
    'The active Web WASM module does not expose the plugin-loader ABI.',
  );
}

function withUtf8<T>(
  module: PluginLoaderModule,
  value: string,
  body: (ptr: number) => T,
): T {
  const size = module.lengthBytesUTF8(value) + 1;
  const ptr = module._malloc(size);
  try {
    module.stringToUTF8(value, ptr, size);
    return body(ptr);
  } finally {
    module._free(ptr);
  }
}

export const PluginLoader = {
  get apiVersion(): number {
    const module = activeModule();
    if (!module || typeof module._rac_plugin_api_version !== 'function') {
      missing('pluginLoader.apiVersion');
    }
    return module._rac_plugin_api_version();
  },

  get registeredCount(): number {
    const module = activeModule();
    if (!module || typeof module._rac_registry_plugin_count !== 'function') {
      missing('pluginLoader.registeredCount');
    }
    return module._rac_registry_plugin_count();
  },

  registeredNames(): string[] {
    const module = activeModule();
    if (
      !module ||
      typeof module._rac_registry_list_plugins !== 'function' ||
      typeof module._rac_registry_free_plugin_list !== 'function'
    ) {
      missing('pluginLoader.registeredNames');
    }

    const outNamesPtr = module._malloc(4);
    const outCountPtr = module._malloc(4);
    try {
      module.HEAPU32[outNamesPtr >>> 2] = 0;
      module.HEAPU32[outCountPtr >>> 2] = 0;
      const rc = module._rac_registry_list_plugins(outNamesPtr, outCountPtr);
      if (rc !== 0) return [];

      const namesPtr = module.HEAPU32[outNamesPtr >>> 2] ?? 0;
      const count = module.HEAPU32[outCountPtr >>> 2] ?? 0;
      if (!namesPtr || count === 0) return [];

      const out: string[] = [];
      for (let i = 0; i < count; i += 1) {
        const cstr = module.HEAPU32[(namesPtr >>> 2) + i] ?? 0;
        if (cstr) out.push(module.UTF8ToString(cstr));
      }
      module._rac_registry_free_plugin_list(namesPtr, count);
      return out;
    } finally {
      module._free(outNamesPtr);
      module._free(outCountPtr);
    }
  },

  listLoaded(): PluginInfo[] {
    return this.registeredNames().map((name) => ({ name, path: '' }));
  },

  load(path: string): PluginInfo {
    if (!path.trim()) {
      // Swift taxonomy: bad input throws `validationFailed` (SDKException.swift:188-190).
      throw SDKException.validationFailed('Plugin path is required');
    }
    const module = activeModule();
    if (!module || typeof module._rac_registry_load_plugin !== 'function') {
      missing('pluginLoader.load');
    }
    const rc = withUtf8(module, path, (ptr) => module._rac_registry_load_plugin!(ptr));
    if (rc !== 0) {
      throw SDKException.fromRACResult(rc, `pluginLoader.load failed for ${path}`);
    }
    const stem = path.split('/').pop()?.replace(/\.[^.]+$/, '').replace(/^lib/, '') ?? path;
    return { name: stem, path };
  },

  unload(name: string): void {
    if (!name.trim()) {
      // Swift taxonomy: bad input throws `validationFailed` (SDKException.swift:188-190).
      throw SDKException.validationFailed('Plugin name is required');
    }
    const module = activeModule();
    if (!module || typeof module._rac_registry_unload_plugin !== 'function') {
      missing('pluginLoader.unload');
    }
    const rc = withUtf8(module, name, (ptr) => module._rac_registry_unload_plugin!(ptr));
    if (rc !== 0) {
      throw SDKException.fromRACResult(rc, `pluginLoader.unload failed for ${name}`);
    }
  },
};

export type PluginLoaderCapability = typeof PluginLoader;
