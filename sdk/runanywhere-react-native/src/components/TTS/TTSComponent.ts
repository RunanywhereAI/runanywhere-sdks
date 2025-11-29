/**
 * TTSComponent.ts
 *
 * Text-to-Speech component for RunAnywhere React Native SDK.
 * Follows the same architecture as Swift SDK's TTSComponent.swift.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/TTS/TTSComponent.swift
 */

import { NativeEventEmitter, NativeModules } from 'react-native';
import { EventBus } from '../../events';
import { SDKError, SDKErrorCode } from '../../errors';
// Note: We define TTSComponentConfiguration locally, which extends the basic TTSConfiguration concept

// ============================================================================
// TTS Configuration (Extended)
// ============================================================================

/**
 * Full configuration for TTS component
 * Reference: TTSConfiguration in TTSComponent.swift
 */
export interface TTSComponentConfiguration {
  /** Voice identifier */
  voice: string;

  /** Language code (e.g., 'en-US') */
  language: string;

  /** Speaking rate (0.5 to 2.0, 1.0 is normal) */
  speakingRate: number;

  /** Speech pitch (0.5 to 2.0, 1.0 is normal) */
  pitch: number;

  /** Speech volume (0.0 to 1.0) */
  volume: number;

  /** Audio format for output */
  audioFormat: 'pcm' | 'wav' | 'mp3';

  /** Use neural voice if available */
  useNeuralVoice: boolean;

  /** Enable SSML markup support */
  enableSSML: boolean;
}

/**
 * Default TTS configuration
 */
export const DEFAULT_TTS_CONFIG: TTSComponentConfiguration = {
  voice: 'default',
  language: 'en-US',
  speakingRate: 1.0,
  pitch: 1.0,
  volume: 1.0,
  audioFormat: 'pcm',
  useNeuralVoice: true,
  enableSSML: false,
};

// ============================================================================
// TTS Options
// ============================================================================

/**
 * Options for TTS synthesis
 * Reference: TTSOptions in TTSComponent.swift
 */
export interface TTSOptions {
  /** Voice to use */
  voice?: string;

  /** Language for synthesis */
  language?: string;

  /** Speech rate (0.5 to 2.0) */
  rate?: number;

  /** Speech pitch (0.5 to 2.0) */
  pitch?: number;

  /** Speech volume (0.0 to 1.0) */
  volume?: number;

  /** Audio format */
  audioFormat?: 'pcm' | 'wav' | 'mp3';

  /** Sample rate for output */
  sampleRate?: number;

  /** Use SSML markup */
  useSSML?: boolean;
}

// ============================================================================
// TTS Input/Output Types
// ============================================================================

/**
 * Input for Text-to-Speech
 * Reference: TTSInput in TTSComponent.swift
 */
export interface TTSInput {
  /** Text to synthesize */
  text: string;

  /** Optional SSML markup (overrides text if provided) */
  ssml?: string;

  /** Voice ID override */
  voiceId?: string;

  /** Language override */
  language?: string;

  /** Custom options override */
  options?: TTSOptions;
}

/**
 * Output from Text-to-Speech
 * Reference: TTSOutput in TTSComponent.swift
 */
export interface TTSOutput {
  /** Synthesized audio data (base64 encoded) */
  audioData: string;

  /** Audio format of the output */
  format: 'pcm' | 'wav' | 'mp3';

  /** Duration of the audio in seconds */
  duration: number;

  /** Sample rate of the audio */
  sampleRate: number;

  /** Number of samples */
  numSamples: number;

  /** Phoneme timestamps if available */
  phonemeTimestamps?: PhonemeTimestamp[];

  /** Processing metadata */
  metadata: SynthesisMetadata;

  /** Timestamp */
  timestamp: Date;
}

/**
 * Phoneme timestamp information
 */
export interface PhonemeTimestamp {
  phoneme: string;
  startTime: number; // seconds
  endTime: number; // seconds
}

/**
 * Synthesis metadata
 */
export interface SynthesisMetadata {
  voice: string;
  language: string;
  processingTime: number; // milliseconds
  characterCount: number;
  charactersPerSecond: number;
}

// ============================================================================
// Voice Info
// ============================================================================

/**
 * Information about an available voice
 */
export interface VoiceInfo {
  /** Voice identifier */
  id: string;

  /** Display name */
  name: string;

  /** Language code */
  language: string;

  /** Whether it's a neural voice */
  isNeural: boolean;

  /** Gender (if available) */
  gender?: 'male' | 'female' | 'neutral';
}

// ============================================================================
// TTS Component
// ============================================================================

/**
 * Text-to-Speech component
 *
 * Provides speech synthesis capabilities with batch and streaming support.
 * Follows the same architecture as Swift SDK's TTSComponent.
 *
 * @example
 * ```typescript
 * // Create component with configuration
 * const tts = new TTSComponent({
 *   voice: 'en-US-default',
 *   speakingRate: 1.0,
 * });
 *
 * // Initialize
 * await tts.initialize();
 *
 * // Synthesize speech
 * const result = await tts.synthesize('Hello, world!');
 * console.log('Audio length:', result.duration, 'seconds');
 *
 * // Play audio (implementation depends on your audio player)
 * playAudio(result.audioData);
 * ```
 */
export class TTSComponent {
  private configuration: TTSComponentConfiguration;
  private isModelLoaded = false;
  private currentVoice?: string;
  private nativeModule: any;
  private eventEmitter?: NativeEventEmitter;
  private _isSynthesizing = false;

  constructor(configuration: Partial<TTSComponentConfiguration> = {}) {
    this.configuration = { ...DEFAULT_TTS_CONFIG, ...configuration };
    this.nativeModule = NativeModules.RunAnywhere;
  }

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /**
   * Initialize the TTS component
   */
  async initialize(): Promise<void> {
    if (!this.nativeModule) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native module not available. Ensure the native module is properly linked.'
      );
    }

    // Check if createBackend method is available
    if (typeof this.nativeModule.createBackend !== 'function') {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native createBackend method not available. Native module may not be properly built.'
      );
    }

    // Create backend if not exists
    const backendCreated = await this.nativeModule.createBackend('onnx');
    if (!backendCreated) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Failed to create ONNX backend'
      );
    }

    // Check if initialize method is available
    if (typeof this.nativeModule.initialize !== 'function') {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native initialize method not available. Native module may not be properly built.'
      );
    }

    // Initialize backend
    const initResult = await this.nativeModule.initialize(null);

    if (!initResult) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Failed to initialize backend'
      );
    }

    // Set up event emitter
    this.eventEmitter = new NativeEventEmitter(this.nativeModule);
  }

  /**
   * Load a TTS model
   */
  async loadModel(
    modelPath: string,
    modelType: string = 'sherpa-onnx'
  ): Promise<void> {
    if (!this.nativeModule) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Component not initialized'
      );
    }

    // Check if loadTTSModel method is available
    if (typeof this.nativeModule.loadTTSModel !== 'function') {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native loadTTSModel method not available. Native module may not be properly built.'
      );
    }

    const configJson = JSON.stringify({
      voice: this.configuration.voice,
      language: this.configuration.language,
      speakingRate: this.configuration.speakingRate,
      pitch: this.configuration.pitch,
    });

    const result = await this.nativeModule.loadTTSModel(
      modelPath,
      modelType,
      configJson
    );

    if (!result) {
      const error = await this.nativeModule.getLastError?.() ?? 'Unknown error';
      throw new SDKError(
        SDKErrorCode.ModelLoadFailed,
        `Failed to load TTS model: ${error}`
      );
    }

    this.isModelLoaded = true;
    this.currentVoice = this.configuration.voice;

    // Emit model loaded event
    EventBus.emitModel({
      type: 'loadCompleted',
      modelId: modelPath,
    });
  }

  /**
   * Unload the TTS model
   */
  async unloadModel(): Promise<void> {
    if (!this.nativeModule || !this.isModelLoaded) return;

    // TTS unload - for now just mark as unloaded
    // Native method would be: ra_tts_unload_model
    this.isModelLoaded = false;
    this.currentVoice = undefined;
  }

  /**
   * Check if model is loaded
   */
  get modelLoaded(): boolean {
    return this.isModelLoaded;
  }

  /**
   * Check if currently synthesizing
   */
  get isSynthesizing(): boolean {
    return this._isSynthesizing;
  }

  /**
   * Cleanup resources
   */
  async cleanup(): Promise<void> {
    await this.stop();
    await this.unloadModel();
    if (this.nativeModule) {
      await this.nativeModule.destroy();
    }
  }

  // ============================================================================
  // Synthesis API
  // ============================================================================

  /**
   * Synthesize speech from text
   *
   * @param text - Text to synthesize
   * @param options - Optional TTS options
   * @returns Synthesis output with audio data
   */
  async synthesize(text: string, options?: TTSOptions): Promise<TTSOutput> {
    this.ensureReady();

    const voiceId = options?.voice ?? this.configuration.voice;
    const speedRate = options?.rate ?? this.configuration.speakingRate;
    const pitchShift = options?.pitch ?? this.configuration.pitch;

    const startTime = Date.now();
    this._isSynthesizing = true;

    try {
      // Check if synthesize method is available
      if (typeof this.nativeModule.synthesize !== 'function') {
        throw new SDKError(
          SDKErrorCode.ComponentNotInitialized,
          'Native synthesize method not available. Native module may not be properly built.'
        );
      }

      // Call native synthesize method
      const resultJson = await this.nativeModule.synthesize(
        text,
        voiceId,
        speedRate,
        pitchShift
      );

      const processingTime = Date.now() - startTime;

      // Parse result
      const result = JSON.parse(resultJson);

      if (result.error) {
        throw new SDKError(SDKErrorCode.SynthesisFailed, result.error);
      }

      // Calculate duration from samples and sample rate
      const duration =
        result.sampleRate > 0 ? result.numSamples / result.sampleRate : 0;

      return {
        audioData: result.audio,
        format: this.configuration.audioFormat,
        duration,
        sampleRate: result.sampleRate,
        numSamples: result.numSamples,
        metadata: {
          voice: voiceId,
          language: options?.language ?? this.configuration.language,
          processingTime,
          characterCount: text.length,
          charactersPerSecond:
            processingTime > 0 ? (text.length / processingTime) * 1000 : 0,
        },
        timestamp: new Date(),
      };
    } finally {
      this._isSynthesizing = false;
    }
  }

  /**
   * Synthesize with SSML markup
   */
  async synthesizeSSML(ssml: string, options?: TTSOptions): Promise<TTSOutput> {
    // For now, strip SSML tags and synthesize plain text
    // Full SSML support would require native implementation
    const plainText = ssml.replace(/<[^>]*>/g, '');
    return this.synthesize(plainText, { ...options, useSSML: true });
  }

  /**
   * Process TTS input
   */
  async process(input: TTSInput): Promise<TTSOutput> {
    const text = input.ssml ?? input.text;
    return this.synthesize(text, {
      voice: input.voiceId,
      language: input.language,
      ...input.options,
    });
  }

  // ============================================================================
  // Streaming Synthesis
  // ============================================================================

  /**
   * Stream synthesis for long text
   *
   * @param text - Text to synthesize
   * @param options - Optional TTS options
   * @yields Audio chunks (base64 encoded)
   */
  async *synthesizeStream(
    text: string,
    options?: TTSOptions
  ): AsyncGenerator<string, void, unknown> {
    this.ensureReady();

    // For now, synthesize the complete text and yield as single chunk
    // True streaming would require native streaming TTS support
    const result = await this.synthesize(text, options);
    yield result.audioData;
  }

  /**
   * Subscribe to audio chunk events for streaming
   */
  onAudioChunk(callback: (audioData: string) => void): () => void {
    if (!this.eventEmitter) {
      return () => {};
    }

    const subscription = this.eventEmitter.addListener(
      'onTTSAudio',
      (event: any) => {
        callback(event.audio);
      }
    );

    return () => subscription.remove();
  }

  // ============================================================================
  // Voice Management
  // ============================================================================

  /**
   * Get available voices
   */
  async getAvailableVoices(): Promise<VoiceInfo[]> {
    if (!this.nativeModule) {
      return [];
    }

    // Call native to get voices
    // For now, return mock voices based on sherpa-onnx capabilities
    return [
      {
        id: 'en-US-default',
        name: 'English (US) Default',
        language: 'en-US',
        isNeural: true,
      },
      {
        id: 'en-GB-default',
        name: 'English (UK) Default',
        language: 'en-GB',
        isNeural: true,
      },
    ];
  }

  /**
   * Set current voice
   */
  setVoice(voiceId: string): void {
    this.configuration.voice = voiceId;
    this.currentVoice = voiceId;
  }

  /**
   * Get current voice
   */
  getCurrentVoice(): string | undefined {
    return this.currentVoice;
  }

  // ============================================================================
  // Playback Control
  // ============================================================================

  /**
   * Stop current synthesis
   */
  async stop(): Promise<void> {
    if (!this.nativeModule) return;

    // Call native cancel
    // Native method: ra_tts_cancel
    this._isSynthesizing = false;
  }

  // ============================================================================
  // Event Subscriptions
  // ============================================================================

  /**
   * Subscribe to synthesis complete events
   */
  onComplete(callback: (result: TTSOutput) => void): () => void {
    if (!this.eventEmitter) {
      return () => {};
    }

    const subscription = this.eventEmitter.addListener(
      'onTTSComplete',
      (event: any) => {
        callback({
          audioData: event.audio ?? '',
          format: this.configuration.audioFormat,
          duration: event.duration ?? 0,
          sampleRate: event.sampleRate ?? 0,
          numSamples: event.numSamples ?? 0,
          metadata: {
            voice: this.currentVoice ?? 'unknown',
            language: this.configuration.language,
            processingTime: event.processingTime ?? 0,
            characterCount: event.characterCount ?? 0,
            charactersPerSecond: event.charactersPerSecond ?? 0,
          },
          timestamp: new Date(),
        });
      }
    );

    return () => subscription.remove();
  }

  /**
   * Subscribe to error events
   */
  onError(callback: (error: Error) => void): () => void {
    if (!this.eventEmitter) {
      return () => {};
    }

    const subscription = this.eventEmitter.addListener(
      'onTTSError',
      (event: any) => {
        callback(new SDKError(SDKErrorCode.SynthesisFailed, event.message));
      }
    );

    return () => subscription.remove();
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  private ensureReady(): void {
    if (!this.nativeModule) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'TTS component not initialized'
      );
    }

    if (!this.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'TTS model not loaded');
    }
  }
}

// Export default instance creator
export function createTTSComponent(
  configuration?: Partial<TTSComponentConfiguration>
): TTSComponent {
  return new TTSComponent(configuration);
}
