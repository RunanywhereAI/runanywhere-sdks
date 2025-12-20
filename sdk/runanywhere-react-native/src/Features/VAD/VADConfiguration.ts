/**
 * VADConfiguration.ts
 *
 * Configuration for VAD component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/VAD/VADComponent.swift
 */

import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * Configuration for VAD component
 * Reference: VADConfiguration in VADComponent.swift
 */
export interface VADConfiguration extends ComponentConfiguration {
  /** Component type */
  readonly componentType: SDKComponent;

  /** Model ID (optional for VAD) */
  readonly modelId: string | null;

  /** Energy threshold for voice detection (0.0 to 1.0) */
  energyThreshold: number;

  /** Sample rate in Hz */
  sampleRate: number;

  /** Frame length in seconds */
  frameLength: number;

  /** Enable automatic calibration */
  enableAutoCalibration: boolean;

  /** Calibration multiplier (threshold = ambient noise * multiplier) */
  calibrationMultiplier: number;
}

/**
 * Default VAD configuration
 * Matches Swift SDK defaults
 */
export const DEFAULT_VAD_CONFIG: Omit<VADConfiguration, 'validate'> = {
  componentType: SDKComponent.VAD,
  modelId: null,
  energyThreshold: 0.015,
  sampleRate: 16000,
  frameLength: 0.1,
  enableAutoCalibration: false,
  calibrationMultiplier: 1.5,
};

/**
 * Create VAD configuration
 */
export class VADConfigurationImpl implements VADConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.VAD;
  public readonly modelId: string | null = null;
  public energyThreshold: number;
  public sampleRate: number;
  public frameLength: number;
  public enableAutoCalibration: boolean;
  public calibrationMultiplier: number;

  constructor(
    options: Partial<
      Omit<VADConfiguration, 'validate' | 'componentType' | 'modelId'>
    > = {}
  ) {
    this.energyThreshold =
      options.energyThreshold ?? DEFAULT_VAD_CONFIG.energyThreshold;
    this.sampleRate = options.sampleRate ?? DEFAULT_VAD_CONFIG.sampleRate;
    this.frameLength = options.frameLength ?? DEFAULT_VAD_CONFIG.frameLength;
    this.enableAutoCalibration =
      options.enableAutoCalibration ?? DEFAULT_VAD_CONFIG.enableAutoCalibration;
    this.calibrationMultiplier =
      options.calibrationMultiplier ?? DEFAULT_VAD_CONFIG.calibrationMultiplier;
  }

  public validate(): void {
    if (this.energyThreshold < 0 || this.energyThreshold > 1) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Energy threshold must be between 0.0 and 1.0'
      );
    }
    if (this.sampleRate <= 0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Sample rate must be positive'
      );
    }
    if (this.frameLength <= 0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Frame length must be positive'
      );
    }
    if (this.calibrationMultiplier <= 0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Calibration multiplier must be positive'
      );
    }
  }
}
