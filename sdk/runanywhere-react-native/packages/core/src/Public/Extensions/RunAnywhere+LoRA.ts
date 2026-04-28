/**
 * RunAnywhere+LoRA.ts
 *
 * Public API for LoRA adapter management on the RN SDK.
 * Routes through the same native module as the rest of the LLM surface so
 * runtime ops are dispatched via `rac_llm_*` and catalog ops via the LoRA
 * registry.
 *
 * Matches iOS: RunAnywhere+LoRA.swift
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoraAdapterCatalogEntry,
  LoraCompatibilityResult,
} from '../../types/LoRATypes';

const logger = new SDKLogger('RunAnywhere.LoRA');

/**
 * Native module surface for LoRA. These methods dispatch through the same
 * Nitro hybrid object that owns the rest of the LLM bridge. Each method is
 * optional because backends without LoRA support can simply omit them.
 */
interface LoRANativeModule {
  loadLoraAdapter?: (configJson: string) => Promise<boolean>;
  removeLoraAdapter?: (path: string) => Promise<boolean>;
  clearLoraAdapters?: () => Promise<boolean>;
  getLoadedLoraAdapters?: () => Promise<string>;
  checkLoraCompatibility?: (path: string) => Promise<string>;
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
 * Multiple adapters can be stacked. Context is recreated internally.
 *
 * Matches Swift: `RunAnywhere.loadLoraAdapter(_:)`
 */
export async function loadLoraAdapter(
  config: LoRAAdapterConfig
): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.loadLoraAdapter) {
    throw new Error('LoRA adapter loading is not supported by the current LLM backend');
  }
  const configJson = JSON.stringify({
    path: config.path,
    scale: config.scale ?? 1.0,
  });
  const ok = await native.loadLoraAdapter(configJson);
  if (!ok) {
    throw new Error(`Failed to load LoRA adapter: ${config.path}`);
  }
  logger.info(`LoRA adapter loaded: ${config.path}`);
}

/**
 * Remove a specific LoRA adapter by path.
 *
 * Matches Swift: `RunAnywhere.removeLoraAdapter(_:)`
 */
export async function removeLoraAdapter(path: string): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.removeLoraAdapter) {
    throw new Error('LoRA adapter removal is not supported by the current LLM backend');
  }
  const ok = await native.removeLoraAdapter(path);
  if (!ok) {
    throw new Error(`Failed to remove LoRA adapter: ${path}`);
  }
  logger.info(`LoRA adapter removed: ${path}`);
}

/**
 * Remove all loaded LoRA adapters.
 *
 * Matches Swift: `RunAnywhere.clearLoraAdapters()`
 */
export async function clearLoraAdapters(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.clearLoraAdapters) {
    throw new Error('LoRA adapter clearing is not supported by the current LLM backend');
  }
  await native.clearLoraAdapters();
  logger.info('All LoRA adapters cleared');
}

/**
 * Get info about all currently loaded LoRA adapters.
 *
 * Matches Swift: `RunAnywhere.getLoadedLoraAdapters()`
 */
export async function getLoadedLoraAdapters(): Promise<LoRAAdapterInfo[]> {
  if (!isNativeModuleAvailable()) {
    return [];
  }
  const native = getNative();
  if (!native.getLoadedLoraAdapters) {
    return [];
  }
  const json = await native.getLoadedLoraAdapters();
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr.map((entry: { path?: string; scale?: number; applied?: boolean }) => ({
      path: entry.path ?? '',
      scale: entry.scale ?? 1.0,
      applied: entry.applied ?? false,
    }));
  } catch {
    return [];
  }
}

/**
 * Check if a LoRA adapter file is compatible with the currently loaded model.
 * This is a lightweight pre-check; the definitive check happens on load.
 *
 * Matches Swift: `RunAnywhere.checkLoraCompatibility(loraPath:)`
 */
export async function checkLoraCompatibility(
  loraPath: string
): Promise<LoraCompatibilityResult> {
  if (!isNativeModuleAvailable()) {
    return { isCompatible: false, error: 'SDK not initialized' };
  }
  const native = getNative();
  if (!native.checkLoraCompatibility) {
    return { isCompatible: false, error: 'LoRA support not available' };
  }
  const json = await native.checkLoraCompatibility(loraPath);
  try {
    const result = JSON.parse(json);
    return {
      isCompatible: !!result.isCompatible,
      error: result.error,
    };
  } catch {
    return { isCompatible: false, error: 'Failed to parse compatibility result' };
  }
}

// ============================================================================
// Catalog Operations
// ============================================================================

/**
 * Register a LoRA adapter in the SDK catalog at app startup.
 * Call this before loading any adapters so the SDK knows what's available.
 *
 * Matches Swift: `RunAnywhere.registerLoraAdapter(_:)`
 */
export async function registerLoraAdapter(
  entry: LoraAdapterCatalogEntry
): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.registerLoraAdapter) {
    throw new Error('LoRA registration is not supported by the current LLM backend');
  }
  const entryJson = JSON.stringify({
    id: entry.id,
    name: entry.name,
    description: entry.description,
    download_url: entry.downloadURL,
    filename: entry.filename,
    compatible_model_ids: entry.compatibleModelIds,
    file_size: entry.fileSize ?? 0,
    default_scale: entry.defaultScale ?? 1.0,
  });
  const ok = await native.registerLoraAdapter(entryJson);
  if (!ok) {
    throw new Error(`Failed to register LoRA adapter: ${entry.id}`);
  }
  logger.info(`LoRA adapter registered: ${entry.id}`);
}

/**
 * Get all LoRA adapters compatible with a specific model.
 *
 * Matches Swift: `RunAnywhere.loraAdaptersForModel(_:)`
 */
export async function loraAdaptersForModel(
  modelId: string
): Promise<LoraAdapterCatalogEntry[]> {
  if (!isNativeModuleAvailable()) {
    return [];
  }
  const native = getNative();
  if (!native.loraAdaptersForModel) {
    return [];
  }
  const json = await native.loraAdaptersForModel(modelId);
  return parseCatalogEntries(json);
}

/**
 * Get all registered LoRA adapters.
 *
 * Matches Swift: `RunAnywhere.allRegisteredLoraAdapters()`
 */
export async function allRegisteredLoraAdapters(): Promise<
  LoraAdapterCatalogEntry[]
> {
  if (!isNativeModuleAvailable()) {
    return [];
  }
  const native = getNative();
  if (!native.allRegisteredLoraAdapters) {
    return [];
  }
  const json = await native.allRegisteredLoraAdapters();
  return parseCatalogEntries(json);
}

function parseCatalogEntries(json: string): LoraAdapterCatalogEntry[] {
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr.map((entry: {
      id?: string;
      name?: string;
      description?: string;
      download_url?: string;
      downloadURL?: string;
      filename?: string;
      compatible_model_ids?: string[];
      compatibleModelIds?: string[];
      file_size?: number;
      fileSize?: number;
      default_scale?: number;
      defaultScale?: number;
    }) => ({
      id: entry.id ?? '',
      name: entry.name ?? '',
      description: entry.description ?? '',
      downloadURL: entry.download_url ?? entry.downloadURL ?? '',
      filename: entry.filename ?? '',
      compatibleModelIds:
        entry.compatible_model_ids ?? entry.compatibleModelIds ?? [],
      fileSize: entry.file_size ?? entry.fileSize ?? 0,
      defaultScale: entry.default_scale ?? entry.defaultScale ?? 1.0,
    }));
  } catch {
    return [];
  }
}
