/**
 * TTSConfiguration.ts
 *
 * Configuration for TTS component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import type { ComponentInitParameters } from '../../Core/Models/Common/ComponentInitParameters';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * Configuration for TTS component (conforms to ComponentConfiguration and ComponentInitParameters protocols)
 */
export interface TTSConfiguration extends ComponentConfiguration, ComponentInitParameters {
  readonly componentType: SDKComponent;
  readonly modelId: string | null; // Not typically used for TTS
  readonly voice: string;
  readonly language: string;
  readonly speakingRate: number; // 0.5 to 2.0
  readonly pitch: number; // 0.5 to 2.0
  readonly volume: number; // 0.0 to 1.0
  readonly audioFormat: string;
  readonly useNeuralVoice: boolean;
  readonly enableSSML: boolean;
}

/**
 * Create TTS configuration
 */
export class TTSConfigurationImpl implements TTSConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.TTS;
  public readonly modelId: string | null = null; // Not typically used for TTS
  public readonly voice: string;
  public readonly language: string;
  public readonly speakingRate: number;
  public readonly pitch: number;
  public readonly volume: number;
  public readonly audioFormat: string;
  public readonly useNeuralVoice: boolean;
  public readonly enableSSML: boolean;

  constructor(options: {
    voice?: string;
    language?: string;
    speakingRate?: number;
    pitch?: number;
    volume?: number;
    audioFormat?: string;
    useNeuralVoice?: boolean;
    enableSSML?: boolean;
  } = {}) {
    this.voice = options.voice ?? 'com.apple.ttsbundle.siri_female_en-US_compact';
    this.language = options.language ?? 'en-US';
    this.speakingRate = options.speakingRate ?? 1.0;
    this.pitch = options.pitch ?? 1.0;
    this.volume = options.volume ?? 1.0;
    this.audioFormat = options.audioFormat ?? 'pcm';
    this.useNeuralVoice = options.useNeuralVoice ?? true;
    this.enableSSML = options.enableSSML ?? false;
  }

  public validate(): void {
    if (this.speakingRate < 0.5 || this.speakingRate > 2.0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Speaking rate must be between 0.5 and 2.0'
      );
    }
    if (this.pitch < 0.5 || this.pitch > 2.0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Pitch must be between 0.5 and 2.0'
      );
    }
    if (this.volume < 0.0 || this.volume > 1.0) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        'Volume must be between 0.0 and 1.0'
      );
    }
  }
}
