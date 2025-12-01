/**
 * TTSComponent.ts
 *
 * Text-to-Speech component following the clean architecture
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ModuleRegistry } from '../../Core/ModuleRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { TTSConfiguration } from './TTSConfiguration';
import type { TTSInput, TTSOutput, TTSOptions } from './TTSModels';
import type { TTSService } from '../../Core/Protocols/Voice/TTSService';
import type { TTSServiceProvider } from '../../Core/Protocols/Voice/TTSServiceProvider';
import type { TTSResult } from '../../Core/Models/TTS/TTSResult';
import type { TTSConfiguration as CoreTTSConfiguration } from '../../Core/Models/Configuration/TTSConfiguration';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';

/**
 * TTS Service Wrapper
 * Wrapper class to allow protocol-based TTS service to work with BaseComponent
 */
export class TTSServiceWrapper extends AnyServiceWrapper<TTSService> {
  constructor(service: TTSService | null = null) {
    super(service);
  }
}

/**
 * Text-to-Speech component
 */
export class TTSComponent extends BaseComponent<TTSServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.TTS;

  private readonly ttsConfiguration: TTSConfiguration;
  private currentVoice: string | null = null;

  // MARK: - Initialization

  constructor(configuration: TTSConfiguration) {
    super(configuration);
    this.ttsConfiguration = configuration;
    this.currentVoice = configuration.voice;
  }

  // MARK: - Service Creation

  protected override async createService(): Promise<TTSServiceWrapper> {
    const modelId = this.ttsConfiguration.voice;
    const modelName = modelId;

    // Try to get a registered TTS provider from central registry
    const provider = ModuleRegistry.shared.ttsProvider(modelId);

    try {
      let ttsService: TTSService;

      if (provider) {
        // Use registered provider (e.g., ONNXTTSServiceProvider)
        ttsService = await provider.createTTSService(this.ttsConfiguration);
      } else {
        // Fallback to default adapter (system TTS)
        // For React Native, we'll need to implement a default TTS service
        throw new SDKError(
          SDKErrorCode.ComponentNotInitialized,
          'No TTS service provider registered. Please register a TTS provider with ModuleRegistry.shared.registerTTS(provider).'
        );
      }

      // Wrap the service
      const wrapper = new TTSServiceWrapper(ttsService);

      return wrapper;
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        `Failed to create TTS service: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  protected override async performCleanup(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.cleanup();
    }
  }

  // MARK: - Public API

  /**
   * Synthesize text to audio
   */
  public async synthesize(text: string, options?: Partial<TTSOptions>): Promise<TTSOutput> {
    this.ensureReady();

    const input: TTSInput = {
      text,
      ssml: null,
      voiceId: options?.voice ?? null,
      language: options?.language ?? null,
      options: options as TTSOptions | null,
      validate: () => {
        if (!text || text.trim().length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'TTSInput must contain text');
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Process TTS input
   */
  public async process(input: TTSInput): Promise<TTSOutput> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    // Validate input
    input.validate();

    // Build options
    const options: TTSOptions = input.options ?? {
      voice: this.ttsConfiguration.voice,
      language: this.ttsConfiguration.language,
      rate: this.ttsConfiguration.speakingRate,
      pitch: this.ttsConfiguration.pitch,
      volume: this.ttsConfiguration.volume,
      audioFormat: this.ttsConfiguration.audioFormat,
      sampleRate: 16000, // Default sample rate
      useSSML: this.ttsConfiguration.enableSSML,
    };

    // Track processing time
    const startTime = Date.now();

    // Convert TTSOptions to TTSConfiguration for service
    const ttsConfig: CoreTTSConfiguration = {
      componentType: this.ttsConfiguration.componentType,
      modelId: this.ttsConfiguration.modelId,
      voice: options.voice ?? this.ttsConfiguration.voice,
      language: options.language ?? this.ttsConfiguration.language,
      speakingRate: options.rate ?? this.ttsConfiguration.speakingRate,
      pitch: options.pitch ?? this.ttsConfiguration.pitch,
      volume: options.volume ?? this.ttsConfiguration.volume,
      audioFormat: options.audioFormat ?? this.ttsConfiguration.audioFormat,
      useNeuralVoice: this.ttsConfiguration.useNeuralVoice,
      enableSSML: options.useSSML ?? this.ttsConfiguration.enableSSML,
      validate: () => {},
    };

    // Synthesize
    const result: TTSResult = await this.service.wrappedService.synthesize(
      input.ssml ?? input.text,
      ttsConfig
    );

    const processingTime = (Date.now() - startTime) / 1000; // seconds
    const characterCount = (input.ssml ?? input.text).length;
    const charactersPerSecond = processingTime > 0 ? characterCount / processingTime : 0;

    // Decode base64 audio data
    const audioData = Buffer.from(result.audio, 'base64');

    // Create output
    return {
      audioData,
      format: options.audioFormat ?? this.ttsConfiguration.audioFormat,
      duration: result.duration,
      phonemeTimestamps: null, // Not typically available
      metadata: {
        voice: options.voice ?? this.ttsConfiguration.voice,
        language: options.language ?? this.ttsConfiguration.language,
        processingTime,
        characterCount,
        charactersPerSecond,
      },
      timestamp: new Date(),
    };
  }

  /**
   * Stream synthesis for long text
   * Note: Most TTS services don't support true streaming, so this falls back to batch mode
   */
  public async synthesizeStream(
    text: string,
    options?: Partial<TTSOptions>,
    onChunk?: (chunk: Buffer | Uint8Array) => void
  ): Promise<void> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    // For now, TTS services typically don't support streaming
    // So we just synthesize the full text and call onChunk once
    const output = await this.synthesize(text, options);
    if (onChunk) {
      onChunk(output.audioData);
    }
  }

  /**
   * Get available voices
   */
  public async getAvailableVoices(): Promise<string[]> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    return await this.service.wrappedService.getAvailableVoices();
  }
}
