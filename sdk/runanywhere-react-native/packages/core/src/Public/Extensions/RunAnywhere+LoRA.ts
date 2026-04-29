/**
 * RunAnywhere+LoRA.ts
 *
 * Public API for LoRA adapter management. Wave 2: aligned to
 * proto-canonical LoRA shapes (`@runanywhere/proto-ts/lora_options`).
 *
 * Matches Swift: `Public/Extensions/LLM/RunAnywhere+LoRA.swift`. Surface
 * follows the canonical cross-SDK namespace shape — `RunAnywhere.lora.*`:
 *
 *   await RunAnywhere.lora.load({ adapterPath, scale })
 *   await RunAnywhere.lora.remove(adapterPath)
 *   await RunAnywhere.lora.clear()
 *   const loaded = await RunAnywhere.lora.getLoaded()
 *   const compat = await RunAnywhere.lora.checkCompatibility(adapterPath)
 *   await RunAnywhere.lora.register({ id, name, ... })
 *   const list = await RunAnywhere.lora.adaptersForModel(modelId)
 *   const all  = await RunAnywhere.lora.allRegistered()
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

const logger = new SDKLogger('RunAnywhere.LoRA');

interface LoRANativeModule {
  loadLoraAdapter?: (configJson: string) => Promise<boolean>;
  removeLoraAdapter?: (path: string) => Promise<boolean>;
  clearLoraAdapters?: () => Promise<boolean>;
  getLoadedLoraAdapters?: () => Promise<string>;
  /** Accepts `adapterId` and optional `modelId` (passed as JSON object). */
  checkLoraCompatibility?: (adapterId: string, modelId?: string) => Promise<string>;
  registerLoraAdapter?: (entryJson: string) => Promise<boolean>;
  loraAdaptersForModel?: (modelId: string) => Promise<string>;
  allRegisteredLoraAdapters?: () => Promise<string>;
}

function getNative(): LoRANativeModule {
  return requireNativeModule() as unknown as LoRANativeModule;
}

// ============================================================================
// Runtime Operations
// ============================================================================

/**
 * Load and apply a LoRA adapter to the currently loaded model.
 *
 * Returns `LoRAAdapterInfo` describing the applied adapter, as specified by
 * the canonical cross-SDK spec §3.
 *
 * Canonical: `RunAnywhere.lora.load(config) → LoRAAdapterInfo`.
 */
async function load(config: LoRAAdapterConfig): Promise<LoRAAdapterInfo> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.loadLoraAdapter) {
    throw new Error(
      'LoRA adapter loading is not supported by the current LLM backend'
    );
  }
  const configJson = JSON.stringify({
    path: config.adapterPath,
    scale: config.scale ?? 1.0,
    adapter_id: config.adapterId,
  });
  const ok = await native.loadLoraAdapter(configJson);
  if (!ok) {
    throw new Error(`Failed to load LoRA adapter: ${config.adapterPath}`);
  }
  logger.info(`LoRA adapter loaded: ${config.adapterPath}`);
  // Return an LoRAAdapterInfo constructed from the config values.
  // The native bridge returns bool only; callers that need the full proto
  // info should call `lora.getLoaded()` after loading.
  return {
    adapterId: config.adapterId ?? '',
    adapterPath: config.adapterPath,
    scale: config.scale ?? 1.0,
    applied: true,
  };
}

/**
 * Remove a specific LoRA adapter by path.
 *
 * Canonical: `RunAnywhere.lora.remove(adapterId)`.
 */
async function remove(adapterId: string): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.removeLoraAdapter) {
    throw new Error(
      'LoRA adapter removal is not supported by the current LLM backend'
    );
  }
  const ok = await native.removeLoraAdapter(adapterId);
  if (!ok) {
    throw new Error(`Failed to remove LoRA adapter: ${adapterId}`);
  }
  logger.info(`LoRA adapter removed: ${adapterId}`);
}

/** Remove all loaded LoRA adapters. Canonical: `RunAnywhere.lora.clear()`. */
async function clear(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.clearLoraAdapters) {
    throw new Error(
      'LoRA adapter clearing is not supported by the current LLM backend'
    );
  }
  await native.clearLoraAdapters();
  logger.info('All LoRA adapters cleared');
}

/**
 * Get info about all currently loaded LoRA adapters.
 *
 * Canonical: `RunAnywhere.lora.getLoaded()`.
 */
async function getLoaded(): Promise<LoRAAdapterInfo[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = getNative();
  if (!native.getLoadedLoraAdapters) return [];
  const json = await native.getLoadedLoraAdapters();
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr.map(
      (entry: {
        path?: string;
        adapter_path?: string;
        adapterPath?: string;
        scale?: number;
        applied?: boolean;
        adapter_id?: string;
        adapterId?: string;
        error_message?: string;
        errorMessage?: string;
      }): LoRAAdapterInfo => ({
        adapterId: entry.adapter_id ?? entry.adapterId ?? '',
        adapterPath:
          entry.adapter_path ?? entry.adapterPath ?? entry.path ?? '',
        scale: entry.scale ?? 1.0,
        applied: entry.applied ?? false,
        errorMessage: entry.error_message ?? entry.errorMessage,
      })
    );
  } catch {
    return [];
  }
}

/**
 * Check LoRA adapter compatibility with a model.
 *
 * Both `adapterId` and `modelId` are forwarded to the native bridge. When
 * `modelId` is omitted the bridge checks against the currently loaded model.
 *
 * Canonical: `RunAnywhere.lora.checkCompatibility(adapterId, modelId)` (§3).
 */
async function checkCompatibility(
  adapterId: string,
  modelId?: string,
): Promise<LoraCompatibilityResult> {
  if (!isNativeModuleAvailable()) {
    return { isCompatible: false, errorMessage: 'SDK not initialized' };
  }
  const native = getNative();
  if (!native.checkLoraCompatibility) {
    return { isCompatible: false, errorMessage: 'LoRA support not available' };
  }
  // Pass modelId to the bridge when provided so the C ABI can verify
  // compatibility against a specific base model (not just the loaded one).
  const json = await native.checkLoraCompatibility(adapterId, modelId);
  try {
    const result = JSON.parse(json) as {
      isCompatible?: boolean;
      is_compatible?: boolean;
      error?: string;
      error_message?: string;
      errorMessage?: string;
      base_model_required?: string;
      baseModelRequired?: string;
    };
    return {
      isCompatible: !!(result.isCompatible ?? result.is_compatible),
      errorMessage:
        result.error_message ?? result.errorMessage ?? result.error,
      baseModelRequired: result.base_model_required ?? result.baseModelRequired,
    };
  } catch {
    return {
      isCompatible: false,
      errorMessage: 'Failed to parse compatibility result',
    };
  }
}

// ============================================================================
// Catalog Operations
// ============================================================================

/**
 * Register a LoRA adapter configuration with the SDK so it can be
 * referenced by `adapterId` in subsequent `load` calls.
 *
 * Accepts `LoRAAdapterConfig` per the canonical cross-SDK spec §3.
 *
 * Canonical: `RunAnywhere.lora.register(config: LoRAAdapterConfig) → void`.
 */
async function register(config: LoRAAdapterConfig): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.registerLoraAdapter) {
    throw new Error(
      'LoRA registration is not supported by the current LLM backend'
    );
  }
  const entryJson = JSON.stringify({
    path: config.adapterPath,
    scale: config.scale ?? 1.0,
    adapter_id: config.adapterId,
  });
  const ok = await native.registerLoraAdapter(entryJson);
  if (!ok) {
    throw new Error(`Failed to register LoRA adapter: ${config.adapterPath}`);
  }
  logger.info(`LoRA adapter registered: ${config.adapterPath}`);
}

/**
 * Get all LoRA adapters compatible with a specific model.
 *
 * Canonical: `RunAnywhere.lora.adaptersForModel(modelId) → LoRAAdapterInfo[]` (§3).
 */
async function adaptersForModel(
  modelId: string,
): Promise<LoRAAdapterInfo[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = getNative();
  if (!native.loraAdaptersForModel) return [];
  const json = await native.loraAdaptersForModel(modelId);
  return parseAdapterInfoEntries(json);
}

/**
 * Get all registered LoRA adapters.
 *
 * Canonical: `RunAnywhere.lora.allRegistered() → LoRAAdapterInfo[]` (§3).
 */
async function allRegistered(): Promise<LoRAAdapterInfo[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = getNative();
  if (!native.allRegisteredLoraAdapters) return [];
  const json = await native.allRegisteredLoraAdapters();
  return parseAdapterInfoEntries(json);
}

function parseAdapterInfoEntries(json: string): LoRAAdapterInfo[] {
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr.map(
      (entry: {
        adapter_id?: string;
        adapterId?: string;
        id?: string;
        adapter_path?: string;
        adapterPath?: string;
        path?: string;
        scale?: number;
        applied?: boolean;
        error_message?: string;
        errorMessage?: string;
      }): LoRAAdapterInfo => ({
        adapterId: entry.adapter_id ?? entry.adapterId ?? entry.id ?? '',
        adapterPath: entry.adapter_path ?? entry.adapterPath ?? entry.path ?? '',
        scale: entry.scale ?? 1.0,
        applied: entry.applied ?? false,
        errorMessage: entry.error_message ?? entry.errorMessage,
      })
    );
  } catch {
    return [];
  }
}

// ============================================================================
// Canonical namespace export
// ============================================================================

/**
 * `RunAnywhere.lora` namespace — canonical cross-SDK shape.
 *
 * Mirror of Swift `RunAnywhere.lora.load(...)` and Web/Flutter/Kotlin
 * once the same alignment lands there. Stateless wrapper: each call
 * dispatches into the LLM component native bridge.
 */
export const lora = {
  load,
  remove,
  clear,
  getLoaded,
  checkCompatibility,
  register,
  adaptersForModel,
  allRegistered,
};
