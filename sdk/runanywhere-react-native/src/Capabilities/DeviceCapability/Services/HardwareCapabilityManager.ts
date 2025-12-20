/**
 * HardwareCapabilityManager.ts
 *
 * Hardware capability manager
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/DeviceCapability/Services/HardwareDetectionService.swift
 */

import type { DeviceCapabilities } from '../Models/DeviceCapabilities';
import {
  DeviceCapabilitiesImpl,
  ProcessorType,
} from '../Models/DeviceCapabilities';
import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';
import type { ResourceAvailability } from '../../../Core/Models/Common/ResourceAvailability';
import { ThermalState } from '../../../Core/Models/Common/ResourceAvailability';
import { HardwareAcceleration } from '../../TextGeneration/Models/GenerationOptions';

/**
 * Capability analyzer interface for future extension
 */
interface CapabilityAnalyzer {
  analyze(): unknown;
}

/**
 * Hardware capability manager
 */
export class HardwareCapabilityManager {
  private static sharedInstance: HardwareCapabilityManager | null = null;
  private _capabilityAnalyzer: CapabilityAnalyzer | null = null;
  private cachedCapabilities: DeviceCapabilities | null = null;
  private cacheTimestamp: Date | null = null;
  private readonly cacheValidityDuration: number = 60 * 1000; // 1 minute in ms

  /**
   * Get shared instance
   */
  public static get shared(): HardwareCapabilityManager {
    if (!HardwareCapabilityManager.sharedInstance) {
      HardwareCapabilityManager.sharedInstance =
        new HardwareCapabilityManager();
    }
    return HardwareCapabilityManager.sharedInstance;
  }

  /**
   * Device identifier for compilation cache
   */
  public get deviceIdentifier(): string {
    // In React Native, this would need native module support
    return 'Unknown-' + 'ReactNative';
  }

  private constructor() {
    // Initialize capability analyzer
    // this.capabilityAnalyzer = new CapabilityAnalyzer();
  }

  /**
   * Get current device capabilities
   */
  public get capabilities(): DeviceCapabilities {
    // Fast path: check cache
    if (
      this.cachedCapabilities &&
      this.cacheTimestamp &&
      Date.now() - this.cacheTimestamp.getTime() < this.cacheValidityDuration
    ) {
      return this.cachedCapabilities;
    }

    // Compute capabilities
    const computed = this.computeCapabilities();

    // Update cache
    this.cachedCapabilities = computed;
    this.cacheTimestamp = new Date();

    return computed;
  }

  /**
   * Get optimal hardware configuration for a model
   */
  public optimalConfiguration(_model: ModelInfo): unknown {
    // Placeholder - would use capabilityAnalyzer
    return {};
  }

  /**
   * Check resource availability
   */
  public checkResourceAvailability(): ResourceAvailability {
    const capabilities = this.capabilities;

    // Placeholder values - would need native module support
    const storageAvailable = 0;
    const accelerators = capabilities.supportedAccelerators;
    const thermalState = ThermalState.Nominal;
    const batteryLevel = null;
    const isLowPowerMode = false;

    return {
      memoryAvailable: capabilities.availableMemory,
      storageAvailable,
      acceleratorsAvailable: accelerators,
      thermalState,
      batteryLevel,
      isLowPowerMode,
      canLoadModel: (model: ModelInfo) => {
        return capabilities.canRun(model);
      },
    };
  }

  /**
   * Refresh cached capabilities
   */
  public refreshCapabilities(): void {
    this.cachedCapabilities = null;
    this.cacheTimestamp = null;
  }

  /**
   * Compute capabilities
   */
  private computeCapabilities(): DeviceCapabilities {
    // Placeholder implementation - would use native modules in production
    return new DeviceCapabilitiesImpl({
      totalMemory: 4_000_000_000, // 4GB
      availableMemory: 2_000_000_000, // 2GB
      hasNeuralEngine: false, // Would detect via native module
      hasGPU: true, // Assume true for modern devices
      processorCount: 4, // Placeholder
      processorType: ProcessorType.Unknown,
      supportedAccelerators: [
        HardwareAcceleration.CPU,
        HardwareAcceleration.GPU,
      ],
      osVersion: {
        majorVersion: 0,
        minorVersion: 0,
        patchVersion: 0,
      },
      modelIdentifier: 'Unknown',
    });
  }
}
