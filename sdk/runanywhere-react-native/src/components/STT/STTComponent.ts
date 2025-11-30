/**
 * STTComponent.ts
 *
 * Speech-to-Text component for RunAnywhere React Native SDK.
 * Follows the exact architecture and patterns from Swift SDK's STTComponent.swift.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift
 */

import { NativeModules } from 'react-native';
import { BaseComponent } from '../BaseComponent';
import type { ComponentConfiguration, ComponentInput, ComponentOutput } from '../BaseComponent';
import { EventBus } from '../../events';
import { SDKError, SDKErrorCode } from '../../errors';
import { AudioFormat, ComponentState, LLMFramework, SDKComponent } from '../../types/enums';
import type { STTOptions, STTResult } from '../../types';

// ============================================================================
// STT Configuration
// ============================================================================

/**
 * Configuration for STT component
 * Reference: STTConfiguration in STTComponent.swift
 *
 * Conforms to ComponentConfiguration protocol
 */
export interface STTConfiguration extends ComponentConfiguration {
  /** Component type */
  readonly componentType: SDKComponent;

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
export const DEFAULT_STT_CONFIGURATION: Omit<STTConfiguration, 'componentType' | 'validate'> = {
  language: 'en-US',
  sampleRate: 16000,
  enablePunctuation: true,
  enableDiarization: false,
  vocabularyList: [],
  maxAlternatives: 1,
  enableTimestamps: true,
  useGPUIfAvailable: true,
};

/**
 * Create STT configuration with defaults
 */
export function createSTTConfiguration(
  config: Partial<Omit<STTConfiguration, 'componentType' | 'validate'>>
): STTConfiguration {
  return {
    componentType: SDKComponent.STT,
    ...DEFAULT_STT_CONFIGURATION,
    ...config,
    validate(): void {
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
    },
  };
}

// ============================================================================
// STT Input/Output Types
// ============================================================================

/**
 * Input for Speech-to-Text
 * Reference: STTInput in STTComponent.swift
 */
export interface STTInput extends ComponentInput {
  /** Audio data (base64 encoded) */
  audioData: string;

  /** Audio buffer (alternative to data - for native buffers) */
  audioBuffer?: any;

  /** Audio format */
  format: AudioFormat;

  /** Language code override */
  language?: string;

  /** VAD output for context (future enhancement) */
  vadOutput?: any;

  /** Custom options override */
  options?: STTOptions;

  /** Validate input */
  validate(): void;
}

/**
 * Output from Speech-to-Text
 * Reference: STTOutput in STTComponent.swift
 */
export interface STTOutput extends ComponentOutput {
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
 * Reference: WordTimestamp in STTComponent.swift
 */
export interface WordTimestamp {
  word: string;
  startTime: number; // seconds
  endTime: number; // seconds
  confidence: number;
}

/**
 * Alternative transcription
 * Reference: TranscriptionAlternative in STTComponent.swift
 */
export interface TranscriptionAlternative {
  text: string;
  confidence: number;
}

/**
 * Transcription metadata
 * Reference: TranscriptionMetadata in STTComponent.swift
 */
export interface TranscriptionMetadata {
  modelId: string;
  processingTime: number; // milliseconds
  audioLength: number; // seconds
  realTimeFactor: number; // processingTime / audioLength
}

/**
 * STT transcription result from service
 * Reference: STTTranscriptionResult in STTComponent.swift
 */
export interface STTTranscriptionResult {
  transcript: string;
  confidence?: number;
  timestamps?: TimestampInfo[];
  language?: string;
  alternatives?: AlternativeTranscription[];
}

export interface TimestampInfo {
  word: string;
  startTime: number;
  endTime: number;
  confidence?: number;
}

export interface AlternativeTranscription {
  transcript: string;
  confidence: number;
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
// STT Service Protocol
// ============================================================================

/**
 * Protocol for speech-to-text services
 * Reference: STTService protocol in STTComponent.swift
 */
export interface STTService {
  /** Initialize the service with optional model path */
  initialize(modelPath?: string): Promise<void>;

  /** Transcribe audio data (batch mode) */
  transcribe(audioData: string, options: STTOptions): Promise<STTTranscriptionResult>;

  /** Stream transcription for real-time processing */
  streamTranscribe(
    audioStream: AsyncIterable<string>,
    options: STTOptions,
    onPartial: (text: string) => void
  ): Promise<STTTranscriptionResult>;

  /** Check if service is ready */
  isReady: boolean;

  /** Get current model identifier */
  currentModel: string | null;

  /** Whether this service supports live/streaming transcription */
  supportsStreaming: boolean;

  /** Cleanup resources */
  cleanup(): Promise<void>;
}

/**
 * Service wrapper for STT service
 * Reference: STTServiceWrapper in STTComponent.swift
 */
export class STTServiceWrapper {
  public wrappedService: STTService | null = null;

  constructor(service?: STTService) {
    this.wrappedService = service || null;
  }
}

// ============================================================================
// Native STT Service Implementation
// ============================================================================

/**
 * Native implementation of STTService using NativeRunAnywhere
 * This bridges to the C++ TurboModule
 */
class NativeSTTService implements STTService {
  private nativeModule: any;
  private _isReady = false;
  private _currentModel: string | null = null;

  constructor() {
    this.nativeModule = NativeModules.RunAnywhere;
  }

  async initialize(modelPath?: string): Promise<void> {
    if (!this.nativeModule) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Native module not available'
      );
    }

    // Create backend if needed
    const backendCreated = await this.nativeModule.createBackend('onnx');
    if (!backendCreated) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Failed to create ONNX backend'
      );
    }

    // Initialize backend
    const initResult = await this.nativeModule.initialize(
      JSON.stringify({ useGPU: true })
    );
    if (!initResult) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'Failed to initialize backend'
      );
    }

    this._isReady = true;
  }

  async transcribe(audioData: string, options: STTOptions): Promise<STTTranscriptionResult> {
    if (!this._isReady) {
      throw new SDKError(SDKErrorCode.ServiceNotInitialized, 'STT service not initialized');
    }

    const resultJson = await this.nativeModule.transcribe(
      audioData,
      options.sampleRate || 16000,
      options.language || 'en'
    );

    if (!resultJson) {
      throw new SDKError(SDKErrorCode.TranscriptionFailed, 'Transcription failed');
    }

    const result = JSON.parse(resultJson);

    return {
      transcript: result.text || '',
      confidence: result.confidence,
      timestamps: result.timestamps,
      language: result.language,
      alternatives: result.alternatives,
    };
  }

  async streamTranscribe(
    audioStream: AsyncIterable<string>,
    options: STTOptions,
    onPartial: (text: string) => void
  ): Promise<STTTranscriptionResult> {
    if (!this.supportsStreaming) {
      // Fallback to batch mode
      const chunks: string[] = [];
      for await (const chunk of audioStream) {
        chunks.push(chunk);
      }
      const combined = chunks.join(''); // Combine base64 chunks
      return this.transcribe(combined, options);
    }

    // Create stream
    const streamId = await this.nativeModule.createSTTStream(
      JSON.stringify(options)
    );

    if (streamId < 0) {
      throw new SDKError(SDKErrorCode.StreamCreationFailed, 'Failed to create STT stream');
    }

    try {
      // Feed audio chunks
      for await (const chunk of audioStream) {
        await this.nativeModule.feedSTTAudio(
          streamId,
          chunk,
          options.sampleRate || 16000
        );

        // Check for partial results
        const isReady = await this.nativeModule.isSTTReady?.(streamId);
        if (isReady) {
          const partialJson = await this.nativeModule.decodeSTT(streamId);
          if (partialJson) {
            const partial = JSON.parse(partialJson);
            if (partial.text) {
              onPartial(partial.text);
            }
          }
        }

        // Check for endpoint
        const isEndpoint = await this.nativeModule.isSTTEndpoint?.(streamId);
        if (isEndpoint) {
          break;
        }
      }

      // Signal input finished and get final result
      await this.nativeModule.finishSTTInput?.(streamId);

      const finalJson = await this.nativeModule.decodeSTT(streamId);
      if (!finalJson) {
        throw new SDKError(SDKErrorCode.TranscriptionFailed, 'No transcription result');
      }

      const result = JSON.parse(finalJson);

      return {
        transcript: result.text || '',
        confidence: result.confidence,
        timestamps: result.timestamps,
        language: result.language,
        alternatives: result.alternatives,
      };
    } finally {
      // Cleanup stream
      await this.nativeModule.destroySTTStream(streamId);
    }
  }

  get isReady(): boolean {
    return this._isReady;
  }

  get currentModel(): string | null {
    return this._currentModel;
  }

  get supportsStreaming(): boolean {
    // Check if native module has streaming methods
    return (
      this.nativeModule?.createSTTStream !== undefined &&
      this.nativeModule?.feedSTTAudio !== undefined &&
      this.nativeModule?.decodeSTT !== undefined
    );
  }

  async cleanup(): Promise<void> {
    if (this.nativeModule?.unloadSTTModel) {
      await this.nativeModule.unloadSTTModel();
    }
    this._isReady = false;
    this._currentModel = null;
  }

  async loadModel(modelPath: string, modelType: string = 'sherpa-onnx'): Promise<void> {
    const configJson = JSON.stringify({
      language: 'en-US',
      sampleRate: 16000,
      enablePunctuation: true,
    });

    const result = await this.nativeModule.loadSTTModel(
      modelPath,
      modelType,
      configJson
    );

    if (!result) {
      const error = await this.nativeModule.getLastError?.() || 'Unknown error';
      throw new SDKError(SDKErrorCode.ModelLoadFailed, `Failed to load STT model: ${error}`);
    }

    this._currentModel = modelPath;
  }
}

// ============================================================================
// STT Component
// ============================================================================

/**
 * Speech-to-Text component following the clean architecture
 *
 * Extends BaseComponent to provide STT capabilities with lifecycle management.
 * Matches the Swift SDK STTComponent implementation exactly.
 *
 * Reference: STTComponent in STTComponent.swift
 *
 * @example
 * ```typescript
 * // Create and initialize component
 * const config = createSTTConfiguration({
 *   language: 'en-US',
 *   enablePunctuation: true,
 * });
 *
 * const stt = new STTComponent(config);
 * await stt.initialize();
 *
 * // Batch transcription
 * const result = await stt.transcribe(audioDataBase64);
 * console.log('Transcript:', result.text);
 *
 * // Streaming transcription
 * const stream = stt.liveTranscribe(audioStream);
 * for await (const text of stream) {
 *   console.log('Partial:', text);
 * }
 * ```
 */
export class STTComponent extends BaseComponent<STTServiceWrapper> {
  // ============================================================================
  // Static Properties
  // ============================================================================

  /**
   * Component type identifier
   * Reference: componentType in STTComponent.swift
   */
  static override componentType = SDKComponent.STT;

  // ============================================================================
  // Instance Properties
  // ============================================================================

  private readonly sttConfiguration: STTConfiguration;
  private isModelLoaded = false;
  private modelPath?: string;

  // ============================================================================
  // Constructor
  // ============================================================================

  constructor(configuration: STTConfiguration) {
    super(configuration);
    this.sttConfiguration = configuration;
  }

  // ============================================================================
  // Service Creation
  // ============================================================================

  /**
   * Create the STT service
   *
   * Reference: createService() in STTComponent.swift
   */
  protected async createService(): Promise<STTServiceWrapper> {
    const modelId = this.sttConfiguration.modelId || 'unknown';
    const modelName = modelId;

    // Notify lifecycle manager (emit event)
    this.eventBus.emitModel({
      type: 'loadStarted',
      modelId: modelId,
    });

    try {
      // Create native STT service
      const sttService = new NativeSTTService();

      // Initialize service
      await sttService.initialize();

      // Load model if specified
      if (this.sttConfiguration.modelId) {
        await sttService.loadModel(this.sttConfiguration.modelId);
        this.modelPath = this.sttConfiguration.modelId;
        this.isModelLoaded = true;
      }

      // Wrap the service
      const wrapper = new STTServiceWrapper(sttService);

      // Notify successful load
      this.eventBus.emitModel({
        type: 'loadCompleted',
        modelId: modelId,
      });

      return wrapper;
    } catch (error) {
      this.eventBus.emitModel({
        type: 'loadFailed',
        modelId: modelId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  /**
   * Cleanup resources
   *
   * Reference: performCleanup() in STTComponent.swift
   */
  protected async performCleanup(): Promise<void> {
    await this.service?.wrappedService?.cleanup();
    this.isModelLoaded = false;
    this.modelPath = undefined;
  }

  // ============================================================================
  // Helper Properties
  // ============================================================================

  /**
   * Get wrapped STT service
   */
  private get sttService(): STTService | null {
    return this.service?.wrappedService || null;
  }

  // ============================================================================
  // Capabilities
  // ============================================================================

  /**
   * Whether the underlying service supports live/streaming transcription
   *
   * Reference: supportsStreaming in STTComponent.swift
   */
  get supportsStreaming(): boolean {
    return this.sttService?.supportsStreaming || false;
  }

  /**
   * Get the recommended transcription mode based on service capabilities
   *
   * Reference: recommendedMode in STTComponent.swift
   */
  get recommendedMode(): STTMode {
    return this.supportsStreaming ? STTMode.Live : STTMode.Batch;
  }

  // ============================================================================
  // Batch Transcription API
  // ============================================================================

  /**
   * Transcribe audio data in batch mode
   *
   * Reference: transcribe(_:options:) in STTComponent.swift
   *
   * @param audioData - Base64 encoded audio data (Float32 PCM or compatible format)
   * @param options - Transcription options
   * @returns Transcription output with text, confidence, and metadata
   */
  async transcribe(audioData: string, options?: Partial<STTOptions>): Promise<STTOutput> {
    this.ensureReady();

    const input: STTInput = {
      audioData,
      format: AudioFormat.WAV,
      language: options?.language,
      options: options ? this.mergeOptions(options) : this.createDefaultOptions(),
      validate: () => {
        if (!audioData || audioData.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'Audio data is required');
        }
      },
    };

    return this.process(input);
  }

  /**
   * Process STT input
   *
   * Reference: process(_:) in STTComponent.swift
   *
   * @param input - STT input with audio data and options
   * @returns STT output with transcription result
   */
  async process(input: STTInput): Promise<STTOutput> {
    this.ensureReady();

    if (!this.sttService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'STT service not available');
    }

    // Validate input
    input.validate();

    // Create options from input or use defaults
    const options = input.options || this.createDefaultOptions();

    // Get audio data
    const audioData = input.audioData;
    if (!audioData || audioData.length === 0) {
      throw new SDKError(SDKErrorCode.ValidationFailed, 'No audio data provided');
    }

    // Track processing time
    const startTime = Date.now();

    // Perform transcription
    const result = await this.sttService.transcribe(audioData, options);

    const processingTime = Date.now() - startTime;

    // Convert to strongly typed output
    const wordTimestamps = result.timestamps?.map((timestamp) => ({
      word: timestamp.word,
      startTime: timestamp.startTime,
      endTime: timestamp.endTime,
      confidence: timestamp.confidence || 0.9,
    }));

    const alternatives = result.alternatives?.map((alt) => ({
      text: alt.transcript,
      confidence: alt.confidence,
    }));

    // Calculate audio length (estimate based on data size and format)
    const audioLength = this.estimateAudioLength(audioData);

    const metadata: TranscriptionMetadata = {
      modelId: this.sttService.currentModel || 'unknown',
      processingTime,
      audioLength,
      realTimeFactor: audioLength > 0 ? processingTime / 1000 / audioLength : 0,
    };

    return {
      text: result.transcript,
      confidence: result.confidence || 0.9,
      wordTimestamps,
      detectedLanguage: result.language,
      alternatives,
      metadata,
      timestamp: new Date(),
    };
  }

  // ============================================================================
  // Live/Streaming Transcription API
  // ============================================================================

  /**
   * Live transcription with real-time partial results
   *
   * Reference: liveTranscribe(_:options:) in STTComponent.swift
   *
   * @param audioStream - Async sequence of audio data chunks (base64 encoded)
   * @param options - Transcription options
   * @returns Async stream of transcription text (partial and final results)
   */
  async *liveTranscribe(
    audioStream: AsyncIterable<string>,
    options?: Partial<STTOptions>
  ): AsyncGenerator<string, void, unknown> {
    this.ensureReady();

    if (!this.sttService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'STT service not available');
    }

    const mergedOptions = options ? this.mergeOptions(options) : this.createDefaultOptions();

    // Use service streaming
    const partials: string[] = [];

    const result = await this.sttService.streamTranscribe(
      audioStream,
      mergedOptions,
      (partial) => {
        partials.push(partial);
      }
    );

    // Yield all partials
    for (const partial of partials) {
      yield partial;
    }

    // Yield final result
    yield result.transcript;
  }

  /**
   * Stream transcription (alias for liveTranscribe)
   *
   * Reference: streamTranscribe(_:language:) in STTComponent.swift
   */
  streamTranscribe(
    audioStream: AsyncIterable<string>,
    language?: string
  ): AsyncGenerator<string, void, unknown> {
    return this.liveTranscribe(audioStream, { language });
  }

  // ============================================================================
  // Service Access
  // ============================================================================

  /**
   * Get service wrapper for compatibility
   *
   * Reference: getService() in STTComponent.swift
   */
  override getService(): STTServiceWrapper | null {
    return this.service;
  }

  /**
   * Get underlying STT service
   */
  getSTTService(): STTService | null {
    return this.sttService;
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  /**
   * Create default STT options from configuration
   */
  private createDefaultOptions(): STTOptions {
    return {
      language: this.sttConfiguration.language,
      punctuation: this.sttConfiguration.enablePunctuation,
      diarization: this.sttConfiguration.enableDiarization,
      wordTimestamps: this.sttConfiguration.enableTimestamps,
      sampleRate: this.sttConfiguration.sampleRate,
    };
  }

  /**
   * Merge user options with configuration defaults
   */
  private mergeOptions(options: Partial<STTOptions>): STTOptions {
    return {
      language: options.language || this.sttConfiguration.language,
      punctuation: options.punctuation ?? this.sttConfiguration.enablePunctuation,
      diarization: options.diarization ?? this.sttConfiguration.enableDiarization,
      wordTimestamps: options.wordTimestamps ?? this.sttConfiguration.enableTimestamps,
      sampleRate: options.sampleRate || this.sttConfiguration.sampleRate,
    };
  }

  /**
   * Estimate audio length from base64 data
   *
   * Reference: estimateAudioLength() in STTComponent.swift
   */
  private estimateAudioLength(base64Data: string): number {
    // Base64 encoding is ~4/3 of original size
    // Float32 PCM at given sample rate = 4 bytes per sample
    const decodedSize = (base64Data.length * 3) / 4;
    const bytesPerSecond = 4 * this.sttConfiguration.sampleRate;
    return decodedSize / bytesPerSecond;
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/**
 * Create an STT component with configuration
 *
 * @param config - Partial configuration (merged with defaults)
 * @returns Configured STT component
 */
export function createSTTComponent(
  config?: Partial<Omit<STTConfiguration, 'componentType' | 'validate'>>
): STTComponent {
  const configuration = createSTTConfiguration(config || {});
  return new STTComponent(configuration);
}

