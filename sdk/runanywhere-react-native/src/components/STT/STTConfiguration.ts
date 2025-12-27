/**
 * STTConfiguration.ts
 *
 * Configuration for STT component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import type { ComponentInitParameters } from '../../Core/Models/Common/ComponentInitParameters';
import { SDKError } from '../../Public/Errors/SDKError';
import { SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * Configuration for STT component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
 */
export interface STTConfiguration extends ComponentConfiguration, ComponentInitParameters {
  readonly componentType: SDKComponent;
  readonly modelId: string | null;
  readonly language: string;
  readonly sampleRate: number;
  readonly enablePunctuation: boolean;
  readonly enableDiarization: boolean;
  readonly vocabularyList: string[];
  readonly maxAlternatives: number;
  readonly enableTimestamps: boolean;
  readonly useGPUIfAvailable: boolean;
}

/**
 * Create STT configuration
 */
export class STTConfigurationImpl implements STTConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.STT;
  public readonly modelId: string | null;
  public readonly language: string;
  public readonly sampleRate: number;
  public readonly enablePunctuation: boolean;
  public readonly enableDiarization: boolean;
  public readonly vocabularyList: string[];
  public readonly maxAlternatives: number;
  public readonly enableTimestamps: boolean;
  public readonly useGPUIfAvailable: boolean;

  constructor(options: {
    modelId?: string | null;
    language?: string;
    sampleRate?: number;
    enablePunctuation?: boolean;
    enableDiarization?: boolean;
    vocabularyList?: string[];
    maxAlternatives?: number;
    enableTimestamps?: boolean;
    useGPUIfAvailable?: boolean;
  } = {}) {
    this.modelId = options.modelId ?? null;
    this.language = options.language ?? 'en-US';
    this.sampleRate = options.sampleRate ?? 16000;
    this.enablePunctuation = options.enablePunctuation ?? true;
    this.enableDiarization = options.enableDiarization ?? false;
    this.vocabularyList = options.vocabularyList ?? [];
    this.maxAlternatives = options.maxAlternatives ?? 1;
    this.enableTimestamps = options.enableTimestamps ?? true;
    this.useGPUIfAvailable = options.useGPUIfAvailable ?? true;
  }

  public validate(): void {
    if (this.sampleRate <= 0 || this.sampleRate > 48000) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Sample rate must be between 1 and 48000 Hz'
      );
    }
    if (this.maxAlternatives <= 0 || this.maxAlternatives > 10) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Max alternatives must be between 1 and 10'
      );
    }
  }
}
