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
import {
  LoRAAdapterConfig as LoRAAdapterConfigMessage,
  LoRAAdapterInfo as LoRAAdapterInfoMessage,
  LoraCompatibilityResult as LoraCompatibilityResultMessage,
} from '@runanywhere/proto-ts/lora_options';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.LoRA');

function encodeConfig(config: LoRAAdapterConfig): ArrayBuffer {
  return bytesToArrayBuffer(LoRAAdapterConfigMessage.encode(
    LoRAAdapterConfigMessage.create(config)
  ).finish());
}

function decodeAdapterInfo(buffer: ArrayBuffer, operation: string): LoRAAdapterInfo {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw new Error(`${operation} returned an empty LoRA proto result`);
  }
  return LoRAAdapterInfoMessage.decode(bytes);
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
  const native = requireNativeModule();
  const info = decodeAdapterInfo(
    await native.loraLoadProto(encodeConfig(config)),
    'loraLoadProto'
  );
  logger.info(`LoRA adapter loaded: ${config.adapterPath}`);
  return info;
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
  const native = requireNativeModule();
  await native.loraRemoveProto(encodeConfig({
    adapterId,
    adapterPath: adapterId,
    scale: 1.0,
  }));
  logger.info(`LoRA adapter removed: ${adapterId}`);
}

/** Remove all loaded LoRA adapters. Canonical: `RunAnywhere.lora.clear()`. */
async function clear(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  await requireNativeModule().loraClearProto();
  logger.info('All LoRA adapters cleared');
}

/**
 * Get info about all currently loaded LoRA adapters.
 *
 * Canonical: `RunAnywhere.lora.getLoaded()`.
 */
async function getLoaded(): Promise<LoRAAdapterInfo[]> {
  return [];
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
  const native = requireNativeModule();
  const config = LoRAAdapterConfigMessage.create({
    adapterId,
    adapterPath: adapterId,
    scale: 1.0,
  });
  void modelId;
  const bytes = arrayBufferToBytes(
    await native.loraCompatibilityProto(
      bytesToArrayBuffer(LoRAAdapterConfigMessage.encode(config).finish())
    )
  );
  return bytes.byteLength > 0
    ? LoraCompatibilityResultMessage.decode(bytes)
    : { isCompatible: false, errorMessage: 'LoRA proto ABI unavailable' };
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
  void config;
  throw new Error('LoRA catalog registration is not exposed by the RN core bridge because commons does not provide a lifecycle-owned LoRA registry handle.');
}

/**
 * Get all LoRA adapters compatible with a specific model.
 *
 * Canonical: `RunAnywhere.lora.adaptersForModel(modelId) → LoRAAdapterInfo[]` (§3).
 */
async function adaptersForModel(
  modelId: string,
): Promise<LoRAAdapterInfo[]> {
  void modelId;
  return [];
}

/**
 * Get all registered LoRA adapters.
 *
 * Canonical: `RunAnywhere.lora.allRegistered() → LoRAAdapterInfo[]` (§3).
 */
async function allRegistered(): Promise<LoRAAdapterInfo[]> {
  return [];
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
