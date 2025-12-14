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
import { NativeRunAnywhere } from '../../native/NativeRunAnywhere';

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
        // Fallback to system TTS service
        const { SystemTTSService } = await import('../../services/SystemTTSService');
        ttsService = new SystemTTSService();
        await ttsService.initialize();
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

    // Check if native streaming is supported
    const supportsStreaming = await NativeRunAnywhere.supportsTTSStreaming();

    if (supportsStreaming && onChunk) {
      // Use native streaming if available
      const voiceId = options?.voice ?? this.ttsConfiguration.voice;
      const speedRate = options?.rate ?? this.ttsConfiguration.speakingRate;
      const pitchShift = options?.pitch ?? this.ttsConfiguration.pitch;

      // Start streaming synthesis
      NativeRunAnywhere.synthesizeStream(text, voiceId, speedRate, pitchShift);

      // Note: Audio chunks would be emitted via event emitter
      // This is a placeholder for the streaming implementation
      // The actual chunk delivery would need to be handled via React Native's EventEmitter
    } else {
      // Fallback to batch mode
      const output = await this.synthesize(text, options);
      if (onChunk) {
        onChunk(output.audioData);
      }
    }
  }

  /**
   * Stream synthesis as AsyncGenerator
   * Provides a modern async iteration interface for streaming TTS
   */
  public async *synthesizeStreamGenerator(
    text: string,
    options?: Partial<TTSOptions>
  ): AsyncGenerator<Buffer | Uint8Array> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    // For now, yield the complete synthesis result
    // True streaming would yield chunks as they become available
    const output = await this.synthesize(text, options);
    yield output.audioData;
  }

  /**
   * Get available voices
   */
  public async getAvailableVoices(): Promise<string[]> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    if (!this.service.wrappedService.getAvailableVoices) {
      return [];
    }

    return await this.service.wrappedService.getAvailableVoices();
  }

  /**
   * Get detailed voice information
   * Returns structured voice metadata including language, gender, quality, etc.
   */
  public async getVoiceInfo(): Promise<import('../../Core/Protocols/Voice/TTSService').VoiceInfo[]> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    if (!this.service.wrappedService.getVoiceInfo) {
      return [];
    }

    return await this.service.wrappedService.getVoiceInfo();
  }

  /**
   * Get voices filtered by language
   * @param language - Language code (e.g., 'en-US', 'es-ES')
   */
  public async getVoicesByLanguage(language: string): Promise<string[]> {
    const allVoices = await this.getAvailableVoices();

    // Filter voices that match the language
    return allVoices.filter(voice => {
      if (!voice) return false;
      const voiceLower = voice.toLowerCase();
      const languageLower = language.toLowerCase();
      const langPrefix = language.split('-')[0]?.toLowerCase() || '';
      return voiceLower.includes(languageLower) || voiceLower.startsWith(langPrefix);
    });
  }

  /**
   * Set the current voice for synthesis
   * @param voiceId - Voice identifier to use
   */
  public setVoice(voiceId: string): void {
    this.currentVoice = voiceId;
  }

  /**
   * Get the current voice setting
   */
  public getVoice(): string | null {
    return this.currentVoice;
  }

  /**
   * Stop current synthesis playback
   */
  public async stopSynthesis(): Promise<void> {
    if (this.service?.wrappedService) {
      await NativeRunAnywhere.cancelTTS();
    }
  }

  /**
   * Check if TTS is currently playing/synthesizing
   */
  public async isSynthesizing(): Promise<boolean> {
    // This would need native state tracking
    // For now, return false as a placeholder
    return false;
  }
}
