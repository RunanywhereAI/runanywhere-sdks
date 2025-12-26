/**
 * STTCapability.ts
 *
 * Actor-based STT capability that owns model lifecycle and transcription.
 * Uses ManagedLifecycle for unified lifecycle + analytics handling.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/STT/STTCapability.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ServiceRegistry } from '../../Foundation/DependencyInjection/ServiceRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { STTConfiguration } from './STTConfiguration';
import type { STTInput, STTOutput, STTStreamResult } from './STTModels';
import type { STTService } from '../../Core/Protocols/Voice/STTService';
import type { STTTranscriptionResult } from '../../Core/Models/STT/STTTranscriptionResult';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';
import { ManagedLifecycle } from '../../Core/Capabilities/ManagedLifecycle';
import type { ComponentConfiguration } from '../../Core/Capabilities/CapabilityProtocols';

/**
 * STT Service Wrapper
 * Wrapper class to allow protocol-based STT service to work with BaseComponent
 */
export class STTServiceWrapper extends AnyServiceWrapper<STTService> {
  constructor(service: STTService | null = null) {
    super(service);
  }
}

/**
 * Speech-to-Text capability
 *
 * Uses `ManagedLifecycle` to handle model loading/unloading with automatic analytics tracking.
 */
export class STTCapability extends BaseComponent<STTServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.STT;

  private readonly sttConfiguration: STTConfiguration;
  private providerName: string = 'Unknown'; // Store the provider name for telemetry

  /**
   * Managed lifecycle with integrated event tracking
   * Matches iOS: private let managedLifecycle: ManagedLifecycle<STTService>
   */
  private readonly managedLifecycle: ManagedLifecycle<STTService>;

  // MARK: - Initialization

  constructor(configuration: STTConfiguration) {
    super(configuration);
    this.sttConfiguration = configuration;

    // Create managed lifecycle for STT with load/unload functions
    this.managedLifecycle = ManagedLifecycle.forSTT<STTService>(
      // Load resource function
      async (resourceId: string, _config: ComponentConfiguration | null) => {
        return await this.loadSTTService(resourceId);
      },
      // Unload resource function
      async (service: STTService) => {
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
   * Whether the service supports streaming transcription
   * Matches iOS: public var supportsStreaming: Bool { get async { ... } }
   */
  get supportsStreaming(): boolean {
    const service = this.managedLifecycle.currentService;
    return service?.supportsStreaming ?? false;
  }

  /**
   * Load a model by ID
   * Matches iOS: public func loadModel(_ modelId: String) async throws
   */
  async loadModel(modelId: string): Promise<void> {
    const sttService = await this.managedLifecycle.load(modelId);
    // Update BaseComponent's service reference for compatibility
    this.service = new STTServiceWrapper(sttService);
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
   * Load STT service for a given model ID
   * Called by ManagedLifecycle during load()
   */
  private async loadSTTService(modelId: string): Promise<STTService> {
    // Try to get a registered STT provider from central registry
    const provider = ServiceRegistry.shared.sttProvider(modelId);

    if (!provider) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'No STT service provider registered. Please register WhisperKitServiceProvider.register()'
      );
    }

    // Create service through provider
    const sttService = await provider.createSTTService(this.sttConfiguration);

    // Store provider name for telemetry
    this.providerName = provider.name;

    return sttService;
  }

  // MARK: - Service Creation (BaseComponent compatibility)

  protected override async createService(): Promise<STTServiceWrapper> {
    // If modelId is provided in config, load through managed lifecycle
    if (this.sttConfiguration.modelId) {
      await this.loadModel(this.sttConfiguration.modelId);
      if (!this.service) {
        throw new SDKError(
          SDKErrorCode.InvalidState,
          'Service was not created after loading model'
        );
      }
      return this.service;
    }

    // Fallback: create service without loading model (caller will load model separately)
    return new STTServiceWrapper(null);
  }

  protected override async performCleanup(): Promise<void> {
    await this.managedLifecycle.reset();
  }

  // MARK: - Public API

  /**
   * Transcribe audio data
   */
  public async transcribe(
    audioData: Buffer | Uint8Array,
    options?: Partial<STTInput['options']>
  ): Promise<STTOutput> {
    this.ensureReady();

    const input: STTInput = {
      audioData,
      format: 'pcm',
      language: options?.language ?? null,
      options: options as STTInput['options'] | null,
      validate: () => {
        if (!audioData || audioData.length === 0) {
          throw new SDKError(
            SDKErrorCode.ValidationFailed,
            'STTInput must contain audioData'
          );
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Process STT input
   */
  public async process(input: STTInput): Promise<STTOutput> {
    this.ensureReady();

    // Use managedLifecycle.requireService() for iOS parity
    const sttService = this.managedLifecycle.requireService();
    const modelId = this.managedLifecycle.resourceIdOrUnknown();

    // Validate input
    input.validate();

    // Build options
    const options = input.options ?? {
      language: this.sttConfiguration.language,
      detectLanguage: false,
      enablePunctuation: this.sttConfiguration.enablePunctuation,
      enableDiarization: this.sttConfiguration.enableDiarization,
      maxSpeakers: null,
      enableTimestamps: this.sttConfiguration.enableTimestamps,
      vocabularyFilter: this.sttConfiguration.vocabularyList,
      sampleRate: this.sttConfiguration.sampleRate,
      preferredFramework: null,
    };

    // Track processing time
    const startTime = Date.now();

    // Convert audio data to ArrayBuffer if needed
    let audioData: string | ArrayBuffer;
    if (Buffer.isBuffer(input.audioData)) {
      // Use slice to get a proper ArrayBuffer (Uint8Array.buffer returns ArrayBufferLike)
      audioData = input.audioData.buffer.slice(
        input.audioData.byteOffset,
        input.audioData.byteOffset + input.audioData.byteLength
      ) as ArrayBuffer;
    } else if (input.audioData instanceof Uint8Array) {
      // For Uint8Array, we need to slice to get ArrayBuffer
      audioData = input.audioData.buffer.slice(
        input.audioData.byteOffset,
        input.audioData.byteOffset + input.audioData.byteLength
      ) as ArrayBuffer;
    } else {
      audioData = input.audioData as ArrayBuffer;
    }

    // Transcribe using service from managed lifecycle
    const result: STTTranscriptionResult = await sttService.transcribe(
      audioData,
      {
        sampleRate: options.sampleRate,
        language: options.language,
        enablePunctuation: options.enablePunctuation,
      }
    );

    const processingTime = (Date.now() - startTime) / 1000; // seconds
    const audioLength =
      input.audioData.length / (this.sttConfiguration.sampleRate * 2); // Rough estimate

    // Create output
    return {
      text: result.transcript,
      confidence: result.confidence ?? 1.0,
      wordTimestamps:
        result.timestamps?.map((t) => ({
          word: t.word,
          startTime: t.startTime,
          endTime: t.endTime,
          confidence: t.confidence ?? result.confidence ?? 1.0,
        })) ?? null,
      detectedLanguage: result.language ?? null,
      alternatives:
        result.alternatives?.map((a) => ({
          text: a.transcript,
          confidence: a.confidence,
        })) ?? null,
      metadata: {
        modelId,
        processingTime,
        audioLength,
        realTimeFactor: audioLength > 0 ? processingTime / audioLength : 0,
      },
      timestamp: new Date(),
    };
  }

  /**
   * Stream transcription for real-time processing (legacy string-based API)
   * @deprecated Use streamTranscribeWithResults for structured results
   */
  public async *streamTranscribe(
    audioStream: AsyncIterable<Buffer | Uint8Array>,
    options?: Partial<STTInput['options']>
  ): AsyncGenerator<string, void, unknown> {
    this.ensureReady();

    // Use managedLifecycle.requireService() for iOS parity
    const sttService = this.managedLifecycle.requireService();

    // Build options
    const sttOptions = (options as STTInput['options'] | null) ?? {
      language: this.sttConfiguration.language,
      detectLanguage: false,
      enablePunctuation: this.sttConfiguration.enablePunctuation,
      enableDiarization: this.sttConfiguration.enableDiarization,
      maxSpeakers: null,
      enableTimestamps: this.sttConfiguration.enableTimestamps,
      vocabularyFilter: this.sttConfiguration.vocabularyList,
      sampleRate: this.sttConfiguration.sampleRate,
      preferredFramework: null,
    };

    // Convert stream to ArrayBuffer format
    const convertedStream: AsyncIterable<string | ArrayBuffer> =
      (async function* () {
        for await (const chunk of audioStream) {
          if (Buffer.isBuffer(chunk)) {
            yield chunk.buffer.slice(
              chunk.byteOffset,
              chunk.byteOffset + chunk.byteLength
            ) as ArrayBuffer;
          } else if (chunk instanceof Uint8Array) {
            yield chunk.buffer.slice(
              chunk.byteOffset,
              chunk.byteOffset + chunk.byteLength
            ) as ArrayBuffer;
          } else {
            yield chunk as ArrayBuffer;
          }
        }
      })();

    // Stream transcription (if supported)
    if (sttService.streamTranscribe) {
      let _partialText = '';
      const result = await sttService.streamTranscribe(
        convertedStream,
        {
          sampleRate: sttOptions.sampleRate,
          language: sttOptions.language,
        },
        (text: string, _confidence: number) => {
          // Yield partial results as they come
          _partialText = text;
        }
      );
      // Yield final result
      yield result.transcript;
    } else {
      // Fallback to batch mode - collect all chunks first
      const allChunks: ArrayBuffer[] = [];
      for await (const chunk of convertedStream) {
        allChunks.push(
          chunk instanceof ArrayBuffer
            ? chunk
            : (new TextEncoder().encode(chunk as string).buffer as ArrayBuffer)
        );
      }
      // Combine chunks
      const totalLength = allChunks.reduce(
        (acc, chunk) => acc + chunk.byteLength,
        0
      );
      const combined = new Uint8Array(totalLength);
      let offset = 0;
      for (const chunk of allChunks) {
        combined.set(new Uint8Array(chunk), offset);
        offset += chunk.byteLength;
      }
      const result = await sttService.transcribe(combined.buffer, {
        sampleRate: sttOptions.sampleRate,
        language: sttOptions.language,
      });
      yield result.transcript;
    }
  }

  /**
   * Stream transcription with structured results (partial and final)
   *
   * This method provides real-time transcription with:
   * - Partial results as audio is processed (isFinal: false)
   * - Final result when transcription completes (isFinal: true)
   * - Confidence scores for each result
   * - Proper error handling without breaking the stream
   *
   * @param audioStream - Async iterable of audio chunks (Buffer or Uint8Array)
   * @param options - Optional STT options (language, punctuation, etc.)
   * @returns AsyncGenerator yielding STTStreamResult objects
   *
   * @example
   * ```typescript
   * for await (const result of sttComponent.streamTranscribeWithResults(audioStream)) {
   *   if (result.isFinal) {
   *     console.log('Final:', result.text);
   *   } else {
   *     console.log('Partial:', result.text);
   *   }
   * }
   * ```
   */
  public async *streamTranscribeWithResults(
    audioStream: AsyncIterable<Buffer | Uint8Array>,
    options?: Partial<STTInput['options']>
  ): AsyncGenerator<STTStreamResult, STTOutput, unknown> {
    this.ensureReady();

    // Use managedLifecycle.requireService() for iOS parity
    const sttService = this.managedLifecycle.requireService();
    const modelId = this.managedLifecycle.resourceIdOrUnknown();

    // Build options
    const sttOptions = (options as STTInput['options'] | null) ?? {
      language: this.sttConfiguration.language,
      detectLanguage: false,
      enablePunctuation: this.sttConfiguration.enablePunctuation,
      enableDiarization: this.sttConfiguration.enableDiarization,
      maxSpeakers: null,
      enableTimestamps: this.sttConfiguration.enableTimestamps,
      vocabularyFilter: this.sttConfiguration.vocabularyList,
      sampleRate: this.sttConfiguration.sampleRate,
      preferredFramework: null,
    };

    // Convert stream to ArrayBuffer format
    const convertedStream: AsyncIterable<string | ArrayBuffer> =
      (async function* () {
        for await (const chunk of audioStream) {
          if (Buffer.isBuffer(chunk)) {
            yield chunk.buffer.slice(
              chunk.byteOffset,
              chunk.byteOffset + chunk.byteLength
            ) as ArrayBuffer;
          } else if (chunk instanceof Uint8Array) {
            yield chunk.buffer.slice(
              chunk.byteOffset,
              chunk.byteOffset + chunk.byteLength
            ) as ArrayBuffer;
          } else {
            yield chunk as ArrayBuffer;
          }
        }
      })();

    // Track processing time
    const startTime = Date.now();
    let totalAudioLength = 0;
    let _partialResultCount = 0;

    try {
      // Stream transcription (if supported)
      if (sttService.streamTranscribe) {
        // Partial results handler
        const partialResults: STTStreamResult[] = [];
        const onPartial = (text: string, confidence: number) => {
          const partialResult: STTStreamResult = {
            text,
            isFinal: false,
            confidence,
            timestamp: new Date(),
          };
          partialResults.push(partialResult);
          _partialResultCount++;
        };

        // Call streaming service
        const result = await sttService.streamTranscribe(
          convertedStream,
          {
            sampleRate: sttOptions.sampleRate,
            language: sttOptions.language,
          },
          onPartial
        );

        // Yield all partial results that were collected
        for (const partialResult of partialResults) {
          yield partialResult;
        }

        // Calculate processing metadata
        const processingTime = (Date.now() - startTime) / 1000; // seconds

        // Create final output
        const finalOutput: STTOutput = {
          text: result.transcript,
          confidence: result.confidence ?? 1.0,
          wordTimestamps:
            result.timestamps?.map((t) => ({
              word: t.word,
              startTime: t.startTime,
              endTime: t.endTime,
              confidence: t.confidence ?? result.confidence ?? 1.0,
            })) ?? null,
          detectedLanguage: result.language ?? null,
          alternatives:
            result.alternatives?.map((a) => ({
              text: a.transcript,
              confidence: a.confidence,
            })) ?? null,
          metadata: {
            modelId,
            processingTime,
            audioLength: totalAudioLength,
            realTimeFactor:
              totalAudioLength > 0 ? processingTime / totalAudioLength : 0,
          },
          timestamp: new Date(),
        };

        // Yield final result as STTStreamResult
        yield {
          text: result.transcript,
          isFinal: true,
          confidence: result.confidence ?? 1.0,
          timestamp: new Date(),
        };

        return finalOutput;
      } else {
        // Fallback to batch mode - collect all chunks first
        const allChunks: ArrayBuffer[] = [];
        for await (const chunk of convertedStream) {
          const arrayBuffer =
            chunk instanceof ArrayBuffer
              ? chunk
              : (new TextEncoder().encode(chunk as string)
                  .buffer as ArrayBuffer);
          allChunks.push(arrayBuffer);
          totalAudioLength +=
            arrayBuffer.byteLength / (this.sttConfiguration.sampleRate * 2); // Rough estimate
        }

        // Combine chunks
        const totalLength = allChunks.reduce(
          (acc, chunk) => acc + chunk.byteLength,
          0
        );
        const combined = new Uint8Array(totalLength);
        let offset = 0;
        for (const chunk of allChunks) {
          combined.set(new Uint8Array(chunk), offset);
          offset += chunk.byteLength;
        }

        // Transcribe combined audio
        const result = await sttService.transcribe(combined.buffer, {
          sampleRate: sttOptions.sampleRate,
          language: sttOptions.language,
        });

        const processingTime = (Date.now() - startTime) / 1000;

        // Create final output
        const finalOutput: STTOutput = {
          text: result.transcript,
          confidence: result.confidence ?? 1.0,
          wordTimestamps:
            result.timestamps?.map((t) => ({
              word: t.word,
              startTime: t.startTime,
              endTime: t.endTime,
              confidence: t.confidence ?? result.confidence ?? 1.0,
            })) ?? null,
          detectedLanguage: result.language ?? null,
          alternatives:
            result.alternatives?.map((a) => ({
              text: a.transcript,
              confidence: a.confidence,
            })) ?? null,
          metadata: {
            modelId,
            processingTime,
            audioLength: totalAudioLength,
            realTimeFactor:
              totalAudioLength > 0 ? processingTime / totalAudioLength : 0,
          },
          timestamp: new Date(),
        };

        // Yield only final result in batch mode
        yield {
          text: result.transcript,
          isFinal: true,
          confidence: result.confidence ?? 1.0,
          timestamp: new Date(),
        };

        return finalOutput;
      }
    } catch (error) {
      // Handle errors gracefully without breaking the stream
      throw new SDKError(
        SDKErrorCode.ProcessingFailed,
        `Streaming transcription failed: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }
}
