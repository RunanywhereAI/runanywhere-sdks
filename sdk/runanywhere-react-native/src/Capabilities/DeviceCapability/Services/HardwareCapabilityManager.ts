/**
 * HardwareCapabilityManager.ts
 *
 * Hardware capability manager using react-native-device-info package.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/DeviceCapability/Services/HardwareDetectionService.swift
 */

import { Platform } from 'react-native';
import type { DeviceCapabilities } from '../Models/DeviceCapabilities';
import {
  DeviceCapabilitiesImpl,
  ProcessorType,
} from '../Models/DeviceCapabilities';
import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';
import type { ResourceAvailability } from '../../../Core/Models/Common/ResourceAvailability';
import { ThermalState } from '../../../Core/Models/Common/ResourceAvailability';
import { HardwareAcceleration } from '../../TextGeneration/Models/GenerationOptions';
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';

// Dynamic import for optional peer dependency
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let DeviceInfo: any = null;

try {
  DeviceInfo = require('react-native-device-info');
} catch {
  // Package not installed
}

const logger = new SDKLogger('HardwareCapabilityManager');

/**
 * Hardware capability manager using react-native-device-info.
 *
 * This class uses react-native-device-info, a well-maintained community package
 * that provides comprehensive device information for both iOS and Android.
 */
export class HardwareCapabilityManager {
  private static sharedInstance: HardwareCapabilityManager | null = null;
  private cachedCapabilities: DeviceCapabilities | null = null;
  private cacheTimestamp: Date | null = null;
  private readonly cacheValidityDuration: number = 60 * 1000; // 1 minute in ms
  private _deviceIdentifier: string | null = null;

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
   * Check if device info package is available
   */
  public isAvailable(): boolean {
    return DeviceInfo !== null;
  }

  /**
   * Device identifier for compilation cache (synchronous)
   */
  public get deviceIdentifier(): string {
    return this._deviceIdentifier ?? 'Unknown-ReactNative';
  }

  /**
   * Fetch device identifier asynchronously
   */
  public async fetchDeviceIdentifier(): Promise<string> {
    if (this._deviceIdentifier) {
      return this._deviceIdentifier;
    }

    try {
      if (DeviceInfo) {
        const [model, brand, deviceId] = await Promise.all([
          DeviceInfo.getModel(),
          DeviceInfo.getBrand(),
          DeviceInfo.getDeviceId(),
        ]);
        this._deviceIdentifier =
          `${Platform.OS}-${brand}-${model}-${deviceId}`.replace(/\s+/g, '_');
      } else {
        this._deviceIdentifier = `${Platform.OS}-Unknown`;
      }
      return this._deviceIdentifier;
    } catch (error) {
      logger.warning('Failed to fetch device identifier', { error });
      return 'Unknown-ReactNative';
    }
  }

  private constructor() {
    // Initialize device identifier asynchronously
    this.fetchDeviceIdentifier().catch(() => {
      // Ignore initialization errors
    });
  }

  /**
   * Get current device capabilities (sync, uses cached values)
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

    // Return defaults and trigger async refresh
    this.refreshCapabilitiesAsync();

    // Return default values synchronously
    if (!this.cachedCapabilities) {
      this.cachedCapabilities = this.getDefaultCapabilities();
    }

    return this.cachedCapabilities;
  }

  /**
   * Fetch capabilities asynchronously from react-native-device-info
   */
  public async fetchCapabilities(): Promise<DeviceCapabilities> {
    if (!DeviceInfo) {
      logger.warning('react-native-device-info not installed, using defaults');
      return this.getDefaultCapabilities();
    }

    try {
      const [
        totalMemory,
        usedMemory,
        model,
        deviceId,
        systemVersion,
        brand,
        isEmulator,
        supportedAbis,
      ] = await Promise.all([
        DeviceInfo.getTotalMemory(),
        DeviceInfo.getUsedMemory(),
        DeviceInfo.getModel(),
        DeviceInfo.getDeviceId(),
        DeviceInfo.getSystemVersion(),
        DeviceInfo.getBrand(),
        DeviceInfo.isEmulator(),
        DeviceInfo.supportedAbis(),
      ]);

      // Calculate available memory
      const availableMemory = totalMemory - usedMemory;

      // Parse OS version
      const versionParts = systemVersion.split('.');
      const majorVersion = parseInt(versionParts[0] ?? '0', 10);
      const minorVersion = parseInt(versionParts[1] ?? '0', 10);
      const patchVersion = parseInt(versionParts[2] ?? '0', 10);

      // Detect processor type
      const processorType = this.detectProcessorType(deviceId, supportedAbis);

      // Detect GPU/NPU support
      const hasGPU = !isEmulator; // Assume real devices have GPU
      const hasNPU = this.detectNPU(deviceId, model, majorVersion);

      // Build accelerators list
      const supportedAccelerators: HardwareAcceleration[] = [
        HardwareAcceleration.CPU,
      ];
      if (hasGPU) {
        supportedAccelerators.push(HardwareAcceleration.GPU);
      }
      if (hasNPU) {
        supportedAccelerators.push(HardwareAcceleration.NeuralEngine);
      }

      // Get CPU cores (sync method)
      const processorCount =
        DeviceInfo.getSupportedAbisSync().length > 0
          ? Math.max(2, navigator?.hardwareConcurrency ?? 4)
          : 4;

      const capabilities = new DeviceCapabilitiesImpl({
        totalMemory,
        availableMemory,
        hasNeuralEngine: hasNPU,
        hasGPU,
        processorCount,
        processorType,
        supportedAccelerators,
        osVersion: {
          majorVersion,
          minorVersion,
          patchVersion,
        },
        modelIdentifier: `${brand} ${model} (${deviceId})`,
      });

      // Update cache
      this.cachedCapabilities = capabilities;
      this.cacheTimestamp = new Date();

      return capabilities;
    } catch (error) {
      logger.warning('Failed to fetch device capabilities', { error });
      return this.getDefaultCapabilities();
    }
  }

  /**
   * Get optimal hardware configuration for a model
   */
  public async optimalConfiguration(
    _model: ModelInfo
  ): Promise<{ acceleration: HardwareAcceleration }> {
    const capabilities = await this.fetchCapabilities();

    // Prefer NPU/NeuralEngine for compatible models
    if (
      capabilities.hasNeuralEngine &&
      capabilities.supportedAccelerators.includes(
        HardwareAcceleration.NeuralEngine
      )
    ) {
      return { acceleration: HardwareAcceleration.NeuralEngine };
    }

    // Fallback to GPU if available
    if (
      capabilities.hasGPU &&
      capabilities.supportedAccelerators.includes(HardwareAcceleration.GPU)
    ) {
      return { acceleration: HardwareAcceleration.GPU };
    }

    // Use CPU as fallback
    return { acceleration: HardwareAcceleration.CPU };
  }

  /**
   * Check resource availability asynchronously
   */
  public async checkResourceAvailabilityAsync(): Promise<ResourceAvailability> {
    const capabilities = await this.fetchCapabilities();

    let storageAvailable = 0;
    let batteryLevel: number | null = null;
    let isLowPowerMode = false;
    const thermalState = ThermalState.Nominal;

    if (DeviceInfo) {
      try {
        const [freeDisk, battery, powerMode] = await Promise.all([
          DeviceInfo.getFreeDiskStorage(),
          DeviceInfo.getBatteryLevel(),
          DeviceInfo.getPowerState(),
        ]);

        storageAvailable = freeDisk;
        batteryLevel = battery >= 0 ? battery : null;
        isLowPowerMode = powerMode?.lowPowerMode ?? false;

        // Estimate thermal state from battery temperature if available
        // (react-native-device-info doesn't provide thermal state directly)
      } catch (error) {
        logger.warning('Failed to get resource availability', { error });
      }
    }

    return {
      memoryAvailable: capabilities.availableMemory,
      storageAvailable,
      acceleratorsAvailable: capabilities.supportedAccelerators,
      thermalState,
      batteryLevel,
      isLowPowerMode,
      canLoadModel: (model: ModelInfo) => {
        return capabilities.canRun(model);
      },
    };
  }

  /**
   * Check resource availability (sync, uses cached values)
   */
  public checkResourceAvailability(): ResourceAvailability {
    const capabilities = this.capabilities;

    return {
      memoryAvailable: capabilities.availableMemory,
      storageAvailable: 0,
      acceleratorsAvailable: capabilities.supportedAccelerators,
      thermalState: ThermalState.Nominal,
      batteryLevel: null,
      isLowPowerMode: false,
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
   * Refresh capabilities asynchronously and update cache
   */
  private async refreshCapabilitiesAsync(): Promise<void> {
    try {
      await this.fetchCapabilities();
    } catch (error) {
      logger.warning('Failed to refresh capabilities', { error });
    }
  }

  /**
   * Get default capabilities when package is unavailable
   */
  private getDefaultCapabilities(): DeviceCapabilities {
    return new DeviceCapabilitiesImpl({
      totalMemory: 4_000_000_000, // 4GB default
      availableMemory: 2_000_000_000, // 2GB default
      hasNeuralEngine: Platform.OS === 'ios', // iOS devices likely have ANE
      hasGPU: true,
      processorCount: 4,
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

  /**
   * Detect processor type from device ID and ABIs
   */
  private detectProcessorType(
    deviceId: string,
    supportedAbis: string[]
  ): ProcessorType {
    const device = deviceId.toLowerCase();

    if (Platform.OS === 'ios') {
      // A-series chips
      if (device.includes('iphone16') || device.includes('ipad15')) {
        return ProcessorType.A18Pro;
      }
      if (device.includes('iphone15') || device.includes('ipad14')) {
        return ProcessorType.A17Pro;
      }
      if (device.includes('iphone14') || device.includes('ipad13')) {
        return ProcessorType.A16Bionic;
      }
      if (device.includes('iphone13') || device.includes('ipad12')) {
        return ProcessorType.A15Bionic;
      }
      if (device.includes('iphone12') || device.includes('ipad11')) {
        return ProcessorType.A14Bionic;
      }

      // M-series (iPad Pro, Mac)
      if (device.includes('mac') || device.includes('ipad14')) {
        return ProcessorType.M2;
      }
    }

    if (Platform.OS === 'android') {
      // Check ABIs for ARM architecture
      const abiStr = supportedAbis.join(',').toLowerCase();
      if (abiStr.includes('arm64') || abiStr.includes('armeabi')) {
        return ProcessorType.Arm;
      }
      if (abiStr.includes('x86')) {
        return ProcessorType.Intel;
      }
    }

    return ProcessorType.Unknown;
  }

  /**
   * Detect if device has NPU/Neural Engine
   */
  private detectNPU(
    deviceId: string,
    model: string,
    osMajorVersion: number
  ): boolean {
    if (Platform.OS === 'ios') {
      // iOS 11+ with A11 Bionic or later has Neural Engine
      // iPhone X and later, iPad Pro (3rd gen) and later
      if (osMajorVersion >= 11) {
        const device = deviceId.toLowerCase();
        // iPhone 8/X and later (iPhone10,x and higher)
        if (device.includes('iphone')) {
          const match = device.match(/iphone(\d+)/);
          if (match && parseInt(match[1] ?? '0', 10) >= 10) {
            return true;
          }
        }
        // iPad Pro 3rd gen and later
        if (device.includes('ipad')) {
          const match = device.match(/ipad(\d+)/);
          if (match && parseInt(match[1] ?? '0', 10) >= 8) {
            return true;
          }
        }
      }
      return false;
    }

    if (Platform.OS === 'android') {
      // Check for known NPU-capable chips
      const deviceLower = (model + deviceId).toLowerCase();
      return (
        deviceLower.includes('snapdragon') ||
        deviceLower.includes('exynos') ||
        deviceLower.includes('tensor') ||
        deviceLower.includes('dimensity') ||
        deviceLower.includes('kirin')
      );
    }

    return false;
  }
}
