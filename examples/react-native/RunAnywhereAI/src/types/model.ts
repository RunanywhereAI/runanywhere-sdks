/**
 * Device info for model selection
 */
export interface DeviceInfo {
  /** Device model name */
  modelName: string;

  /** Chip name */
  chipName: string;

  /** Total memory in bytes */
  totalMemory: number;

  /** Available memory in bytes */
  availableMemory: number;

  /** Whether device has Neural Engine / NPU */
  hasNeuralEngine: boolean;

  /** OS version */
  osVersion: string;

  /** Whether device has GPU */
  hasGPU?: boolean;

  /** Number of CPU cores */
  cpuCores?: number;
}
