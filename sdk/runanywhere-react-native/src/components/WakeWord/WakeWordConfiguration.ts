/**
 * WakeWordConfiguration.ts
 *
 * Configuration for Wake Word Detection component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/WakeWord/WakeWordComponent.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import type { ComponentInitParameters } from '../../Core/Models/Common/ComponentInitParameters';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * Configuration for Wake Word Detection component
 */
export interface WakeWordConfiguration extends ComponentConfiguration, ComponentInitParameters {
  readonly componentType: SDKComponent;
  readonly modelId: string | null;
  readonly wakeWords: string[];
  readonly sensitivity: number; // 0.0 to 1.0
  readonly bufferSize: number;
  readonly sampleRate: number;
  readonly confidenceThreshold: number; // 0.0 to 1.0
  readonly continuousListening: boolean;
}

/**
 * Create Wake Word configuration
 */
export class WakeWordConfigurationImpl implements WakeWordConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.WakeWord;
  public readonly modelId: string | null;
  public readonly wakeWords: string[];
  public readonly sensitivity: number;
  public readonly bufferSize: number;
  public readonly sampleRate: number;
  public readonly confidenceThreshold: number;
  public readonly continuousListening: boolean;

  constructor(options: {
    modelId?: string | null;
    wakeWords?: string[];
    sensitivity?: number;
    bufferSize?: number;
    sampleRate?: number;
    confidenceThreshold?: number;
    continuousListening?: boolean;
  } = {}) {
    this.modelId = options.modelId ?? null;
    this.wakeWords = options.wakeWords ?? ['Hey Siri', 'OK Google'];
    this.sensitivity = options.sensitivity ?? 0.5;
    this.bufferSize = options.bufferSize ?? 16000;
    this.sampleRate = options.sampleRate ?? 16000;
    this.confidenceThreshold = options.confidenceThreshold ?? 0.7;
    this.continuousListening = options.continuousListening ?? true;
  }

  public validate(): void {
    if (this.wakeWords.length === 0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'At least one wake word must be specified'
      );
    }
    if (this.sensitivity < 0 || this.sensitivity > 1) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Sensitivity must be between 0 and 1'
      );
    }
    if (this.confidenceThreshold < 0 || this.confidenceThreshold > 1) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Confidence threshold must be between 0 and 1'
      );
    }
  }
}

