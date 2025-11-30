/**
 * TTSComponent.ts
 *
 * Text-to-Speech component for RunAnywhere React Native SDK.
 * Follows the exact architecture and patterns from Swift SDK's TTSComponent.swift.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift
 */

import { BaseComponent } from '../BaseComponent';
import type { ComponentConfiguration, ComponentInput, ComponentOutput } from '../BaseComponent';
import { requireNativeModule } from '../../native/NativeRunAnywhere';
import { SDKError, SDKErrorCode } from '../../errors';
import { AudioFormat, SDKComponent } from '../../types/enums';

/**
 * Get default sample rate for audio format
 */
export function getAudioFormatSampleRate(format: AudioFormat): number {
  switch (format) {
    case AudioFormat.WAV:
    case AudioFormat.PCM:
    case AudioFormat.FLAC:
      return 16000;
    case AudioFormat.MP3:
    case AudioFormat.M4A:
      return 44100;
    case AudioFormat.OPUS:
      return 48000;
    default:
      return 16000;
  }
}

// ============================================================================
// TTS Configuration
// ============================================================================

/**
 * Configuration for TTS component
 * Reference: TTSConfiguration in TTSComponent.swift
 *
 * Conforms to ComponentConfiguration and ComponentInitParameters protocols
 */
export interface TTSConfiguration extends ComponentConfiguration {
  /** Component type */
  readonly componentType: SDKComponent;

  /** Model ID (not typically used for TTS) */
  readonly modelId?: string | null;

  /** Voice identifier */
  voice: string;

  /** Language code */
  language: string;

  /** Speaking rate (0.5 to 2.0) */
  speakingRate: number;

  /** Pitch (0.5 to 2.0) */
  pitch: number;

  /** Volume (0.0 to 1.0) */
  volume: number;

  /** Audio format */
  audioFormat: AudioFormat;

  /** Use neural voice (if available) */
  useNeuralVoice: boolean;

  /** Enable SSML */
  enableSSML: boolean;

  /** Validate configuration */
  validate(): void;
}

/**
 * Default TTS configuration
 */
export const DEFAULT_TTS_CONFIGURATION: Omit<TTSConfiguration, 'componentType' | 'validate'> = {
  modelId: undefined,
  voice: 'com.apple.ttsbundle.siri_female_en-US_compact',
  language: 'en-US',
  speakingRate: 1.0,
  pitch: 1.0,
  volume: 1.0,
  audioFormat: AudioFormat.PCM,
  useNeuralVoice: true,
  enableSSML: false,
};

/**
 * Create TTS configuration with defaults
 */
export function createTTSConfiguration(
  config: Partial<Omit<TTSConfiguration, 'componentType' | 'validate'>>
): TTSConfiguration {
  return {
    componentType: SDKComponent.TTS,
    ...DEFAULT_TTS_CONFIGURATION,
    ...config,
    validate(): void {
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
    },
  };
}

// ============================================================================
// TTS Options
// ============================================================================

/**
 * Options for text-to-speech synthesis
 * Reference: TTSOptions in TTSComponent.swift
 */
export interface TTSOptions {
  /** Voice to use for synthesis */
  voice?: string | null;

  /** Language for synthesis */
  language: string;

  /** Speech rate (0.0 to 2.0, 1.0 is normal) */
  rate: number;

  /** Speech pitch (0.0 to 2.0, 1.0 is normal) */
  pitch: number;

  /** Speech volume (0.0 to 1.0) */
  volume: number;

  /** Audio format for output */
  audioFormat: AudioFormat;

  /** Sample rate for output audio */
  sampleRate: number;

  /** Whether to use SSML markup */
  useSSML: boolean;
}

// ============================================================================
// TTS Input/Output Models
// ============================================================================

/**
 * Input for Text-to-Speech
 * Reference: TTSInput in TTSComponent.swift
 */
export interface TTSInput extends ComponentInput {
  /** Text to synthesize */
  text: string;

  /** Optional SSML markup (overrides text if provided) */
  ssml?: string | null;

  /** Voice ID override */
  voiceId?: string | null;

  /** Language override */
  language?: string | null;

  /** Custom options override */
  options?: TTSOptions | null;

  /** Validate input */
  validate(): void;
}

/**
 * Phoneme timestamp information
 * Reference: PhonemeTimestamp in TTSComponent.swift
 */
export interface PhonemeTimestamp {
  phoneme: string;
  startTime: number;
  endTime: number;
}

/**
 * Synthesis metadata
 * Reference: SynthesisMetadata in TTSComponent.swift
 */
export interface SynthesisMetadata {
  voice: string;
  language: string;
  processingTime: number;
  characterCount: number;
  charactersPerSecond: number;
}

/**
 * Output from Text-to-Speech
 * Reference: TTSOutput in TTSComponent.swift
 */
export interface TTSOutput extends ComponentOutput {
  /** Synthesized audio data (base64 encoded) */
  audioData: string;

  /** Audio format of the output */
  format: AudioFormat;

  /** Duration of the audio in seconds */
  duration: number;

  /** Sample rate of the audio */
  sampleRate: number;

  /** Number of samples */
  numSamples: number;

  /** Phoneme timestamps if available */
  phonemeTimestamps?: PhonemeTimestamp[] | null;

  /** Processing metadata */
  metadata: SynthesisMetadata;

  /** Timestamp (required by ComponentOutput) */
  timestamp: Date;
}

/**
 * Voice information
 */
export interface VoiceInfo {
  id: string;
  name: string;
  language: string;
  isNeural?: boolean;
}

// ============================================================================
// TTS Service Protocol
// ============================================================================

/**
 * Protocol for text-to-speech services
 * Reference: TTSService protocol in TTSComponent.swift
 */
export interface TTSService {
  /** Initialize the TTS service */
  initialize(): Promise<void>;

  /** Synthesize text to audio */
  synthesize(text: string, options: TTSOptions): Promise<string>;

  /** Stream synthesis for long text */
  synthesizeStream(
    text: string,
    options: TTSOptions,
    onChunk: (chunk: string) => void
  ): Promise<void>;

  /** Stop current synthesis */
  stop(): void;

  /** Check if currently synthesizing */
  readonly isSynthesizing: boolean;

  /** Get available voices */
  readonly availableVoices: string[];

  /** Cleanup resources */
  cleanup(): Promise<void>;
}

/**
 * Service wrapper for TTS service
 * Reference: TTSServiceWrapper in TTSComponent.swift
 */
export class TTSServiceWrapper {
  public wrappedService: TTSService | null = null;

  constructor(service?: TTSService) {
    this.wrappedService = service || null;
  }
}

// ============================================================================
// Native TTS Service Implementation
// ============================================================================

/**
 * Native implementation of TTSService using NativeRunAnywhere
 * This bridges to the native TTS implementation
 */
class NativeTTSService implements TTSService {
  private nativeModule: any;
  private _isSynthesizing = false;
  private _isInitialized = false;

  constructor() {
    this.nativeModule = requireNativeModule();
  }

  async initialize(): Promise<void> {
    if (this._isInitialized) {
      return;
    }

    // System TTS doesn't require explicit initialization
    // Just verify the module is available
    if (!this.nativeModule) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native module not available'
      );
    }

    this._isInitialized = true;
  }

  async synthesize(text: string, options: TTSOptions): Promise<string> {
    if (!this._isInitialized) {
      throw new SDKError(SDKErrorCode.NotInitialized, 'TTS service not initialized');
    }

    this._isSynthesizing = true;

    try {
      // Call native synthesize method
      const resultJson = await this.nativeModule.synthesize(
        text,
        options.voice || null,
        options.rate,
        options.pitch
      );

      if (!resultJson) {
        throw new SDKError(SDKErrorCode.SynthesisFailed, 'Synthesis failed');
      }

      return resultJson;
    } finally {
      this._isSynthesizing = false;
    }
  }

  async synthesizeStream(
    text: string,
    options: TTSOptions,
    onChunk: (chunk: string) => void
  ): Promise<void> {
    // System TTS doesn't support true streaming
    // Just synthesize the complete text
    const result = await this.synthesize(text, options);
    onChunk(result); // Signal completion with result
  }

  stop(): void {
    if (this.nativeModule?.cancelTTS) {
      this.nativeModule.cancelTTS();
    }
    this._isSynthesizing = false;
  }

  get isSynthesizing(): boolean {
    return this._isSynthesizing;
  }

  get availableVoices(): string[] {
    // Would call native to get voices
    // For now return empty - native implementation needs to provide this
    return [];
  }

  async cleanup(): Promise<void> {
    this.stop();
    this._isInitialized = false;
  }
}

// ============================================================================
// TTS Component
// ============================================================================

/**
 * Text-to-Speech component following the clean architecture
 *
 * Extends BaseComponent to provide TTS capabilities with lifecycle management.
 * Matches the Swift SDK TTSComponent implementation exactly.
 *
 * Reference: TTSComponent in TTSComponent.swift
 *
 * @example
 * ```typescript
 * // Create and initialize component
 * const config = createTTSConfiguration({
 *   voice: 'en-US-default',
 *   speakingRate: 1.0,
 *   pitch: 1.0,
 * });
 *
 * const tts = new TTSComponent(config);
 * await tts.initialize();
 *
 * // Synthesize speech
 * const result = await tts.synthesize('Hello, world!');
 * console.log('Audio duration:', result.duration, 'seconds');
 *
 * // Synthesize with SSML
 * const ssmlResult = await tts.synthesizeSSML('<speak>Hello!</speak>');
 * ```
 */
export class TTSComponent extends BaseComponent<TTSServiceWrapper> {
  // ============================================================================
  // Static Properties
  // ============================================================================

  /**
   * Component type identifier
   * Reference: componentType in TTSComponent.swift
   */
  static override componentType = SDKComponent.TTS;

  // ============================================================================
  // Instance Properties
  // ============================================================================

  private readonly ttsConfiguration: TTSConfiguration;

  // ============================================================================
  // Constructor
  // ============================================================================

  constructor(configuration: TTSConfiguration) {
    super(configuration);
    this.ttsConfiguration = configuration;
  }

  // ============================================================================
  // Service Creation
  // ============================================================================

  /**
   * Create the TTS service
   *
   * Reference: createService() in TTSComponent.swift
   */
  protected async createService(): Promise<TTSServiceWrapper> {
    const modelId = this.ttsConfiguration.voice;

    // Emit checking event
    this.eventBus.emitComponentInitialization({
      type: 'componentChecking',
      component: TTSComponent.componentType,
      modelId: modelId,
    });

    try {
      // Create native TTS service (System TTS fallback)
      const ttsService = new NativeTTSService();
      await ttsService.initialize();

      // Wrap the service
      const wrapper = new TTSServiceWrapper(ttsService);

      return wrapper;
    } catch (error) {
      throw error;
    }
  }

  protected async initializeService(): Promise<void> {
    const wrappedService = this.service?.wrappedService;
    if (!wrappedService) {
      return;
    }

    // Track initialization
    this.eventBus.emitComponentInitialization({
      type: 'componentInitializing',
      component: TTSComponent.componentType,
      modelId: undefined,
    });

    await wrappedService.initialize();
  }

  // ============================================================================
  // Public API
  // ============================================================================

  /**
   * Synthesize speech from text
   *
   * Reference: synthesize(_:voice:language:) in TTSComponent.swift
   *
   * @param text - Text to synthesize
   * @param voice - Voice override
   * @param language - Language override
   * @returns TTS output with audio data
   */
  async synthesize(text: string, voice?: string | null, language?: string | null): Promise<TTSOutput> {
    this.ensureReady();

    const input: TTSInput = {
      text,
      voiceId: voice,
      language: language,
      validate: () => {
        if (!text || text.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'Text is required');
        }
      },
    };

    return this.process(input);
  }

  /**
   * Synthesize with SSML markup
   *
   * Reference: synthesizeSSML(_:voice:language:) in TTSComponent.swift
   *
   * @param ssml - SSML markup
   * @param voice - Voice override
   * @param language - Language override
   * @returns TTS output with audio data
   */
  async synthesizeSSML(ssml: string, voice?: string | null, language?: string | null): Promise<TTSOutput> {
    this.ensureReady();

    const input: TTSInput = {
      text: '',
      ssml: ssml,
      voiceId: voice,
      language: language,
      validate: () => {
        if (!ssml || ssml.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'SSML is required');
        }
      },
    };

    return this.process(input);
  }

  /**
   * Process TTS input
   *
   * Reference: process(_:) in TTSComponent.swift
   *
   * @param input - TTS input with text/SSML and options
   * @returns TTS output with audio data
   */
  async process(input: TTSInput): Promise<TTSOutput> {
    this.ensureReady();

    const ttsService = this.service?.wrappedService;
    if (!ttsService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    // Validate input
    input.validate();

    // Get text to synthesize
    const textToSynthesize = input.ssml || input.text;

    // Create options from input or use defaults
    const options: TTSOptions = input.options || {
      voice: input.voiceId || this.ttsConfiguration.voice,
      language: input.language || this.ttsConfiguration.language,
      rate: this.ttsConfiguration.speakingRate,
      pitch: this.ttsConfiguration.pitch,
      volume: this.ttsConfiguration.volume,
      audioFormat: this.ttsConfiguration.audioFormat,
      sampleRate: getAudioFormatSampleRate(this.ttsConfiguration.audioFormat),
      useSSML: input.ssml !== null && input.ssml !== undefined,
    };

    // Track processing time
    const startTime = Date.now();

    // Perform synthesis
    const resultJson = await ttsService.synthesize(textToSynthesize, options);

    const processingTime = Date.now() - startTime;

    // Parse result
    const result = JSON.parse(resultJson);

    if (result.error) {
      throw new SDKError(SDKErrorCode.SynthesisFailed, result.error);
    }

    // Calculate duration from samples and sample rate
    const duration = result.sampleRate > 0 ? result.numSamples / result.sampleRate : 0;

    const metadata: SynthesisMetadata = {
      voice: options.voice || this.ttsConfiguration.voice,
      language: options.language,
      processingTime,
      characterCount: textToSynthesize.length,
      charactersPerSecond: processingTime > 0 ? (textToSynthesize.length / processingTime) * 1000 : 0,
    };

    return {
      audioData: result.audio,
      format: this.ttsConfiguration.audioFormat,
      duration,
      sampleRate: result.sampleRate,
      numSamples: result.numSamples,
      phonemeTimestamps: null, // Would be extracted from service if available
      metadata,
      timestamp: new Date(),
    };
  }

  /**
   * Stream synthesis for long text
   *
   * Reference: streamSynthesize(_:voice:language:) in TTSComponent.swift
   *
   * @param text - Text to synthesize
   * @param voice - Voice override
   * @param language - Language override
   * @returns Async stream of audio chunks (base64 encoded)
   */
  async *streamSynthesize(
    text: string,
    voice?: string | null,
    language?: string | null
  ): AsyncGenerator<string, void, unknown> {
    this.ensureReady();

    const ttsService = this.service?.wrappedService;
    if (!ttsService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'TTS service not available');
    }

    const options: TTSOptions = {
      voice: voice || this.ttsConfiguration.voice,
      language: language || this.ttsConfiguration.language,
      rate: this.ttsConfiguration.speakingRate,
      pitch: this.ttsConfiguration.pitch,
      volume: this.ttsConfiguration.volume,
      audioFormat: this.ttsConfiguration.audioFormat,
      sampleRate: getAudioFormatSampleRate(this.ttsConfiguration.audioFormat),
      useSSML: false,
    };

    const chunks: string[] = [];

    await ttsService.synthesizeStream(text, options, (chunk) => {
      chunks.push(chunk);
    });

    // Yield all chunks
    for (const chunk of chunks) {
      yield chunk;
    }
  }

  /**
   * Get available voices
   *
   * Reference: getAvailableVoices() in TTSComponent.swift
   *
   * @returns Array of available voice identifiers
   */
  getAvailableVoices(): string[] {
    return this.service?.wrappedService?.availableVoices || [];
  }

  /**
   * Stop current synthesis
   *
   * Reference: stopSynthesis() in TTSComponent.swift
   */
  stopSynthesis(): void {
    this.service?.wrappedService?.stop();
  }

  /**
   * Check if currently synthesizing
   *
   * Reference: isSynthesizing in TTSComponent.swift
   */
  get isSynthesizing(): boolean {
    return this.service?.wrappedService?.isSynthesizing || false;
  }

  /**
   * Get wrapped TTS service
   *
   * @returns The wrapped TTS service instance
   */
  getTTSService(): TTSService | null {
    return this.service?.wrappedService || null;
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /**
   * Cleanup resources
   *
   * Reference: performCleanup() in TTSComponent.swift
   */
  protected async performCleanup(): Promise<void> {
    this.service?.wrappedService?.stop();
    await this.service?.wrappedService?.cleanup();
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/**
 * Create a TTS component with configuration
 *
 * @param config - Partial configuration (merged with defaults)
 * @returns Configured TTS component
 */
export function createTTSComponent(
  config?: Partial<Omit<TTSConfiguration, 'componentType' | 'validate'>>
): TTSComponent {
  const configuration = createTTSConfiguration(config || {});
  return new TTSComponent(configuration);
}

// ============================================================================
// Exports
// ============================================================================
// All exports are already declared above as `export interface` or `export class`
// No need for additional export statements
