/**
 * STTComponent.ts
 *
 * Speech-to-Text component following the clean architecture
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/STT/STTComponent.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ComponentState } from '../../Core/Models/Common/ComponentState';
import { ModuleRegistry } from '../../Core/ModuleRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { STTConfiguration } from './STTConfiguration';
import type { STTInput, STTOutput } from './STTModels';
import type { STTService } from '../../Core/Protocols/Voice/STTService';
import type { STTServiceProvider } from '../../Core/Protocols/Voice/STTServiceProvider';
import type { STTTranscriptionResult } from '../../Core/Models/STT/STTTranscriptionResult';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';

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
 * Speech-to-Text component
 */
export class STTComponent extends BaseComponent<STTServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.STT;

  private readonly sttConfiguration: STTConfiguration;
  private isModelLoaded = false;
  private modelPath: string | null = null;
  private providerName: string = 'Unknown'; // Store the provider name for telemetry

  // MARK: - Initialization

  constructor(configuration: STTConfiguration) {
    super(configuration);
    this.sttConfiguration = configuration;
  }

  // MARK: - Service Creation

  protected override async createService(): Promise<STTServiceWrapper> {
    const modelId = this.sttConfiguration.modelId ?? 'unknown';
    const modelName = modelId; // Could be enhanced to look up display name

    // Try to get a registered STT provider from central registry
    const provider = ModuleRegistry.shared.sttProvider(this.sttConfiguration.modelId);

    if (!provider) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        'No STT service provider registered. Please register WhisperKitServiceProvider.register()'
      );
    }

    // Check if model needs downloading
    if (this.sttConfiguration.modelId) {
      this.modelPath = this.sttConfiguration.modelId;
      // Provider should handle model management
    }

    try {
      // Create service through provider
      const sttService = await provider.createSTTService(this.sttConfiguration);

      // Store provider name for telemetry
      this.providerName = provider.name;

      // Wrap the service
      const wrapper = new STTServiceWrapper(sttService);

      // Service is already initialized by the provider
      this.isModelLoaded = true;

      return wrapper;
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.ComponentNotInitialized,
        `Failed to create STT service: ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  protected override async performCleanup(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.cleanup();
    }
    this.isModelLoaded = false;
    this.modelPath = null;
  }

  // MARK: - Public API

  /**
   * Transcribe audio data
   */
  public async transcribe(audioData: Buffer | Uint8Array, options?: Partial<STTInput['options']>): Promise<STTOutput> {
    this.ensureReady();

    const input: STTInput = {
      audioData,
      format: 'pcm',
      language: options?.language ?? null,
      options: options as STTInput['options'] | null,
      validate: () => {
        if (!audioData || audioData.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'STTInput must contain audioData');
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

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'STT service not available');
    }

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

    // Transcribe
    const result: STTTranscriptionResult = await this.service.wrappedService.transcribe(
      audioData,
      {
        sampleRate: options.sampleRate,
        language: options.language,
        enablePunctuation: options.enablePunctuation,
      }
    );

    const processingTime = (Date.now() - startTime) / 1000; // seconds
    const audioLength = input.audioData.length / (this.sttConfiguration.sampleRate * 2); // Rough estimate

    // Create output
    return {
      text: result.transcript,
      confidence: result.confidence ?? 1.0,
      wordTimestamps:
        result.segments?.map((t) => ({
          word: t.text,
          startTime: t.start,
          endTime: t.end,
          confidence: result.confidence,
        })) ?? null,
      detectedLanguage: result.language ?? null,
      alternatives: null, // STTTranscriptionResult doesn't have alternatives in the placeholder
      metadata: {
        modelId: this.service.wrappedService.currentModel ?? 'unknown',
        processingTime,
        audioLength,
        realTimeFactor: audioLength > 0 ? processingTime / audioLength : 0,
      },
      timestamp: new Date(),
    };
  }

  /**
   * Stream transcription for real-time processing
   */
  public async *streamTranscribe(
    audioStream: AsyncIterable<Buffer | Uint8Array>,
    options?: Partial<STTInput['options']>
  ): AsyncGenerator<string, void, unknown> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'STT service not available');
    }

    // Build options
    const sttOptions = options as STTInput['options'] | null ?? {
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
    const convertedStream: AsyncIterable<string | ArrayBuffer> = (async function* () {
      for await (const chunk of audioStream) {
        if (Buffer.isBuffer(chunk)) {
          yield chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength) as ArrayBuffer;
        } else if (chunk instanceof Uint8Array) {
          yield chunk.buffer.slice(chunk.byteOffset, chunk.byteOffset + chunk.byteLength) as ArrayBuffer;
        } else {
          yield chunk as ArrayBuffer;
        }
      }
    })();

    // Stream transcription (if supported)
    if (this.service.wrappedService.streamTranscribe) {
      let partialText = '';
      const result = await this.service.wrappedService.streamTranscribe(
        convertedStream,
        {
          sampleRate: sttOptions.sampleRate,
          language: sttOptions.language,
        },
        (text: string, confidence: number) => {
          // Yield partial results as they come
          partialText = text;
        }
      );
      // Yield final result
      yield result.transcript;
    } else {
      // Fallback to batch mode - collect all chunks first
      const allChunks: ArrayBuffer[] = [];
      for await (const chunk of convertedStream) {
        allChunks.push(chunk instanceof ArrayBuffer ? chunk : new TextEncoder().encode(chunk as string).buffer as ArrayBuffer);
      }
      // Combine chunks
      const totalLength = allChunks.reduce((acc, chunk) => acc + chunk.byteLength, 0);
      const combined = new Uint8Array(totalLength);
      let offset = 0;
      for (const chunk of allChunks) {
        combined.set(new Uint8Array(chunk), offset);
        offset += chunk.byteLength;
      }
      const result = await this.service.wrappedService.transcribe(combined.buffer, {
        sampleRate: sttOptions.sampleRate,
        language: sttOptions.language,
      });
      yield result.transcript;
    }
  }
}
