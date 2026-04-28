/**
 * RunAnywhere+LoRA.ts
 *
 * Public API for LoRA adapter management. Wave 2: aligned to
 * proto-canonical LoRA shapes (`@runanywhere/proto-ts/lora_options`).
 *
 * Matches Swift: `Public/Extensions/LLM/RunAnywhere+LoRA.swift`.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoraAdapterCatalogEntry,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

const logger = new SDKLogger('RunAnywhere.LoRA');

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
 *
 * Matches Swift: `RunAnywhere.loadLoraAdapter(_:)`.
 */
export async function loadLoraAdapter(
  config: LoRAAdapterConfig
): Promise<void> {
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
}

/**
 * Remove a specific LoRA adapter by path.
 *
 * Matches Swift: `RunAnywhere.removeLoraAdapter(_:)`.
 */
export async function removeLoraAdapter(path: string): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = getNative();
  if (!native.removeLoraAdapter) {
    throw new Error(
      'LoRA adapter removal is not supported by the current LLM backend'
    );
  }
  const ok = await native.removeLoraAdapter(path);
  if (!ok) {
    throw new Error(`Failed to remove LoRA adapter: ${path}`);
  }
  logger.info(`LoRA adapter removed: ${path}`);
}

/** Remove all loaded LoRA adapters. */
export async function clearLoraAdapters(): Promise<void> {
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

/** Get info about all currently loaded LoRA adapters. */
export async function getLoadedLoraAdapters(): Promise<LoRAAdapterInfo[]> {
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
 * Check LoRA adapter compatibility with the currently loaded model.
 *
 * Matches Swift: `RunAnywhere.checkLoraCompatibility(loraPath:)`.
 */
export async function checkLoraCompatibility(
  loraPath: string
): Promise<LoraCompatibilityResult> {
  if (!isNativeModuleAvailable()) {
    return { isCompatible: false, errorMessage: 'SDK not initialized' };
  }
  const native = getNative();
  if (!native.checkLoraCompatibility) {
    return { isCompatible: false, errorMessage: 'LoRA support not available' };
  }
  const json = await native.checkLoraCompatibility(loraPath);
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
 * Register a LoRA adapter in the SDK catalog at app startup.
 *
 * Matches Swift: `RunAnywhere.registerLoraAdapter(_:)`.
 */
export async function registerLoraAdapter(
  entry: LoraAdapterCatalogEntry
): Promise<void> {
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
    id: entry.id,
    name: entry.name,
    description: entry.description,
    url: entry.url,
    filename: entry.filename,
    compatible_models: entry.compatibleModels,
    size_bytes: entry.sizeBytes ?? 0,
    author: entry.author,
  });
  const ok = await native.registerLoraAdapter(entryJson);
  if (!ok) {
    throw new Error(`Failed to register LoRA adapter: ${entry.id}`);
  }
  logger.info(`LoRA adapter registered: ${entry.id}`);
}

/** Get all LoRA adapters compatible with a specific model. */
export async function loraAdaptersForModel(
  modelId: string
): Promise<LoraAdapterCatalogEntry[]> {
  if (!isNativeModuleAvailable()) return [];
  const native = getNative();
  if (!native.loraAdaptersForModel) return [];
  const json = await native.loraAdaptersForModel(modelId);
  return parseCatalogEntries(json);
}

/** Get all registered LoRA adapters. */
export async function allRegisteredLoraAdapters(): Promise<
  LoraAdapterCatalogEntry[]
> {
  if (!isNativeModuleAvailable()) return [];
  const native = getNative();
  if (!native.allRegisteredLoraAdapters) return [];
  const json = await native.allRegisteredLoraAdapters();
  return parseCatalogEntries(json);
}

function parseCatalogEntries(json: string): LoraAdapterCatalogEntry[] {
  try {
    const arr = JSON.parse(json);
    if (!Array.isArray(arr)) return [];
    return arr.map(
      (entry: {
        id?: string;
        name?: string;
        description?: string;
        url?: string;
        download_url?: string;
        downloadURL?: string;
        filename?: string;
        compatible_models?: string[];
        compatibleModels?: string[];
        compatible_model_ids?: string[];
        compatibleModelIds?: string[];
        size_bytes?: number;
        sizeBytes?: number;
        file_size?: number;
        fileSize?: number;
        author?: string;
      }): LoraAdapterCatalogEntry => ({
        id: entry.id ?? '',
        name: entry.name ?? '',
        description: entry.description ?? '',
        url: entry.url ?? entry.download_url ?? entry.downloadURL ?? '',
        filename: entry.filename ?? '',
        compatibleModels:
          entry.compatible_models ??
          entry.compatibleModels ??
          entry.compatible_model_ids ??
          entry.compatibleModelIds ??
          [],
        sizeBytes:
          entry.size_bytes ??
          entry.sizeBytes ??
          entry.file_size ??
          entry.fileSize ??
          0,
        author: entry.author,
      })
    );
  } catch {
    return [];
  }
}
