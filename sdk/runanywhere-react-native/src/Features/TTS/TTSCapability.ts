/**
 * TTSCapability.ts
 *
 * Actor-based TTS capability that owns model lifecycle and synthesis.
 * Uses ManagedLifecycle for unified lifecycle + analytics handling.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/TTS/TTSCapability.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ServiceRegistry } from '../../Foundation/DependencyInjection/ServiceRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { TTSConfiguration } from './TTSConfiguration';
import type { TTSInput, TTSOutput, TTSOptions } from './TTSModels';
import type { TTSService } from '../../Core/Protocols/Voice/TTSService';
import type { TTSResult } from '../../Core/Models/TTS/TTSResult';
import type { TTSConfiguration as CoreTTSConfiguration } from '../../Core/Models/Configuration/TTSConfiguration';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';
import { NativeRunAnywhere } from '../../native/NativeRunAnywhere';
import { ManagedLifecycle } from '../../Core/Capabilities/ManagedLifecycle';
import type { ComponentConfiguration } from '../../Core/Capabilities/CapabilityProtocols';

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
 * Text-to-Speech capability
 *
 * Uses `ManagedLifecycle` to handle model loading/unloading with automatic analytics tracking.
 */
export class TTSCapability extends BaseComponent<TTSServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.TTS;

  private readonly ttsConfiguration: TTSConfiguration;
  private currentVoice: string | null = null;

  /**
   * Managed lifecycle with integrated event tracking
   * Matches iOS: private let managedLifecycle: ManagedLifecycle<TTSService>
   */
  private readonly managedLifecycle: ManagedLifecycle<TTSService>;

  // MARK: - Initialization

  constructor(configuration: TTSConfiguration) {
    super(configuration);
    this.ttsConfiguration = configuration;
    this.currentVoice = configuration.voice;

    // Create managed lifecycle for TTS with load/unload functions
    this.managedLifecycle = ManagedLifecycle.forTTS<TTSService>(
      // Load resource function
      async (resourceId: string, _config: ComponentConfiguration | null) => {
        return await this.loadTTSService(resourceId);
      },
      // Unload resource function
      async (service: TTSService) => {
        await service.cleanup();
      }
    );

    // Configure lifecycle with our configuration
    this.managedLifecycle.configure(configuration as ComponentConfiguration);
  }

  // MARK: - Model Lifecycle (ModelLoadableCapability Protocol)
  // All lifecycle operations are delegated to ManagedLifecycle which handles analytics automatically

  /**
   * Whether a model is currently loaded
   * Matches iOS: public var isModelLoaded: Bool { get async { await managedLifecycle.isLoaded } }
   */
  get isModelLoaded(): boolean {
    return this.managedLifecycle.isLoaded;
  }

  /**
   * The currently loaded model ID
   * Matches iOS: public var currentModelId: String? { get async { await managedLifecycle.currentResourceId } }
   */
  get currentModelId(): string | null {
    return this.managedLifecycle.currentResourceId;
  }

  /**
   * Load a model/voice by ID
   * Matches iOS: public func loadModel(_ modelId: String) async throws
   */
  async loadModel(modelId: string): Promise<void> {
    const ttsService = await this.managedLifecycle.load(modelId);
    // Update BaseComponent's service reference for compatibility
    this.service = new TTSServiceWrapper(ttsService);
    this.currentVoice = modelId;
  }

  /**
   * Unload the currently loaded model
   * Matches iOS: public func unload() async throws
   */
  async unloadModel(): Promise<void> {
    await this.managedLifecycle.unload();
    this.service = null;
  }

  // MARK: - Private Service Loading

  /**
   * Load TTS service for a given model/voice ID
   * Called by ManagedLifecycle during load()
   */
  private async loadTTSService(modelId: string): Promise<TTSService> {
    // Try to get a registered TTS provider from central registry
    const provider = ServiceRegistry.shared.ttsProvider(modelId);

    if (provider) {
      // Use registered provider (e.g., ONNXTTSServiceProvider)
      return await provider.createTTSService(this.ttsConfiguration);
    } else {
      // Fallback to system TTS service
      const { SystemTTSService } =
        await import('../../services/SystemTTSService');
      const ttsService = new SystemTTSService();
      await ttsService.initialize();
      return ttsService;
    }
  }

  // MARK: - Service Creation (BaseComponent compatibility)

  protected override async createService(): Promise<TTSServiceWrapper> {
    // If voice is provided in config, load through managed lifecycle
    if (this.ttsConfiguration.voice) {
      await this.loadModel(this.ttsConfiguration.voice);
      if (!this.service) {
        throw new SDKError(
          SDKErrorCode.InvalidState,
          'Service was not created after loading model'
        );
      }
      return this.service;
    }

    // Fallback: create service without loading model (caller will load model separately)
    return new TTSServiceWrapper(null);
  }

  protected override async performCleanup(): Promise<void> {
    await this.managedLifecycle.reset();
  }

  // MARK: - Public API

  /**
   * Synthesize text to audio
   */
  public async synthesize(
    text: string,
    options?: Partial<TTSOptions>
  ): Promise<TTSOutput> {
    this.ensureReady();

    const input: TTSInput = {
      text,
      ssml: null,
      voiceId: options?.voice ?? null,
      language: options?.language ?? null,
      options: options as TTSOptions | null,
      validate: () => {
        if (!text || text.trim().length === 0) {
          throw new SDKError(
            SDKErrorCode.ValidationFailed,
            'TTSInput must contain text'
          );
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

    // Use managedLifecycle.requireService() for iOS parity
    const ttsService = this.managedLifecycle.requireService();

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

    // Synthesize using service from managed lifecycle
    const result: TTSResult = await ttsService.synthesize(
      input.ssml ?? input.text,
      ttsConfig
    );

    const processingTime = (Date.now() - startTime) / 1000; // seconds
    const characterCount = (input.ssml ?? input.text).length;
    const charactersPerSecond =
      processingTime > 0 ? characterCount / processingTime : 0;

    // Decode base64 audio data (result.audioData is already base64 from native)
    const audioData = Buffer.from(result.audioData, 'base64');

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

    // Use managedLifecycle.requireService() for iOS parity
    this.managedLifecycle.requireService(); // Ensure service is loaded

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

    // Use managedLifecycle.requireService() for iOS parity
    this.managedLifecycle.requireService(); // Ensure service is loaded

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

    // Use managedLifecycle.requireService() for iOS parity
    const ttsService = this.managedLifecycle.requireService();

    if (!ttsService.getAvailableVoices) {
      return [];
    }

    return await ttsService.getAvailableVoices();
  }

  /**
   * Get detailed voice information
   * Returns structured voice metadata including language, gender, quality, etc.
   */
  public async getVoiceInfo(): Promise<
    import('../../Core/Protocols/Voice/TTSService').VoiceInfo[]
  > {
    this.ensureReady();

    // Use managedLifecycle.requireService() for iOS parity
    const ttsService = this.managedLifecycle.requireService();

    if (!ttsService.getVoiceInfo) {
      return [];
    }

    return await ttsService.getVoiceInfo();
  }

  /**
   * Get voices filtered by language
   * @param language - Language code (e.g., 'en-US', 'es-ES')
   */
  public async getVoicesByLanguage(language: string): Promise<string[]> {
    const allVoices = await this.getAvailableVoices();

    // Filter voices that match the language
    return allVoices.filter((voice) => {
      if (!voice) return false;
      const voiceLower = voice.toLowerCase();
      const languageLower = language.toLowerCase();
      const langPrefix = language.split('-')[0]?.toLowerCase() || '';
      return (
        voiceLower.includes(languageLower) || voiceLower.startsWith(langPrefix)
      );
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
