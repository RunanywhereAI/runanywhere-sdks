/**
 * RunAnywhere+LoRA.ts
 *
 * Top-level LoRA adapter API — mirrors Swift `RunAnywhere+LoRA.swift`.
 *
 * The Web SDK has not yet wired the `rac_lora_*` C ABI into its WASM build,
 * so each method delegates to a `LoRAProvider` registered by a backend
 * package. When no provider is registered (today's default), the methods
 * throw a clear `BackendNotAvailable` SDK error instead of silently failing.
 *
 * Provider contract (extends-pattern; backends declare any subset):
 *   - `loadLoraAdapter(config)`
 *   - `removeLoraAdapter(path)`
 *   - `clearLoraAdapters()`
 *   - `getLoadedLoraAdapters() -> LoRAAdapterInfo[]`
 *   - `checkLoraCompatibility(path) -> LoraCompatibilityResult`
 *   - `registerLoraAdapter(entry)`
 *   - `loraAdaptersForModel(modelId) -> LoraAdapterCatalogEntry[]`
 *   - `allRegisteredLoraAdapters() -> LoraAdapterCatalogEntry[]`
 */

import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoraAdapterCatalogEntry,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

const logger = new SDKLogger('LoRA');

/**
 * Backend-supplied implementation. Optional methods let backends declare
 * partial support without breaking compile-time typing of the public API.
 */
export interface LoRAProvider {
  loadLoraAdapter?(config: LoRAAdapterConfig): Promise<LoRAAdapterInfo | void>;
  removeLoraAdapter?(path: string): Promise<void>;
  clearLoraAdapters?(): Promise<void>;
  getLoadedLoraAdapters?(): Promise<LoRAAdapterInfo[]>;
  checkLoraCompatibility?(adapterId: string, modelId: string): Promise<LoraCompatibilityResult>;
  registerLoraAdapter?(entry: LoraAdapterCatalogEntry): Promise<void>;
  loraAdaptersForModel?(modelId: string): Promise<LoraAdapterCatalogEntry[]>;
  allRegisteredLoraAdapters?(): Promise<LoraAdapterCatalogEntry[]>;
}

let _provider: LoRAProvider | null = null;

/** Backend hook: register the LoRA implementation. */
export function setLoRAProvider(provider: LoRAProvider | null): void {
  _provider = provider;
}

function require<TKey extends keyof LoRAProvider>(method: TKey): NonNullable<LoRAProvider[TKey]> {
  if (_provider == null || _provider[method] == null) {
    // Phase C-prime: throw SDKException — wraps proto-typed wire envelope.
    throw SDKException.backendNotAvailable(
      `LoRA.${String(method)}`,
      'No LoRA backend registered. Install the @runanywhere/web-llamacpp ' +
      'package (with LoRA WASM exports) and register it via `LlamaCPP.register()`.',
    );
  }
  return _provider[method] as NonNullable<LoRAProvider[TKey]>;
}

// ---------------------------------------------------------------------------
// Public API — mirror Swift signatures one-to-one.
// ---------------------------------------------------------------------------

/**
 * Load a LoRA adapter and return its info (§3 `lora.load`).
 * Returns `LoRAAdapterInfo` describing the loaded adapter.
 */
export async function loadLoraAdapter(config: LoRAAdapterConfig): Promise<LoRAAdapterInfo> {
  const result = await require('loadLoraAdapter')(config);
  logger.info(`LoRA adapter loaded: ${config.adapterPath}`);
  // If the backend returns LoRAAdapterInfo, use it; otherwise synthesize from config.
  if (result != null && typeof result === 'object' && 'adapterPath' in result) {
    return result as LoRAAdapterInfo;
  }
  return {
    adapterId: config.adapterId ?? '',
    adapterPath: config.adapterPath,
    scale: config.scale,
    applied: true,
  };
}

export async function removeLoraAdapter(path: string): Promise<void> {
  await require('removeLoraAdapter')(path);
  logger.info(`LoRA adapter removed: ${path}`);
}

export async function clearLoraAdapters(): Promise<void> {
  await require('clearLoraAdapters')();
  logger.info('All LoRA adapters cleared');
}

export async function getLoadedLoraAdapters(): Promise<LoRAAdapterInfo[]> {
  return require('getLoadedLoraAdapters')();
}

/**
 * Check LoRA adapter / model compatibility (§3 `lora.checkCompatibility`).
 * Canonical signature: `(adapterId: string, modelId: string)`.
 */
export async function checkLoraCompatibility(
  adapterId: string,
  modelId: string,
): Promise<LoraCompatibilityResult> {
  if (_provider?.checkLoraCompatibility == null) {
    return { isCompatible: false, errorMessage: 'LoRA support not available' };
  }
  return _provider.checkLoraCompatibility(adapterId, modelId);
}

export async function registerLoraAdapter(entry: LoraAdapterCatalogEntry): Promise<void> {
  await require('registerLoraAdapter')(entry);
  logger.info(`LoRA adapter registered: ${entry.id}`);
}

export async function loraAdaptersForModel(modelId: string): Promise<LoraAdapterCatalogEntry[]> {
  if (_provider?.loraAdaptersForModel == null) return [];
  return _provider.loraAdaptersForModel(modelId);
}

export async function allRegisteredLoraAdapters(): Promise<LoraAdapterCatalogEntry[]> {
  if (_provider?.allRegisteredLoraAdapters == null) return [];
  return _provider.allRegisteredLoraAdapters();
}

export const LoRA = {
  setProvider: setLoRAProvider,
  load: loadLoraAdapter,
  remove: removeLoraAdapter,
  clear: clearLoraAdapters,
  getLoaded: getLoadedLoraAdapters,
  checkCompatibility: checkLoraCompatibility,
  register: registerLoraAdapter,
  adaptersForModel: loraAdaptersForModel,
  allRegistered: allRegisteredLoraAdapters,
};
