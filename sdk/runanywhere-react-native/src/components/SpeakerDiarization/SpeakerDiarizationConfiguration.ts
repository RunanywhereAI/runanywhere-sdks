/**
 * SpeakerDiarizationConfiguration.ts
 *
 * Configuration for Speaker Diarization component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/SpeakerDiarization/SpeakerDiarizationComponent.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import type { ComponentInitParameters } from '../../Core/Models/Common/ComponentInitParameters';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * Configuration for Speaker Diarization component
 */
export interface SpeakerDiarizationConfiguration extends ComponentConfiguration, ComponentInitParameters {
  readonly componentType: SDKComponent;
  readonly modelId: string | null;
  readonly maxSpeakers: number;
  readonly minSpeechDuration: number; // seconds
  readonly speakerChangeThreshold: number; // 0.0 to 1.0
  readonly enableVoiceIdentification: boolean;
  readonly windowSize: number; // seconds
  readonly stepSize: number; // seconds
}

/**
 * Create Speaker Diarization configuration
 */
export class SpeakerDiarizationConfigurationImpl implements SpeakerDiarizationConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.SpeakerDiarization;
  public readonly modelId: string | null;
  public readonly maxSpeakers: number;
  public readonly minSpeechDuration: number;
  public readonly speakerChangeThreshold: number;
  public readonly enableVoiceIdentification: boolean;
  public readonly windowSize: number;
  public readonly stepSize: number;

  constructor(options: {
    modelId?: string | null;
    maxSpeakers?: number;
    minSpeechDuration?: number;
    speakerChangeThreshold?: number;
    enableVoiceIdentification?: boolean;
    windowSize?: number;
    stepSize?: number;
  } = {}) {
    this.modelId = options.modelId ?? null;
    this.maxSpeakers = options.maxSpeakers ?? 10;
    this.minSpeechDuration = options.minSpeechDuration ?? 0.5;
    this.speakerChangeThreshold = options.speakerChangeThreshold ?? 0.7;
    this.enableVoiceIdentification = options.enableVoiceIdentification ?? false;
    this.windowSize = options.windowSize ?? 2.0;
    this.stepSize = options.stepSize ?? 0.5;
  }

  public validate(): void {
    if (this.maxSpeakers <= 0 || this.maxSpeakers > 100) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Max speakers must be between 1 and 100'
      );
    }
    if (this.minSpeechDuration <= 0 || this.minSpeechDuration > 10) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Min speech duration must be between 0 and 10 seconds'
      );
    }
    if (this.speakerChangeThreshold < 0 || this.speakerChangeThreshold > 1.0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Speaker change threshold must be between 0 and 1'
      );
    }
  }
}

