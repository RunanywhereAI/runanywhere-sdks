/**
 * SpeakerDiarizationCapability.ts
 *
 * Speaker Diarization capability for RunAnywhere React Native SDK.
 * Uses ManagedLifecycle for unified lifecycle + analytics handling.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/SpeakerDiarization/SpeakerDiarizationCapability.swift
 */

import {
  BaseComponent,
  AnyServiceWrapper,
} from '../../Core/Components/BaseComponent';
import { ManagedLifecycle } from '../../Core/Capabilities/ManagedLifecycle';
import type { ComponentConfiguration as CapabilityConfiguration } from '../../Core/Capabilities/CapabilityProtocols';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ServiceRegistry } from '../../Foundation/DependencyInjection/ServiceRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { SpeakerDiarizationConfiguration } from './SpeakerDiarizationConfiguration';
import type {
  SpeakerDiarizationInput,
  SpeakerDiarizationOutput,
  SpeakerSegment,
  SpeakerProfile,
  LabeledTranscription,
} from './SpeakerDiarizationModels';
import type { SpeakerDiarizationService } from '../../Core/Protocols/Voice/SpeakerDiarizationService';

// ============================================================================
// Speaker Diarization Not Implemented Error
// ============================================================================

/**
 * Error thrown when speaker diarization is used without a provider.
 *
 * Speaker diarization requires a platform-specific implementation:
 * - iOS uses FluidAudio (iOS-only library)
 * - React Native does not have a built-in diarization provider
 *
 * To use speaker diarization, register a SpeakerDiarizationProvider via ServiceRegistry.
 */
export class SpeakerDiarizationNotAvailableError extends Error {
  constructor() {
    super(
      'Speaker diarization is not available. ' +
        'No SpeakerDiarizationProvider has been registered. ' +
        'iOS uses FluidAudio (platform-specific). ' +
        'For React Native, consider using an ONNX-based diarization model or a cloud service.'
    );
    this.name = 'SpeakerDiarizationNotAvailableError';
  }
}

// ============================================================================
// Speaker Diarization Service Wrapper
// ============================================================================

/**
 * Speaker Diarization Service Wrapper
 * Wrapper class to allow protocol-based service to work with BaseComponent
 */
export class SpeakerDiarizationServiceWrapper extends AnyServiceWrapper<SpeakerDiarizationService> {
  constructor(service: SpeakerDiarizationService | null = null) {
    super(service);
  }
}

// ============================================================================
// Speaker Diarization Capability
// ============================================================================

/**
 * Speaker Diarization capability
 *
 * Uses `ManagedLifecycle` to handle model loading/unloading with automatic analytics tracking,
 * eliminating duplicate lifecycle management code.
 *
 * Features:
 * - Speaker identification and tracking
 * - Multi-speaker support with configurable limits
 * - Speaker embedding extraction
 * - Transcription labeling with speaker IDs
 * - Automatic analytics tracking
 *
 * Reference: SpeakerDiarizationCapability.swift
 */
export class SpeakerDiarizationCapability extends BaseComponent<SpeakerDiarizationServiceWrapper> {
  // ============================================================================
  // Static Properties
  // ============================================================================

  /** Component type identifier */
  static override componentType = SDKComponent.SpeakerDiarization;

  // ============================================================================
  // Instance Properties
  // ============================================================================

  private readonly diarizationConfiguration: SpeakerDiarizationConfiguration;
  private speakerProfiles: Map<string, SpeakerProfile> = new Map();

  /**
   * Managed lifecycle with integrated event tracking
   * Matches iOS: private let managedLifecycle: ManagedLifecycle<SpeakerDiarizationService>
   */
  private readonly managedLifecycle: ManagedLifecycle<SpeakerDiarizationService>;

  // ============================================================================
  // Constructor
  // ============================================================================

  constructor(configuration: SpeakerDiarizationConfiguration) {
    super(configuration);
    this.diarizationConfiguration = configuration;

    // Create managed lifecycle for SpeakerDiarization with load/unload functions
    this.managedLifecycle =
      ManagedLifecycle.forSpeakerDiarization<SpeakerDiarizationService>(
        // Load resource function
        async (resourceId: string, _config: CapabilityConfiguration | null) => {
          return await this.loadDiarizationService(resourceId);
        },
        // Unload resource function
        async (service: SpeakerDiarizationService) => {
          await service.cleanup();
        }
      );

    // Configure lifecycle with our configuration
    this.managedLifecycle.configure(configuration as CapabilityConfiguration);
  }

  // ============================================================================
  // Model Lifecycle (ModelLoadableCapability Protocol)
  // All lifecycle operations are delegated to ManagedLifecycle which handles analytics automatically
  // ============================================================================

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
   * Load a model by ID
   * Matches iOS: public func loadModel(_ modelId: String) async throws
   */
  async loadModel(modelId: string): Promise<void> {
    const diarizationService = await this.managedLifecycle.load(modelId);
    // Update BaseComponent's service reference for compatibility
    this.service = new SpeakerDiarizationServiceWrapper(diarizationService);
  }

  /**
   * Unload the currently loaded model
   * Matches iOS: public func unload() async throws
   */
  async unloadModel(): Promise<void> {
    await this.managedLifecycle.unload();
    this.service = null;
    this.speakerProfiles.clear();
  }

  // ============================================================================
  // Private Service Loading
  // ============================================================================

  /**
   * Load SpeakerDiarization service for a given model ID
   * Called by ManagedLifecycle during load()
   *
   * @throws SpeakerDiarizationNotAvailableError if no provider is registered
   */
  private async loadDiarizationService(
    modelId: string
  ): Promise<SpeakerDiarizationService> {
    // Try to get a registered speaker diarization provider from central registry
    const provider = ServiceRegistry.shared.speakerDiarizationProvider();

    if (!provider) {
      // No provider registered - speaker diarization requires platform-specific implementation
      throw new SpeakerDiarizationNotAvailableError();
    }

    // Use the registered provider to create the service
    const diarizationService = await provider.createSpeakerDiarizationService(
      this.diarizationConfiguration
    );
    await diarizationService.initialize(modelId);
    return diarizationService;
  }

  // ============================================================================
  // Service Creation (BaseComponent compatibility)
  // ============================================================================

  /**
   * Create the SpeakerDiarization service instance
   * If modelId is provided in config, loads through managed lifecycle
   */
  protected override async createService(): Promise<SpeakerDiarizationServiceWrapper> {
    // Fallback: create wrapper without loading model (caller will load model separately)
    return new SpeakerDiarizationServiceWrapper(null);
  }

  /**
   * Perform cleanup (BaseComponent override)
   * Delegates to ManagedLifecycle for proper cleanup
   */
  protected override async performCleanup(): Promise<void> {
    // Delegate to managed lifecycle
    await this.managedLifecycle.reset();

    this.speakerProfiles.clear();
  }

  // ============================================================================
  // Public API Methods
  // ============================================================================

  /**
   * Diarize audio to identify speakers
   * Reference: processAudio() in Swift SpeakerDiarizationCapability
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
          throw new SDKError(
            SDKErrorCode.ValidationFailed,
            'Audio data cannot be empty'
          );
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
          throw new SDKError(
            SDKErrorCode.ValidationFailed,
            'Audio data cannot be empty'
          );
        }
      },
      timestamp: new Date(),
    };

    return await this.process(input);
  }

  /**
   * Process diarization input
   * Reference: processAudio() in Swift SpeakerDiarizationCapability
   */
  public async process(
    input: SpeakerDiarizationInput
  ): Promise<SpeakerDiarizationOutput> {
    this.ensureReady();

    // Use managedLifecycle.requireService() for iOS parity
    const diarizationService = this.managedLifecycle.requireService();

    // Validate input
    input.validate();

    // Track processing time
    const startTime = Date.now();

    // Convert audio data to ArrayBuffer for service
    const audioBuffer: ArrayBuffer = Buffer.isBuffer(input.audioData)
      ? (input.audioData.buffer.slice(
          input.audioData.byteOffset,
          input.audioData.byteOffset + input.audioData.byteLength
        ) as ArrayBuffer)
      : input.audioData instanceof Uint8Array
        ? (input.audioData.buffer.slice(
            input.audioData.byteOffset,
            input.audioData.byteOffset + input.audioData.byteLength
          ) as ArrayBuffer)
        : (Buffer.from(input.audioData).buffer as ArrayBuffer);

    // Process audio to detect speakers
    const result = await diarizationService.processAudio(audioBuffer, 16000);

    // Build segments from result
    const segments: SpeakerSegment[] =
      result.segments?.map((seg) => ({
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
      const totalTime = speakerSegments.reduce(
        (sum, seg) => sum + (seg.endTime - seg.startTime),
        0
      );
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
    const audioLength =
      segments.length > 0 ? Math.max(...segments.map((s) => s.endTime)) : 0;

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

  // ============================================================================
  // Speaker Management
  // ============================================================================

  /**
   * Get all identified speakers
   * Reference: getAllSpeakers() in Swift SpeakerDiarizationCapability
   */
  getAllSpeakers(): SpeakerProfile[] {
    return Array.from(this.speakerProfiles.values());
  }

  /**
   * Update speaker name
   * Reference: updateSpeakerName() in Swift SpeakerDiarizationCapability
   */
  updateSpeakerName(speakerId: string, name: string): void {
    const profile = this.speakerProfiles.get(speakerId);
    if (profile) {
      // Create updated profile with new name
      const updatedProfile: SpeakerProfile = {
        ...profile,
        name,
      };
      this.speakerProfiles.set(speakerId, updatedProfile);
    }
  }

  /**
   * Reset the diarization state
   * Clears all speaker profiles and resets tracking
   * Reference: reset() in Swift SpeakerDiarizationCapability
   */
  resetDiarizationState(): void {
    this.speakerProfiles.clear();
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /**
   * Create labeled transcription from word timestamps and segments
   */
  private createLabeledTranscription(
    wordTimestamps: Array<{
      word: string;
      startTime: number;
      endTime: number;
      confidence: number;
    }>,
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

  // ============================================================================
  // Getters
  // ============================================================================

  /**
   * Get current configuration
   */
  getConfiguration(): SpeakerDiarizationConfiguration {
    return this.diarizationConfiguration;
  }

  /**
   * Get underlying diarization service
   */
  override getService(): SpeakerDiarizationServiceWrapper | null {
    const service = this.managedLifecycle.currentService;
    return service ? new SpeakerDiarizationServiceWrapper(service) : null;
  }
}
