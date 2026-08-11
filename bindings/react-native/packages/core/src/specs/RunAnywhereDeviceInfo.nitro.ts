import { type HybridObject } from 'react-native-nitro-modules';

/**
 * Device information interface for RunAnywhere SDK.
 * Provides device capabilities, memory info, and battery status.
 */
export interface RunAnywhereDeviceInfo
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Get device model name
   */
  getDeviceModel(): Promise<string>;

  /**
   * Get OS version
   */
  getOSVersion(): Promise<string>;

  /**
   * Get platform name (ios/android)
   */
  getPlatform(): Promise<string>;

  /**
   * Get total RAM in bytes
   */
  getTotalRAM(): Promise<number>;

  /**
   * Get available RAM in bytes
   */
  getAvailableRAM(): Promise<number>;

  /**
   * Get number of CPU cores
   */
  getCPUCores(): Promise<number>;

  /**
   * Check if device has GPU
   */
  hasGPU(): Promise<boolean>;

  /**
   * Check if device has NPU (Neural Processing Unit)
   */
  hasNPU(): Promise<boolean>;

  /**
   * Get chip/processor name
   */
  getChipName(): Promise<string>;

  /**
   * Get thermal state (0=nominal, 1=fair, 2=serious, 3=critical)
   */
  getThermalState(): Promise<number>;

  /**
   * Get battery level (0.0 to 1.0)
   */
  getBatteryLevel(): Promise<number>;

  /**
   * Check if device is charging
   */
  isCharging(): Promise<boolean>;

  /**
   * Check if low power mode is enabled
   */
  isLowPowerMode(): Promise<boolean>;
}
