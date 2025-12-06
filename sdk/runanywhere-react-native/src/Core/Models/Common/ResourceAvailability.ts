/**
 * ResourceAvailability.ts
 *
 * Resource availability information
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Common/ResourceAvailability.swift
 */

import { HardwareAcceleration } from '../../../Capabilities/TextGeneration/Models/GenerationOptions';

// Placeholder for ThermalState - React Native equivalent
export enum ThermalState {
  Nominal = 'nominal',
  Fair = 'fair',
  Serious = 'serious',
  Critical = 'critical',
}

import type { ModelInfo } from '../Model/ModelInfo';

/**
 * Resource availability information
 */
export interface ResourceAvailability {
  /**
   * Available memory in bytes
   */
  readonly memoryAvailable: number;

  /**
   * Available storage in bytes
   */
  readonly storageAvailable: number;

  /**
   * Available hardware accelerators
   */
  readonly acceleratorsAvailable: HardwareAcceleration[];

  /**
   * Current thermal state
   */
  readonly thermalState: ThermalState;

  /**
   * Battery level (0.0 to 1.0) or null if not available
   */
  readonly batteryLevel: number | null;

  /**
   * Whether device is in low power mode
   */
  readonly isLowPowerMode: boolean;

  /**
   * Check if a model can be loaded
   */
  canLoadModel(model: ModelInfo): boolean;
}

/**
 * Check if a model can be loaded with the given resource availability
 */
export function canLoadModel(
  availability: ResourceAvailability,
  model: ModelInfo
): { canLoad: boolean; reason: string | null } {
  // Check memory
  const memoryNeeded = model.memoryRequired ?? 0;
  if (memoryNeeded > availability.memoryAvailable) {
    const neededMB = (memoryNeeded / (1024 * 1024)).toFixed(2);
    const availableMB = (availability.memoryAvailable / (1024 * 1024)).toFixed(2);
    return {
      canLoad: false,
      reason: `Insufficient memory: need ${neededMB}MB, have ${availableMB}MB`,
    };
  }

  // Check storage
  if (model.downloadSize && model.downloadSize > availability.storageAvailable) {
    const neededMB = (model.downloadSize / (1024 * 1024)).toFixed(2);
    const availableMB = (availability.storageAvailable / (1024 * 1024)).toFixed(2);
    return {
      canLoad: false,
      reason: `Insufficient storage: need ${neededMB}MB, have ${availableMB}MB`,
    };
  }

  // Check thermal state
  if (availability.thermalState === ThermalState.Critical) {
    return {
      canLoad: false,
      reason: 'Device is too hot, please wait for it to cool down',
    };
  }

  // Check battery in low power mode
  if (
    availability.isLowPowerMode &&
    availability.batteryLevel !== null &&
    availability.batteryLevel < 0.2
  ) {
    return {
      canLoad: false,
      reason: 'Battery too low for model loading in Low Power Mode',
    };
  }

  return { canLoad: true, reason: null };
}

