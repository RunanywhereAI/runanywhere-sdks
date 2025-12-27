/**
 * DeviceCapabilities.ts
 *
 * Device hardware capabilities information
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Capabilities/DeviceCapability/Models/DeviceCapabilities.swift
 */

import { MemoryPressureLevel } from '../../../Core/Protocols/Memory/MemoryModels';
import { HardwareAcceleration } from '../../TextGeneration/Models/GenerationOptions';
import type { ModelInfo } from '../../../Core/Models/Model/ModelInfo';

/**
 * Processor type enumeration
 */
export enum ProcessorType {
  A14Bionic = 'a14Bionic',
  A15Bionic = 'a15Bionic',
  A16Bionic = 'a16Bionic',
  A17Pro = 'a17Pro',
  A18 = 'a18',
  A18Pro = 'a18Pro',
  M1 = 'm1',
  M1Pro = 'm1Pro',
  M1Max = 'm1Max',
  M1Ultra = 'm1Ultra',
  M2 = 'm2',
  M2Pro = 'm2Pro',
  M2Max = 'm2Max',
  M2Ultra = 'm2Ultra',
  M3 = 'm3',
  M3Pro = 'm3Pro',
  M3Max = 'm3Max',
  M4 = 'm4',
  M4Pro = 'm4Pro',
  M4Max = 'm4Max',
  Intel = 'intel',
  Arm = 'arm',
  Unknown = 'unknown',
}

/**
 * Operating system version
 */
export interface OperatingSystemVersion {
  readonly majorVersion: number;
  readonly minorVersion: number;
  readonly patchVersion: number;
}

/**
 * Complete device hardware capabilities
 */
export interface DeviceCapabilities {
  readonly totalMemory: number; // Int64
  readonly availableMemory: number; // Int64
  readonly hasNeuralEngine: boolean;
  readonly hasGPU: boolean;
  readonly processorCount: number;
  readonly processorType: ProcessorType;
  readonly supportedAccelerators: HardwareAcceleration[];
  readonly osVersion: OperatingSystemVersion;
  readonly modelIdentifier: string;

  readonly memoryPressureLevel: MemoryPressureLevel;
  canRun(model: ModelInfo): boolean;
}

/**
 * Create device capabilities
 */
export class DeviceCapabilitiesImpl implements DeviceCapabilities {
  public readonly totalMemory: number;
  public readonly availableMemory: number;
  public readonly hasNeuralEngine: boolean;
  public readonly hasGPU: boolean;
  public readonly processorCount: number;
  public readonly processorType: ProcessorType;
  public readonly supportedAccelerators: HardwareAcceleration[];
  public readonly osVersion: OperatingSystemVersion;
  public readonly modelIdentifier: string;

  constructor(options: {
    totalMemory: number;
    availableMemory: number;
    hasNeuralEngine?: boolean;
    hasGPU?: boolean;
    processorCount: number;
    processorType?: ProcessorType;
    supportedAccelerators?: HardwareAcceleration[];
    osVersion: OperatingSystemVersion;
    modelIdentifier?: string;
  }) {
    this.totalMemory = options.totalMemory;
    this.availableMemory = options.availableMemory;
    this.hasNeuralEngine = options.hasNeuralEngine ?? false;
    this.hasGPU = options.hasGPU ?? false;
    this.processorCount = options.processorCount;
    this.processorType = options.processorType ?? ProcessorType.Unknown;
    this.supportedAccelerators = options.supportedAccelerators ?? [
      HardwareAcceleration.CPU,
    ];
    this.osVersion = options.osVersion;
    this.modelIdentifier = options.modelIdentifier ?? 'Unknown';
  }

  /**
   * Memory pressure level based on available memory
   */
  public get memoryPressureLevel(): MemoryPressureLevel {
    const ratio = this.availableMemory / this.totalMemory;

    if (ratio < 0.1) {
      return MemoryPressureLevel.Critical;
    } else if (ratio < 0.15) {
      return MemoryPressureLevel.Warning;
    } else if (ratio < 0.2) {
      return MemoryPressureLevel.High;
    } else if (ratio < 0.4) {
      return MemoryPressureLevel.Medium;
    } else {
      return MemoryPressureLevel.Low;
    }
  }

  /**
   * Whether the device has sufficient resources for a given model
   */
  public canRun(model: ModelInfo): boolean {
    return this.availableMemory >= (model.memoryRequired ?? 0);
  }
}
