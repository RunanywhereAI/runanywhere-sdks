/**
 * Model compatibility check result
 * Simplified - just performs essential checks
 */
export interface ModelCompatibilityResult {
    /** Whether enough RAM is available to run model */
    canRun: boolean;

    /** Whether enough storage is available to run model */
    canFit: boolean;

    /** Overall compatibility (canRun && canFit) */
    isCompatible: boolean;

    /** Required RAM in bytes */
    requiredMemory: number;

    /** Available RAM in bytes */
    availableMemory: number;

    /** Required storage in bytes */
    requiredStorage: number;

    /** Available storage in bytes */
    availableStorage: number;
}

/**
 * Device capability information
 */
export interface DeviceCapabilities {
    /** Total device RAM in bytes */
    totalMemory: number;

    /** Available device RAM in bytes */
    availableMemory: number;

    /** Total device storage in bytes */
    totalStorage: number;

    /** Available device storage in bytes */
    availableStorage: number;

    /** Number of CPU cores */
    cpuCores: number;

    /** Whether device has GPU */
    hasGPU: boolean;

    /** Whether device has NPU */
    hasNPU: boolean;

    /** Chip/processor name */
    chipName: string;

    /** Device model name */
    deviceModel: string;

    /** Device Platform */
    platform: 'ios' | 'android';
}