/**
 * RunAnywhere DeviceInfo Nitrogen Spec
 *
 * Platform-specific device information.
 * Implemented in Kotlin (Android) and Swift (iOS).
 */
import type { HybridObject } from 'react-native-nitro-modules';

/**
 * Device information and capabilities
 *
 * This is implemented natively in Kotlin/Swift to access
 * platform-specific device APIs.
 */
export interface RunAnywhereDeviceInfo
  extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Get device model name (e.g., "iPhone 15 Pro", "Pixel 8")
   */
  getDeviceModel(): Promise<string>;

  /**
   * Get OS version (e.g., "17.0", "14")
   */
  getOSVersion(): Promise<string>;

  /**
   * Get platform name ("ios" or "android")
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
   * Check if device has GPU acceleration
   */
  hasGPU(): Promise<boolean>;

  /**
   * Check if device has Neural Engine / NPU
   */
  hasNPU(): Promise<boolean>;

  /**
   * Get chip name if available (e.g., "A17 Pro", "Tensor G3")
   */
  getChipName(): Promise<string>;

  /**
   * Get device thermal state (0 = nominal, 1 = fair, 2 = serious, 3 = critical)
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


