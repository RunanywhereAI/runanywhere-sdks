/**
 * VADCapability.ts
 *
 * Voice Activity Detection capability for RunAnywhere React Native SDK.
 * Uses ManagedLifecycle for unified lifecycle + analytics handling.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/VAD/VADCapability.swift
 */

import {
  NativeEventEmitter,
  NativeModules,
  type EmitterSubscription,
} from 'react-native';
import {
  BaseComponent,
  AnyServiceWrapper,
  type ComponentConfiguration,
  type ComponentInput,
  type ComponentOutput,
} from '../../Core/Components/BaseComponent';
import { ManagedLifecycle } from '../../Core/Capabilities/ManagedLifecycle';
import type { ComponentConfiguration as CapabilityConfiguration } from '../../Core/Capabilities/CapabilityProtocols';
import { requireNativeModule } from '@runanywhere/native';
import { EventBus } from '../../Public/Events';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import { SDKComponent } from '../../types/enums';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('VADCapability');

// ============================================================================
// VAD Configuration
// ============================================================================

/**
 * Configuration for VAD component
 * Reference: VADConfiguration in VADComponent.swift
 */
export interface VADConfiguration extends ComponentConfiguration {
  /** Energy threshold for voice detection (0.0 to 1.0) */
  energyThreshold: number;

  /** Sample rate in Hz */
  sampleRate: number;

  /** Frame length in seconds */
  frameLength: number;

  /** Enable automatic calibration */
  enableAutoCalibration: boolean;

  /** Calibration multiplier (threshold = ambient noise * multiplier) */
  calibrationMultiplier: number;
}

/**
 * Default VAD configuration
 * Matches Swift SDK defaults
 */
export const DEFAULT_VAD_CONFIG: Omit<VADConfiguration, 'validate'> = {
  energyThreshold: 0.015,
  sampleRate: 16000,
  frameLength: 0.1,
  enableAutoCalibration: false,
  calibrationMultiplier: 2.0,
};

// ============================================================================
// VAD Input/Output Types
// ============================================================================

/**
 * Input for Voice Activity Detection
 * Reference: VADInput in VADComponent.swift
 */
export interface VADInput extends ComponentInput {
  /** Audio data (base64 encoded float32 PCM samples) */
  audioData: string;

  /** Sample rate in Hz */
  sampleRate?: number;

  /** Optional override for energy threshold */
  energyThresholdOverride?: number;
}

/**
 * Output from Voice Activity Detection
 * Reference: VADOutput in VADComponent.swift
 */
export interface VADOutput extends ComponentOutput {
  /** Whether speech is detected */
  isSpeech: boolean;

  /** Speech probability (0.0 to 1.0) */
  probability: number;

  /** Segments of detected speech */
  segments?: VADSegment[];

  /** Timestamp (required by ComponentOutput) */
  timestamp: Date;
}

/**
 * VAD segment with timing information
 * Reference: Speech segments in Swift SDK
 */
export interface VADSegment {
  /** Start time in seconds */
  start: number;

  /** End time in seconds */
  end: number;

  /** Probability/confidence of speech */
  probability: number;
}

/**
 * Speech activity event types
 * Reference: SpeechActivityEvent in VADComponent.swift
 */
export enum SpeechActivityEvent {
  Started = 'started',
  Ended = 'ended',
}

/**
 * VAD statistics for debugging
 * Reference: getStatistics() in Swift VADComponent
 */
export interface VADStatistics {
  /** Current energy level */
  current: number;

  /** Current threshold */
  threshold: number;

  /** Ambient noise level */
  ambient: number;

  /** Recent average energy */
  recentAvg: number;

  /** Recent maximum energy */
  recentMax: number;
}

// ============================================================================
// VAD Service Interface
// ============================================================================

/**
 * VAD Service interface matching Swift SDK's VADService protocol
 * Reference: VADService protocol in VADComponent.swift
 */
export interface VADService {
  /** Energy threshold for voice detection */
  energyThreshold: number;

  /** Sample rate of the audio */
  sampleRate: number;

  /** Frame length in seconds */
  frameLength: number;

  /** Whether speech is currently active */
  isSpeechActive: boolean;

  /** Initialize the service */
  initialize(): Promise<void>;

  /** Start processing */
  start(): void;

  /** Stop processing */
  stop(): void;

  /** Reset state */
  reset(): void;

  /** Process audio data */
  processAudioData(audioData: string, sampleRate?: number): Promise<boolean>;

  /** Pause VAD processing */
  pause(): void;

  /** Resume VAD processing */
  resume(): void;
}

// ============================================================================
// VAD Service Wrapper
// ============================================================================

/**
 * VAD Service Wrapper
 * Wrapper class to allow protocol-based VAD service to work with BaseComponent
 */
export class VADServiceWrapper extends AnyServiceWrapper<VADService> {
  constructor(service: VADService | null = null) {
    super(service);
  }
}

// ============================================================================
// VAD Capability
// ============================================================================

/**
 * Voice Activity Detection capability
 *
 * Uses `ManagedLifecycle` to handle model loading/unloading with automatic analytics tracking,
 * eliminating duplicate lifecycle management code.
 *
 * Features:
 * - Real-time speech detection
 * - Configurable energy threshold
 * - Automatic calibration support
 * - Speech segment detection
 * - Streaming API for continuous processing
 * - Event emission for speech activity changes
 *
 * Reference: VADCapability.swift
 */
export class VADCapability extends BaseComponent<VADServiceWrapper> {
  // ============================================================================
  // Static Properties
  // ============================================================================

  /** Component type identifier */
  static override componentType = SDKComponent.VAD;

  // ============================================================================
  // Instance Properties
  // ============================================================================

  private readonly vadConfiguration: VADConfiguration;
  private lastSpeechState: boolean = false;
  private isPaused: boolean = false;
  private eventEmitter?: NativeEventEmitter;
  private eventSubscriptions: Map<string, EmitterSubscription> = new Map();

  // Callbacks
  private onSpeechActivityCallback?: (event: SpeechActivityEvent) => void;

  /**
   * Managed lifecycle with integrated event tracking
   * Matches iOS: private let managedLifecycle: ManagedLifecycle<VADService>
   */
  private readonly managedLifecycle: ManagedLifecycle<VADService>;

  // ============================================================================
  // Constructor
  // ============================================================================

  constructor(configuration: VADConfiguration) {
    super(configuration);
    this.vadConfiguration = configuration;

    // Create managed lifecycle for VAD with load/unload functions
    this.managedLifecycle = ManagedLifecycle.forVAD<VADService>(
      // Load resource function
      async (resourceId: string, _config: CapabilityConfiguration | null) => {
        return await this.loadVADService(resourceId);
      },
      // Unload resource function
      async (service: VADService) => {
        service.stop();
        service.reset();
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
    const vadService = await this.managedLifecycle.load(modelId);
    // Update BaseComponent's service reference for compatibility
    this.service = new VADServiceWrapper(vadService);
  }

  /**
   * Unload the currently loaded model
   * Matches iOS: public func unload() async throws
   */
  async unloadModel(): Promise<void> {
    await this.managedLifecycle.unload();
    this.service = null;
  }

  // ============================================================================
  // Private Service Loading
  // ============================================================================

  /**
   * Load VAD service for a given model ID
   * Called by ManagedLifecycle during load()
   */
  private async loadVADService(modelId: string): Promise<VADService> {
    const nativeModule = requireNativeModule();

    // Create VAD service implementation
    const service: VADService = {
      energyThreshold: this.vadConfiguration.energyThreshold,
      sampleRate: this.vadConfiguration.sampleRate,
      frameLength: this.vadConfiguration.frameLength,
      isSpeechActive: false,

      initialize: async () => {
        // Load VAD model with the modelId
        const configJson = JSON.stringify(this.vadConfiguration);
        const success = await nativeModule.loadVADModel(modelId, configJson);

        if (!success) {
          throw new SDKError(
            SDKErrorCode.ModelLoadFailed,
            'Failed to load VAD model'
          );
        }

        // Setup event emitter for native events
        this.setupEventEmitter();
      },

      start: () => {
        // Start VAD processing if needed
      },

      stop: () => {
        // Stop VAD processing if needed
      },

      reset: () => {
        nativeModule.resetVAD();
        this.lastSpeechState = false;
      },

      processAudioData: async (
        audioData: string,
        sampleRate?: number
      ): Promise<boolean> => {
        if (this.isPaused) {
          return false;
        }

        const sr = sampleRate || this.vadConfiguration.sampleRate;
        const resultJson = await nativeModule.processVAD(audioData, sr);
        const result = JSON.parse(resultJson) as {
          isSpeech: boolean;
          probability: number;
        };

        // Update speech active state
        service.isSpeechActive = result.isSpeech;

        // Track state changes for callbacks
        if (result.isSpeech !== this.lastSpeechState) {
          this.lastSpeechState = result.isSpeech;
          const event = result.isSpeech
            ? SpeechActivityEvent.Started
            : SpeechActivityEvent.Ended;

          if (this.onSpeechActivityCallback) {
            this.onSpeechActivityCallback(event);
          }
        }

        return result.isSpeech;
      },

      pause: () => {
        this.isPaused = true;
      },

      resume: () => {
        this.isPaused = false;
      },
    };

    // Initialize the service
    await service.initialize();

    return service;
  }

  // ============================================================================
  // Service Creation (BaseComponent compatibility)
  // ============================================================================

  /**
   * Create the VAD service instance
   * If modelId is provided in config, loads through managed lifecycle
   */
  protected override async createService(): Promise<VADServiceWrapper> {
    // Fallback: create wrapper without loading model (caller will load model separately)
    return new VADServiceWrapper(null);
  }

  /**
   * Perform cleanup (BaseComponent override)
   * Delegates to ManagedLifecycle for proper cleanup
   */
  protected override async performCleanup(): Promise<void> {
    // Remove event listeners
    this.removeEventListeners();

    // Delegate to managed lifecycle
    await this.managedLifecycle.reset();

    this.lastSpeechState = false;
    this.isPaused = false;
  }

  // ============================================================================
  // Public API Methods
  // ============================================================================

  /**
   * Process audio input for voice activity detection
   * Reference: process() in Swift VADComponent
   *
   * @param input - VAD input with audio data
   * @returns VAD output with detection results
   */
  async process(input: VADInput): Promise<VADOutput> {
    this.ensureReady();

    try {
      input.validate();
    } catch (error) {
      throw error;
    }

    // Use managedLifecycle.requireService() for iOS parity
    const vadService = this.managedLifecycle.requireService();

    // Apply threshold override if provided
    if (input.energyThresholdOverride !== undefined) {
      vadService.energyThreshold = input.energyThresholdOverride;
    }

    // Process audio data
    const isSpeech = await vadService.processAudioData(
      input.audioData,
      input.sampleRate || this.vadConfiguration.sampleRate
    );

    return {
      isSpeech,
      probability: isSpeech ? 1.0 : 0.0, // Simplified for energy-based VAD
      timestamp: new Date(),
    };
  }

  /**
   * Detect speech segments in audio data
   * Reference: detectSpeech() in Swift VADComponent
   *
   * @param audioData - Base64 encoded audio data
   * @param sampleRate - Optional sample rate override
   * @returns Array of speech segments
   */
  async detectSegments(
    audioData: string,
    sampleRate?: number
  ): Promise<VADSegment[]> {
    this.ensureReady();

    try {
      const nativeModule = requireNativeModule();
      const sr = sampleRate || this.vadConfiguration.sampleRate;

      const segmentsJson = await nativeModule.detectVADSegments(audioData, sr);
      const segments = JSON.parse(segmentsJson) as Array<{
        startTime: number;
        endTime: number;
        confidence: number;
      }>;

      return segments.map((seg) => ({
        start: seg.startTime,
        end: seg.endTime,
        probability: seg.confidence,
      }));
    } catch (error) {
      throw new SDKError(
        SDKErrorCode.ProcessingFailed,
        `Segment detection failed: ${error instanceof Error ? error.message : 'Unknown error'}`
      );
    }
  }

  /**
   * Process audio stream
   * Reference: processAudioStream() in Swift VADComponent
   *
   * @param audioStream - Async generator of audio chunks
   * @param onSpeech - Callback when speech is detected
   * @returns Async generator of VAD outputs
   */
  async *streamProcess(
    audioStream: AsyncIterable<string>,
    onSpeech?: (output: VADOutput) => void
  ): AsyncGenerator<VADOutput, void, unknown> {
    this.ensureReady();

    for await (const audioChunk of audioStream) {
      const input: VADInput = {
        audioData: audioChunk,
        validate: () => {
          if (!audioChunk) {
            throw new SDKError(
              SDKErrorCode.ValidationFailed,
              'Audio data is required'
            );
          }
        },
      };

      const output = await this.process(input);

      if (output.isSpeech && onSpeech) {
        onSpeech(output);
      }

      yield output;
    }
  }

  // ============================================================================
  // State Management
  // ============================================================================

  /**
   * Reset VAD state
   * Reference: reset() in Swift VADComponent
   */
  resetVADState(): void {
    this.ensureReady();
    this.managedLifecycle.currentService?.reset();
  }

  /**
   * Pause VAD processing
   * Reference: pause() in Swift VADComponent
   */
  pause(): void {
    this.isPaused = true;
    this.managedLifecycle.currentService?.pause();
  }

  /**
   * Resume VAD processing
   * Reference: resume() in Swift VADComponent
   */
  resume(): void {
    this.isPaused = false;
    this.managedLifecycle.currentService?.resume();
  }

  /**
   * Start VAD processing
   * Reference: start() in Swift VADComponent
   */
  start(): void {
    this.managedLifecycle.currentService?.start();
  }

  /**
   * Stop VAD processing
   * Reference: stop() in Swift VADComponent
   */
  stop(): void {
    this.managedLifecycle.currentService?.stop();
  }

  // ============================================================================
  // Callbacks
  // ============================================================================

  /**
   * Set speech activity callback
   * Reference: setSpeechActivityCallback() in Swift VADComponent
   */
  setSpeechActivityCallback(
    callback: (event: SpeechActivityEvent) => void
  ): void {
    this.onSpeechActivityCallback = callback;
  }

  // ============================================================================
  // Calibration Methods
  // ============================================================================

  /**
   * Start calibration to measure ambient noise
   * Reference: startCalibration() in Swift VADComponent
   */
  async startCalibration(): Promise<void> {
    this.ensureReady();

    // Calibration would be implemented here
    // This typically involves collecting ambient noise samples
    // and automatically adjusting the threshold
    logger.info('Calibration started. Feed silent audio for best results.');
  }

  /**
   * Set calibration parameters
   * Reference: setCalibrationParameters() in Swift VADComponent
   *
   * @param multiplier - Threshold = ambient noise * multiplier
   */
  setCalibrationParameters(multiplier: number): void {
    if (multiplier < 1.5 || multiplier > 5.0) {
      throw new SDKError(
        SDKErrorCode.InvalidConfiguration,
        'Calibration multiplier must be between 1.5 and 5.0'
      );
    }

    this.vadConfiguration.calibrationMultiplier = multiplier;
  }

  /**
   * Get VAD statistics for debugging
   * Reference: getStatistics() in Swift VADComponent
   */
  async getStatistics(): Promise<VADStatistics | null> {
    if (!this.isReady) {
      return null;
    }

    // This would require native support to expose statistics
    // For now, return null as placeholder
    return null;
  }

  // ============================================================================
  // Getters
  // ============================================================================

  /**
   * Get current configuration
   */
  getConfiguration(): VADConfiguration {
    return { ...this.vadConfiguration };
  }

  /**
   * Get current speech state
   */
  isSpeechActive(): boolean {
    return this.lastSpeechState;
  }

  /**
   * Get underlying VAD service
   * Reference: getService() in Swift VADComponent
   */
  override getService(): VADServiceWrapper | null {
    const service = this.managedLifecycle.currentService;
    return service ? new VADServiceWrapper(service) : null;
  }

  // ============================================================================
  // Event Handling (Private)
  // ============================================================================

  /**
   * Setup event emitter for native events
   */
  private setupEventEmitter(): void {
    if (NativeModules.RunAnywhere) {
      this.eventEmitter = new NativeEventEmitter(NativeModules.RunAnywhere);

      // Subscribe to speech activity events
      const speechActivitySub = this.eventEmitter.addListener(
        'onSpeechActivity',
        (event: { activity: string }) => {
          const activityEvent =
            event.activity === 'started'
              ? SpeechActivityEvent.Started
              : SpeechActivityEvent.Ended;

          // Update internal state
          this.lastSpeechState = activityEvent === SpeechActivityEvent.Started;

          // Call callback if set
          if (this.onSpeechActivityCallback) {
            this.onSpeechActivityCallback(activityEvent);
          }

          // Emit to event bus - use appropriate VAD event type
          const voiceEventType =
            activityEvent === SpeechActivityEvent.Started
              ? 'vadDetected'
              : 'vadEnded';
          EventBus.getInstance().emitVoice({
            type: voiceEventType,
          });
        }
      );

      this.eventSubscriptions.set('speechActivity', speechActivitySub);
    }
  }

  /**
   * Remove all event listeners
   */
  private removeEventListeners(): void {
    this.eventSubscriptions.forEach((subscription) => {
      subscription.remove();
    });
    this.eventSubscriptions.clear();
  }
}

// ============================================================================
// Configuration Factory
// ============================================================================

/**
 * Create a VAD configuration with validation
 * Reference: VADConfiguration in Swift SDK
 *
 * @param config - Partial configuration to override defaults
 * @returns Complete VAD configuration with validate method
 */
export function createVADConfiguration(
  config: Partial<Omit<VADConfiguration, 'validate'>> = {}
): VADConfiguration {
  const fullConfig = {
    ...DEFAULT_VAD_CONFIG,
    ...config,
  };

  return {
    ...fullConfig,
    validate: () => {
      // Validate threshold range
      if (fullConfig.energyThreshold < 0 || fullConfig.energyThreshold > 1.0) {
        throw new SDKError(
          SDKErrorCode.InvalidConfiguration,
          'Energy threshold must be between 0 and 1.0. Recommended range: 0.01-0.05'
        );
      }

      // Warn if threshold is too low or too high
      if (fullConfig.energyThreshold < 0.002) {
        throw new SDKError(
          SDKErrorCode.InvalidConfiguration,
          `Energy threshold ${fullConfig.energyThreshold} is very low and may cause false positives. Recommended minimum: 0.002`
        );
      }
      if (fullConfig.energyThreshold > 0.1) {
        throw new SDKError(
          SDKErrorCode.InvalidConfiguration,
          `Energy threshold ${fullConfig.energyThreshold} is very high and may miss speech. Recommended maximum: 0.1`
        );
      }

      // Validate sample rate
      if (fullConfig.sampleRate <= 0 || fullConfig.sampleRate > 48000) {
        throw new SDKError(
          SDKErrorCode.InvalidConfiguration,
          'Sample rate must be between 1 and 48000 Hz'
        );
      }

      // Validate frame length
      if (fullConfig.frameLength <= 0 || fullConfig.frameLength > 1.0) {
        throw new SDKError(
          SDKErrorCode.InvalidConfiguration,
          'Frame length must be between 0 and 1 second'
        );
      }

      // Validate calibration multiplier
      if (
        fullConfig.calibrationMultiplier < 1.5 ||
        fullConfig.calibrationMultiplier > 5.0
      ) {
        throw new SDKError(
          SDKErrorCode.InvalidConfiguration,
          'Calibration multiplier must be between 1.5 and 5.0'
        );
      }
    },
  };
}

/**
 * Create VAD input with validation
 *
 * @param audioData - Base64 encoded audio data
 * @param options - Optional parameters
 * @returns VAD input with validate method
 */
export function createVADInput(
  audioData: string,
  options: {
    sampleRate?: number;
    energyThresholdOverride?: number;
  } = {}
): VADInput {
  return {
    audioData,
    sampleRate: options.sampleRate,
    energyThresholdOverride: options.energyThresholdOverride,
    validate: () => {
      if (!audioData) {
        throw new SDKError(
          SDKErrorCode.ValidationFailed,
          'Audio data is required'
        );
      }
      if (options.energyThresholdOverride !== undefined) {
        if (
          options.energyThresholdOverride < 0 ||
          options.energyThresholdOverride > 1.0
        ) {
          throw new SDKError(
            SDKErrorCode.ValidationFailed,
            'Energy threshold override must be between 0 and 1.0'
          );
        }
      }
    },
  };
}

// ============================================================================
// Factory Function
// ============================================================================

/**
 * Create a new VAD component instance
 * Convenience factory function
 *
 * @param configuration - VAD configuration (partial or complete)
 * @returns Configured VAD component
 */
export function createVADCapability(
  configuration: Partial<Omit<VADConfiguration, 'validate'>> = {}
): VADCapability {
  const config = createVADConfiguration(configuration);
  return new VADCapability(config);
}
