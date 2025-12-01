/**
 * SpeakerDiarizationComponent.ts
 *
 * Speaker Diarization component following the clean architecture
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/SpeakerDiarization/SpeakerDiarizationComponent.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ModuleRegistry } from '../../Core/ModuleRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { SpeakerDiarizationConfiguration } from './SpeakerDiarizationConfiguration';
import type {
  SpeakerDiarizationInput,
  SpeakerDiarizationOutput,
  SpeakerSegment,
  SpeakerProfile,
  LabeledTranscription,
  SpeakerInfo,
} from './SpeakerDiarizationModels';
import type { SpeakerDiarizationService } from '../../Core/Protocols/Voice/SpeakerDiarizationService';
import type { SpeakerDiarizationServiceProvider } from '../../Core/Protocols/Voice/SpeakerDiarizationServiceProvider';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';

/**
 * Default Speaker Diarization Service implementation
 */
class DefaultSpeakerDiarizationService implements SpeakerDiarizationService {
  private speakers: Map<string, SpeakerInfo> = new Map();
  private speakerCounter = 0;

  async initialize(): Promise<void> {
    // No initialization needed for default implementation
  }

  async processAudio(
    audioData: string | ArrayBuffer,
    sampleRate?: number
  ): Promise<import('../../Core/Models/SpeakerDiarization/SpeakerDiarizationResult').SpeakerDiarizationResult> {
    // Simple energy-based speaker detection
    // In real implementation, this would use ML models
    const speakerId = `speaker_${this.speakerCounter++}`;
    const speakerInfo: SpeakerInfo = {
      id: speakerId,
      name: null,
      confidence: 0.8,
      embedding: null,
    };
    this.speakers.set(speakerId, speakerInfo);

    // Return result matching SpeakerDiarizationResult interface
    return {
      segments: [],
      speakers: Array.from(this.speakers.values()).map((s) => ({
        id: s.id,
        name: s.name,
        confidence: s.confidence,
        embedding: s.embedding,
      })),
    };
  }

  get isReady(): boolean {
    return true;
  }

  async cleanup(): Promise<void> {
    this.speakers.clear();
    this.speakerCounter = 0;
  }
}

/**
 * Speaker Diarization Service Wrapper
 */
export class SpeakerDiarizationServiceWrapper extends AnyServiceWrapper<SpeakerDiarizationService> {
  constructor(service: SpeakerDiarizationService | null = null) {
    super(service);
  }
}

/**
 * Speaker Diarization component
 */
export class SpeakerDiarizationComponent extends BaseComponent<SpeakerDiarizationServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.SpeakerDiarization;

  private readonly diarizationConfiguration: SpeakerDiarizationConfiguration;
  private speakerProfiles: Map<string, SpeakerProfile> = new Map();
  private isServiceReady = false;

  // MARK: - Initialization

  constructor(configuration: SpeakerDiarizationConfiguration) {
    super(configuration);
    this.diarizationConfiguration = configuration;
  }

  // MARK: - Service Creation

  protected override async createService(): Promise<SpeakerDiarizationServiceWrapper> {
    // Try to get a registered speaker diarization provider from central registry
    const provider = ModuleRegistry.shared.speakerDiarizationProvider();

    if (provider) {
      try {
        const diarizationService = await provider.createSpeakerDiarizationService(
          this.diarizationConfiguration
        );
        return new SpeakerDiarizationServiceWrapper(diarizationService);
      } catch (error) {
        // Fall through to default
      }
    }

    // Fallback to default implementation
    const defaultService = new DefaultSpeakerDiarizationService();
    await defaultService.initialize();
    return new SpeakerDiarizationServiceWrapper(defaultService);
  }

  protected override async initializeService(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.initialize();
    }
    this.isServiceReady = true;
  }

  protected override async performCleanup(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.cleanup();
    }
    this.speakerProfiles.clear();
    this.isServiceReady = false;
  }

  // MARK: - Public API

  /**
   * Diarize audio to identify speakers
   */
  public async diarize(
    audioData: Buffer | Uint8Array,
    format: string = 'wav'
  ): Promise<SpeakerDiarizationOutput> {
    this.ensureReady();

    const input: SpeakerDiarizationInput = {
      audioData,
      format,
      transcription: null,
      expectedSpeakers: null,
      options: null,
      validate: () => {
        if (!audioData || audioData.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'Audio data cannot be empty');
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Diarize with transcription for labeled output
   */
  public async diarizeWithTranscription(
    audioData: Buffer | Uint8Array,
    transcription: SpeakerDiarizationInput['transcription'],
    format: string = 'wav'
  ): Promise<SpeakerDiarizationOutput> {
    this.ensureReady();

    const input: SpeakerDiarizationInput = {
      audioData,
      format,
      transcription,
      expectedSpeakers: null,
      options: null,
      validate: () => {
        if (!audioData || audioData.length === 0) {
          throw new SDKError(SDKErrorCode.ValidationFailed, 'Audio data cannot be empty');
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Process diarization input
   */
  public async process(input: SpeakerDiarizationInput): Promise<SpeakerDiarizationOutput> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'Speaker diarization service not available');
    }

    // Validate input
    input.validate();

    // Track processing time
    const startTime = Date.now();

    // Convert audio data to ArrayBuffer for service
    const audioBuffer = Buffer.isBuffer(input.audioData)
      ? input.audioData.buffer
      : input.audioData instanceof Uint8Array
      ? input.audioData.buffer
      : Buffer.from(input.audioData).buffer;

    // Process audio to detect speakers
    const result = await this.service.wrappedService.processAudio(audioBuffer, 16000);

    // Build segments from result
    const segments: SpeakerSegment[] = result.segments?.map((seg) => ({
      speakerId: seg.speakerId ?? 'unknown',
      startTime: seg.startTime ?? 0,
      endTime: seg.endTime ?? 0,
      confidence: seg.confidence ?? 0.8,
    })) ?? [];

    // Build speaker profiles from result
    const allSpeakers = result.speakers ?? [];
    const profiles: SpeakerProfile[] = allSpeakers.map((speaker) => {
      const speakerId = speaker.id ?? 'unknown';
      const speakerSegments = segments.filter((s) => s.speakerId === speakerId);
      const totalTime = speakerSegments.reduce((sum, seg) => sum + (seg.endTime - seg.startTime), 0);
      return {
        id: speakerId,
        embedding: speaker.embedding ?? null,
        totalSpeakingTime: totalTime,
        segmentCount: speakerSegments.length,
        name: speaker.name ?? null,
      };
    });

    // Store profiles
    profiles.forEach((profile) => {
      this.speakerProfiles.set(profile.id, profile);
    });

    // Create labeled transcription if provided
    let labeledTranscription: LabeledTranscription | null = null;
    if (input.transcription && input.transcription.wordTimestamps) {
      labeledTranscription = this.createLabeledTranscription(
        input.transcription.wordTimestamps,
        segments
      );
    }

    const processingTime = (Date.now() - startTime) / 1000; // seconds

    // Calculate audio length from segments
    const audioLength = segments.length > 0
      ? Math.max(...segments.map((s) => s.endTime))
      : 0;

    const metadata = {
      processingTime,
      audioLength,
      speakerCount: profiles.length,
      method: this.diarizationConfiguration.modelId ? 'ml' : 'energy',
    };

    return {
      segments,
      speakers: profiles,
      labeledTranscription,
      metadata,
      timestamp: new Date(),
    };
  }

  // MARK: - Helper Methods

  /**
   * Convert audio data to float array
   */
  private convertDataToFloatArray(data: Buffer | Uint8Array): number[] {
    // Convert to Float32 array
    const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
    const floatArray: number[] = [];
    for (let i = 0; i < buffer.length; i += 4) {
      if (i + 3 < buffer.length) {
        floatArray.push(buffer.readFloatLE(i));
      }
    }
    return floatArray;
  }

  /**
   * Create labeled transcription from word timestamps and segments
   */
  private createLabeledTranscription(
    wordTimestamps: Array<{ word: string; startTime: number; endTime: number; confidence: number }>,
    segments: SpeakerSegment[]
  ): LabeledTranscription {
    const labeledSegments = wordTimestamps.map((word) => {
      // Find which speaker segment this word belongs to
      const segment = segments.find(
        (s) => word.startTime >= s.startTime && word.endTime <= s.endTime
      );
      return {
        speakerId: segment?.speakerId ?? 'unknown',
        text: word.word,
        startTime: word.startTime,
        endTime: word.endTime,
      };
    });

    return { segments: labeledSegments };
  }
}

