/**
 * STTComponent.ts
 *
 * Speech-to-Text component for RunAnywhere React Native SDK.
 * Follows the same architecture as Swift SDK's STTComponent.swift.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift
 */

import { NativeEventEmitter, NativeModules } from 'react-native';
import { EventBus } from '../../events';
import { SDKError, SDKErrorCode } from '../../errors';
import type { STTOptions } from '../../types';

// ============================================================================
// STT Configuration
// ============================================================================

/**
 * Configuration for STT component
 * Reference: STTConfiguration in STTComponent.swift
 */
export interface STTConfiguration {
  /** Model ID for the STT model */
  modelId?: string;

  /** Language code (e.g., 'en-US') */
  language: string;

  /** Sample rate in Hz (default: 16000) */
  sampleRate: number;

  /** Enable automatic punctuation */
  enablePunctuation: boolean;

  /** Enable speaker diarization */
  enableDiarization: boolean;

  /** Custom vocabulary words */
  vocabularyList: string[];

  /** Maximum alternative transcriptions */
  maxAlternatives: number;

  /** Enable word timestamps */
  enableTimestamps: boolean;

  /** Use GPU if available */
  useGPUIfAvailable: boolean;
}

/**
 * Default STT configuration
 */
export const DEFAULT_STT_CONFIG: STTConfiguration = {
  language: 'en-US',
  sampleRate: 16000,
  enablePunctuation: true,
  enableDiarization: false,
  vocabularyList: [],
  maxAlternatives: 1,
  enableTimestamps: true,
  useGPUIfAvailable: true,
};

// ============================================================================
// STT Input/Output Types
// ============================================================================

/**
 * Input for Speech-to-Text
 * Reference: STTInput in STTComponent.swift
 */
export interface STTInput {
  /** Audio data (base64 encoded float32 PCM) */
  audioData: string;

  /** Audio format */
  format: 'pcm' | 'wav' | 'mp3';

  /** Language code override */
  language?: string;

  /** Custom options override */
  options?: STTOptions;
}

/**
 * Output from Speech-to-Text
 * Reference: STTOutput in STTComponent.swift
 */
export interface STTOutput {
  /** Transcribed text */
  text: string;

  /** Confidence score (0.0 to 1.0) */
  confidence: number;

  /** Word-level timestamps if available */
  wordTimestamps?: WordTimestamp[];

  /** Detected language if auto-detected */
  detectedLanguage?: string;

  /** Alternative transcriptions */
  alternatives?: TranscriptionAlternative[];

  /** Processing metadata */
  metadata: TranscriptionMetadata;

  /** Timestamp */
  timestamp: Date;
}

/**
 * Word timestamp information
 */
export interface WordTimestamp {
  word: string;
  startTime: number; // seconds
  endTime: number; // seconds
  confidence: number;
}

/**
 * Alternative transcription
 */
export interface TranscriptionAlternative {
  text: string;
  confidence: number;
}

/**
 * Transcription metadata
 */
export interface TranscriptionMetadata {
  modelId: string;
  processingTime: number; // milliseconds
  audioLength: number; // seconds
  realTimeFactor: number; // processingTime / audioLength
}

// ============================================================================
// STT Mode
// ============================================================================

/**
 * Transcription mode for speech-to-text
 * Reference: STTMode in STTComponent.swift
 */
export enum STTMode {
  /** Batch mode: Record all audio first, then transcribe */
  Batch = 'batch',

  /** Live mode: Transcribe audio in real-time */
  Live = 'live',
}

// ============================================================================
// STT Stream Handle
// ============================================================================

/**
 * Handle for managing STT streaming sessions
 */
export interface STTStreamHandle {
  /** Unique stream ID */
  id: number;

  /** Feed audio data to the stream */
  feed(audioData: string, sampleRate?: number): Promise<boolean>;

  /** Decode current buffer and get result */
  decode(): Promise<string>;

  /** Check if stream is ready for decoding */
  isReady(): Promise<boolean>;

  /** Check if endpoint detected */
  isEndpoint(): Promise<boolean>;

  /** Mark input as finished */
  finish(): Promise<void>;

  /** Reset the stream */
  reset(): Promise<void>;

  /** Destroy the stream */
  destroy(): Promise<void>;
}

// ============================================================================
// STT Component
// ============================================================================

/**
 * Speech-to-Text component
 *
 * Provides batch and streaming transcription capabilities.
 * Follows the same architecture as Swift SDK's STTComponent.
 *
 * @example
 * ```typescript
 * // Create component with configuration
 * const stt = new STTComponent({
 *   language: 'en-US',
 *   enablePunctuation: true,
 * });
 *
 * // Initialize
 * await stt.initialize();
 *
 * // Batch transcription
 * const result = await stt.transcribe(audioBase64);
 * console.log('Transcript:', result.text);
 *
 * // Streaming transcription
 * const stream = await stt.createStream();
 * stream.feed(audioChunk);
 * const partial = await stream.decode();
 * ```
 */
export class STTComponent {
  private configuration: STTConfiguration;
  private isModelLoaded = false;
  private modelPath?: string;
  private nativeModule: any;
  private eventEmitter?: NativeEventEmitter;

  constructor(configuration: Partial<STTConfiguration> = {}) {
    this.configuration = { ...DEFAULT_STT_CONFIG, ...configuration };
    this.nativeModule = NativeModules.RunAnywhere;
  }

  // ============================================================================
  // Lifecycle
  // ============================================================================

  /**
   * Initialize the STT component
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
    const initResult = await this.nativeModule.initialize(
      JSON.stringify({
        useGPU: this.configuration.useGPUIfAvailable,
      })
    );

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
   * Load an STT model
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

    // Check if loadSTTModel method is available
    if (typeof this.nativeModule.loadSTTModel !== 'function') {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native loadSTTModel method not available. Native module may not be properly built.'
      );
    }

    const configJson = JSON.stringify({
      language: this.configuration.language,
      sampleRate: this.configuration.sampleRate,
      enablePunctuation: this.configuration.enablePunctuation,
      enableDiarization: this.configuration.enableDiarization,
    });

    const result = await this.nativeModule.loadSTTModel(
      modelPath,
      modelType,
      configJson
    );

    if (!result) {
      const error = await this.nativeModule.getLastError?.() ?? 'Unknown error';
      throw new SDKError(
        SDKErrorCode.ModelLoadFailed,
        `Failed to load STT model: ${error}`
      );
    }

    this.isModelLoaded = true;
    this.modelPath = modelPath;

    // Emit model loaded event
    EventBus.emitModel({
      type: 'loadCompleted',
      modelId: modelPath,
    });
  }

  /**
   * Unload the STT model
   */
  async unloadModel(): Promise<void> {
    if (!this.nativeModule || !this.isModelLoaded) return;

    await this.nativeModule.unloadSTTModel();
    this.isModelLoaded = false;
    this.modelPath = undefined;
  }

  /**
   * Check if model is loaded
   */
  get modelLoaded(): boolean {
    return this.isModelLoaded;
  }

  /**
   * Check if streaming is supported
   */
  async supportsStreaming(): Promise<boolean> {
    if (!this.nativeModule) return false;

    // Check with native module
    // For now, sherpa-onnx supports streaming
    return true;
  }

  /**
   * Get recommended transcription mode
   */
  async getRecommendedMode(): Promise<STTMode> {
    const streaming = await this.supportsStreaming();
    return streaming ? STTMode.Live : STTMode.Batch;
  }

  /**
   * Cleanup resources
   */
  async cleanup(): Promise<void> {
    await this.unloadModel();
    if (this.nativeModule) {
      await this.nativeModule.destroy();
    }
  }

  // ============================================================================
  // Batch Transcription
  // ============================================================================

  /**
   * Transcribe audio data in batch mode
   *
   * @param audioData - Base64 encoded audio data (float32 PCM)
   * @param options - Optional STT options
   * @returns Transcription output
   */
  async transcribe(
    audioData: string,
    options?: Partial<STTOptions>
  ): Promise<STTOutput> {
    this.ensureReady();

    const mergedOptions: STTOptions = {
      language: options?.language ?? this.configuration.language,
      punctuation: options?.punctuation ?? this.configuration.enablePunctuation,
      diarization:
        options?.diarization ?? this.configuration.enableDiarization,
      wordTimestamps:
        options?.wordTimestamps ?? this.configuration.enableTimestamps,
      sampleRate: options?.sampleRate ?? this.configuration.sampleRate,
    };

    const startTime = Date.now();

    // Check if transcribe method is available
    if (typeof this.nativeModule.transcribe !== 'function') {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native transcribe method not available. Native module may not be properly built.'
      );
    }

    // Call native transcribe method
    const resultJson = await this.nativeModule.transcribe(
      audioData,
      mergedOptions.sampleRate,
      mergedOptions.language
    );

    const processingTime = Date.now() - startTime;

    // Parse result
    const result = JSON.parse(resultJson);

    // Estimate audio length from data size
    const audioLength = this.estimateAudioLength(audioData);

    return {
      text: result.text || '',
      confidence: result.confidence ?? 0.9,
      wordTimestamps: result.timestamps?.map((t: any) => ({
        word: t.word,
        startTime: t.startTime,
        endTime: t.endTime,
        confidence: t.confidence ?? 0.9,
      })),
      detectedLanguage: result.language,
      alternatives: result.alternatives?.map((a: any) => ({
        text: a.text,
        confidence: a.confidence,
      })),
      metadata: {
        modelId: this.modelPath ?? 'unknown',
        processingTime,
        audioLength,
        realTimeFactor: audioLength > 0 ? processingTime / 1000 / audioLength : 0,
      },
      timestamp: new Date(),
    };
  }

  /**
   * Transcribe with STTInput
   */
  async process(input: STTInput): Promise<STTOutput> {
    return this.transcribe(input.audioData, input.options);
  }

  // ============================================================================
  // Streaming Transcription
  // ============================================================================

  /**
   * Create a streaming STT session
   *
   * @param options - Optional configuration for the stream
   * @returns Stream handle for feeding audio and getting results
   */
  async createStream(options?: Partial<STTOptions>): Promise<STTStreamHandle> {
    this.ensureReady();

    const configJson = JSON.stringify({
      language: options?.language ?? this.configuration.language,
      sampleRate: options?.sampleRate ?? this.configuration.sampleRate,
    });

    const streamId = await this.nativeModule.createSTTStream(configJson);

    if (streamId < 0) {
      throw new SDKError(
        SDKErrorCode.StreamCreationFailed,
        'Failed to create STT stream'
      );
    }

    // Return stream handle
    const nativeModule = this.nativeModule;
    const sampleRate = options?.sampleRate ?? this.configuration.sampleRate;

    return {
      id: streamId,

      async feed(audioData: string, rate?: number): Promise<boolean> {
        return nativeModule.feedSTTAudio(streamId, audioData, rate ?? sampleRate);
      },

      async decode(): Promise<string> {
        return nativeModule.decodeSTT(streamId);
      },

      async isReady(): Promise<boolean> {
        // Stream is always ready to accept audio in sherpa-onnx
        return true;
      },

      async isEndpoint(): Promise<boolean> {
        // Check if endpoint detected
        // For now, return false - would need native method
        return false;
      },

      async finish(): Promise<void> {
        // Signal end of input
        // Native method: ra_stt_input_finished
      },

      async reset(): Promise<void> {
        // Reset stream state
        // Native method: ra_stt_reset_stream
      },

      async destroy(): Promise<void> {
        await nativeModule.destroySTTStream(streamId);
      },
    };
  }

  /**
   * Live transcription with real-time partial results
   *
   * @param audioStream - Async iterator of audio chunks (base64 encoded)
   * @param options - Optional STT options
   * @yields Transcription text (partial and final results)
   */
  async *liveTranscribe(
    audioStream: AsyncIterable<string>,
    options?: Partial<STTOptions>
  ): AsyncGenerator<string, void, unknown> {
    const stream = await this.createStream(options);

    try {
      for await (const audioChunk of audioStream) {
        // Feed audio chunk
        await stream.feed(audioChunk);

        // Try to decode and yield partial result
        const partial = await stream.decode();
        if (partial && partial !== '{}') {
          const result = JSON.parse(partial);
          if (result.text) {
            yield result.text;
          }
        }
      }

      // Final decode
      await stream.finish();
      const final = await stream.decode();
      if (final && final !== '{}') {
        const result = JSON.parse(final);
        if (result.text) {
          yield result.text;
        }
      }
    } finally {
      await stream.destroy();
    }
  }

  // ============================================================================
  // Event Subscriptions
  // ============================================================================

  /**
   * Subscribe to partial transcription events
   */
  onPartialResult(callback: (text: string) => void): () => void {
    if (!this.eventEmitter) {
      return () => {};
    }

    const subscription = this.eventEmitter.addListener(
      'onSTTPartial',
      (event: any) => {
        callback(event.text);
      }
    );

    return () => subscription.remove();
  }

  /**
   * Subscribe to final transcription events
   */
  onFinalResult(callback: (result: STTOutput) => void): () => void {
    if (!this.eventEmitter) {
      return () => {};
    }

    const subscription = this.eventEmitter.addListener(
      'onSTTFinal',
      (event: any) => {
        callback({
          text: event.text,
          confidence: event.confidence ?? 0.9,
          metadata: {
            modelId: this.modelPath ?? 'unknown',
            processingTime: event.processingTime ?? 0,
            audioLength: event.audioLength ?? 0,
            realTimeFactor: event.realTimeFactor ?? 0,
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
      'onSTTError',
      (event: any) => {
        callback(new SDKError(SDKErrorCode.TranscriptionFailed, event.message));
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
        'STT component not initialized'
      );
    }

    if (!this.isModelLoaded) {
      throw new SDKError(
        SDKErrorCode.ModelNotLoaded,
        'STT model not loaded'
      );
    }
  }

  private estimateAudioLength(base64Data: string): number {
    // Estimate audio length from base64 data size
    // Base64 encoding is ~4/3 of original size
    // Float32 PCM at 16kHz = 4 bytes per sample * 16000 samples/sec = 64000 bytes/sec
    const decodedSize = (base64Data.length * 3) / 4;
    const bytesPerSecond = 4 * this.configuration.sampleRate;
    return decodedSize / bytesPerSecond;
  }
}

// Export default instance creator
export function createSTTComponent(
  configuration?: Partial<STTConfiguration>
): STTComponent {
  return new STTComponent(configuration);
}
