// File: sdk/runanywhere-react-native/packages/core/src/Public/Extensions/RunAnywhere+Compatibility.ts

/**
 * RunAnywhere+Compatibility.ts
 *
 * Simple model compatibility checking for RunAnywhere SDK.
 * Checks if a model can run on the current device.
 */

import { requireDeviceInfoModule } from '../../native/NativeRunAnywhereCore';
import { Platform } from 'react-native';
import { ModelRegistry } from '../../services/ModelRegistry';
import { FileSystem } from '../../services';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
    ModelCompatibilityResult,
    DeviceCapabilities,
} from '../../types/CompatibilityTypes';
import type { ModelInfo } from '../../types';

const logger = new SDKLogger('RunAnywhere.Compatibility');

// ============================================================================
// Constants
// ============================================================================

/** Minimum RAM overhead required for app + OS (500 MB) */
const MIN_RAM_OVERHEAD_BYTES = 500 * 1024 * 1024;

/** Minimum storage overhead for temp files (100 MB) */
const MIN_STORAGE_OVERHEAD_BYTES = 100 * 1024 * 1024;

/** Memory multiplier for model loading (1.5x model size) */
const MEMORY_MULTIPLIER = 1.5;

/** Storage multiplier for extraction/temp files (1.2x download size) */
const STORAGE_MULTIPLIER = 1.2;

// ============================================================================
// Public API
// ============================================================================

/**
 * Check if a model is compatible with the current device
 *
 * @param modelIdOrInfo - Model ID or ModelInfo object
 * @returns Compatibility result with memory and storage checks
 *
 * @example
 * ```typescript
 * const result = await RunAnywhere.checkModelCompatibility('smollm2-360m-q8_0');
 *
 * if (result.isCompatible) {
 *   console.log('Model can run on this device');
 * } else {
 *   if (!result.canRun) {
 *     console.log('Not enough memory');
 *   }
 *   if (!result.canFit) {
 *     console.log('Not enough storage');
 *   }
 * }
 * ```
 */
export async function checkModelCompatibility(
    modelIdOrInfo: string | ModelInfo
): Promise<ModelCompatibilityResult> {
    logger.info('Checking model compatibility', {
        model: typeof modelIdOrInfo === 'string' ? modelIdOrInfo : modelIdOrInfo.id,
    });

    // Get model info
    const modelInfo =
        typeof modelIdOrInfo === 'string'
            ? await ModelRegistry.getModel(modelIdOrInfo)
            : modelIdOrInfo;

    if (!modelInfo) {
        throw new Error(
            `Model not found: ${typeof modelIdOrInfo === 'string' ? modelIdOrInfo : modelIdOrInfo.id}`
        );
    }

    // Get device capabilities
    const deviceCaps = await getDeviceCapabilities();

    // Perform compatibility check
    const result = performCompatibilityCheck(modelInfo, deviceCaps);

    logger.info('Compatibility check complete', {
        model: modelInfo.id,
        canRun: result.canRun,
        canFit: result.canFit,
        isCompatible: result.isCompatible,
    });

    return result;
}

/**
 * Get current device capabilities
 *
 * @returns Device capability information
 *
 * @example
 * ```typescript
 * const caps = await RunAnywhere.getDeviceCapabilities();
 * console.log(`Device: ${caps.deviceModel}`);
 * console.log(`RAM: ${(caps.availableMemory / 1e9).toFixed(1)} GB`);
 * console.log(`Storage: ${(caps.availableStorage / 1e9).toFixed(1)} GB`);
 * ```
 */
export async function getDeviceCapabilities(): Promise<DeviceCapabilities> {
    const deviceInfo = requireDeviceInfoModule();

    const [
        totalMemory,
        availableMemory,
        totalStorage,
        availableStorage,
        cpuCores,
        hasGPU,
        hasNPU,
        chipName,
        deviceModel,
    ] = await Promise.all([
        deviceInfo.getTotalRAM(),
        deviceInfo.getAvailableRAM(),
        FileSystem.getTotalDiskSpace(),
        FileSystem.getAvailableDiskSpace(),
        deviceInfo.getCPUCores(),
        deviceInfo.hasGPU(),
        deviceInfo.hasNPU(),
        deviceInfo.getChipName(),
        deviceInfo.getDeviceModel(),
    ]);

    return {
        totalMemory,
        availableMemory,
        totalStorage,
        availableStorage,
        cpuCores,
        hasGPU,
        hasNPU,
        chipName,
        deviceModel,
        platform: Platform.OS
    };
}

/**
 * Check multiple models for compatibility
 *
 * @param modelIds - Array of model IDs to check
 * @returns Map of model ID to compatibility result
 *
 * @example
 * ```typescript
 * const results = await RunAnywhere.checkModelsCompatibility([
 *   'smollm2-360m-q8_0',
 *   'qwen-2.5-0.5b-instruct-q8_0',
 * ]);
 *
 * for (const [modelId, result] of Object.entries(results)) {
 *   console.log(`${modelId}: ${result.isCompatible ? '✓' : '✗'}`);
 * }
 * ```
 */
export async function checkModelsCompatibility(
    modelIds: string[]
): Promise<Record<string, ModelCompatibilityResult>> {
    const results: Record<string, ModelCompatibilityResult> = {};

    // Get device capabilities once
    const deviceCaps = await getDeviceCapabilities();

    // Check each model
    for (const modelId of modelIds) {
        try {
            const modelInfo = await ModelRegistry.getModel(modelId);
            if (modelInfo) {
                results[modelId] = performCompatibilityCheck(modelInfo, deviceCaps);
            }
        } catch (error) {
            logger.warning(`Failed to check compatibility for ${modelId}`, { error });
        }
    }

    return results;
}

// ============================================================================
// Internal Implementation
// ============================================================================

/**
 * Perform the actual compatibility check logic
 */
function performCompatibilityCheck(
    model: ModelInfo,
    device: DeviceCapabilities
): ModelCompatibilityResult {
    // Calculate required resources
    const requiredMemory = calculateRequiredMemory(model);
    const requiredStorage = calculateRequiredStorage(model);

    // Check memory compatibility
    const canRun = device.availableMemory >= requiredMemory + MIN_RAM_OVERHEAD_BYTES;

    // Check storage compatibility
    const canFit =
        device.availableStorage >= requiredStorage + MIN_STORAGE_OVERHEAD_BYTES;

    // Overall compatibility
    const isCompatible = canRun && canFit;

    return {
        canRun,
        canFit,
        isCompatible,
        requiredMemory,
        availableMemory: device.availableMemory,
        requiredStorage,
        availableStorage: device.availableStorage,
    };
}

/**
 * Calculate required memory for a model (model size * multiplier)
 */
function calculateRequiredMemory(model: ModelInfo): number {
    // Use memoryRequired if available, otherwise estimate from download size
    const baseMemory = model.memoryRequired || model.downloadSize || 0;
    return Math.ceil(baseMemory * MEMORY_MULTIPLIER);
}

/**
 * Calculate required storage for a model (download size * multiplier)
 */
function calculateRequiredStorage(model: ModelInfo): number {
    const baseStorage = model.downloadSize || model.memoryRequired || 0;
    return Math.ceil(baseStorage * STORAGE_MULTIPLIER);
}
