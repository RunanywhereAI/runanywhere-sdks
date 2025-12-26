/**
 * VoiceAgentConfiguration.ts
 *
 * Configuration for the Voice Agent composite component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/ComponentInitializationParameters.swift
 */

import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import type { ComponentConfiguration } from '../../Core/Components/BaseComponent';
import type { ComponentInitParameters } from '../../Core/Models/Common/ComponentInitParameters';
import type { VADConfiguration } from '../VAD/VADConfiguration';
import type { STTConfiguration } from '../STT/STTConfiguration';
import type { LLMConfiguration } from '../LLM/LLMConfiguration';
import type { TTSConfiguration } from '../TTS/TTSConfiguration';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';

/**
 * Configuration for the Voice Agent composite component
 */
export interface VoiceAgentConfiguration
  extends ComponentConfiguration, ComponentInitParameters {
  readonly componentType: SDKComponent;
  readonly modelId: string | null; // Voice agent doesn't have its own model
  readonly vadConfig: VADConfiguration;
  readonly sttConfig: STTConfiguration;
  readonly llmConfig: LLMConfiguration;
  readonly ttsConfig: TTSConfiguration;
}

/**
 * Create Voice Agent configuration
 */
export class VoiceAgentConfigurationImpl implements VoiceAgentConfiguration {
  public readonly componentType: SDKComponent = SDKComponent.VoiceAgent;
  public readonly modelId: string | null = null; // Voice agent doesn't have its own model
  public readonly vadConfig: VADConfiguration;
  public readonly sttConfig: STTConfiguration;
  public readonly llmConfig: LLMConfiguration;
  public readonly ttsConfig: TTSConfiguration;

  constructor(
    options: {
      vadConfig?: VADConfiguration;
      sttConfig?: STTConfiguration;
      llmConfig?: LLMConfiguration;
      ttsConfig?: TTSConfiguration;
    } = {}
  ) {
    // Use provided configs or create defaults
    // Note: These would need to import the actual configuration classes
    this.vadConfig = options.vadConfig ?? ({} as VADConfiguration);
    this.sttConfig = options.sttConfig ?? ({} as STTConfiguration);
    this.llmConfig = options.llmConfig ?? ({} as LLMConfiguration);
    this.ttsConfig = options.ttsConfig ?? ({} as TTSConfiguration);
  }

  public validate(): void {
    try {
      this.vadConfig.validate();
      this.sttConfig.validate();
      this.llmConfig.validate();
      this.ttsConfig.validate();
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.ValidationFailed,
        `Voice agent configuration validation failed: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }
}
