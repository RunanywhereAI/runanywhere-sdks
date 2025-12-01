/**
 * WakeWordComponent.ts
 *
 * Wake Word Detection component following the clean architecture
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Components/WakeWord/WakeWordComponent.swift
 */

import { BaseComponent } from '../../Core/Components/BaseComponent';
import { SDKComponent } from '../../Core/Models/Common/SDKComponent';
import { ModuleRegistry } from '../../Core/ModuleRegistry';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { WakeWordConfiguration } from './WakeWordConfiguration';
import type { WakeWordInput, WakeWordOutput } from './WakeWordModels';
import type { WakeWordService } from '../../Core/Protocols/Voice/WakeWordService';
import type { WakeWordServiceProvider } from '../../Core/Protocols/Voice/WakeWordServiceProvider';
import { AnyServiceWrapper } from '../../Core/Components/BaseComponent';

/**
 * Default Wake Word Service implementation
 */
class DefaultWakeWordService implements WakeWordService {
  private _isListening = false;

  async initialize(): Promise<void> {
    // No initialization needed for default implementation
  }

  async processAudio(
    audioData: string | ArrayBuffer,
    sampleRate?: number,
    onWakeWord?: (word: string, confidence: number) => void
  ): Promise<{ detected: boolean; word?: string; confidence?: number }> {
    // Default implementation always returns false (no detection)
    return { detected: false };
  }

  get isReady(): boolean {
    return true;
  }

  async cleanup(): Promise<void> {
    this._isListening = false;
  }
}

/**
 * Wake Word Service Wrapper
 */
export class WakeWordServiceWrapper extends AnyServiceWrapper<WakeWordService> {
  constructor(service: WakeWordService | null = null) {
    super(service);
  }
}

/**
 * Wake Word Detection component
 */
export class WakeWordComponent extends BaseComponent<WakeWordServiceWrapper> {
  // MARK: - Properties

  public static override componentType: SDKComponent = SDKComponent.WakeWord;

  private readonly wakeWordConfiguration: WakeWordConfiguration;
  private isDetecting = false;

  // MARK: - Initialization

  constructor(configuration: WakeWordConfiguration) {
    super(configuration);
    this.wakeWordConfiguration = configuration;
  }

  // MARK: - Service Creation

  protected override async createService(): Promise<WakeWordServiceWrapper> {
    // Try to get a registered wake word provider from central registry
    const provider = ModuleRegistry.shared.wakeWordProvider();

    if (provider) {
      try {
        const wakeWordService = await provider.createWakeWordService(this.wakeWordConfiguration);
        return new WakeWordServiceWrapper(wakeWordService);
      } catch (error) {
        // Fall through to default
      }
    }

    // Fallback to default implementation
    const defaultService = new DefaultWakeWordService();
    await defaultService.initialize();
    return new WakeWordServiceWrapper(defaultService);
  }

  protected override async initializeService(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.initialize();
    }
  }

  protected override async performCleanup(): Promise<void> {
    if (this.service?.wrappedService) {
      await this.service.wrappedService.cleanup();
    }
    this.isDetecting = false;
  }

  // MARK: - Public API

  /**
   * Process audio input for wake word detection
   */
  public async process(input: WakeWordInput): Promise<WakeWordOutput> {
    this.ensureReady();

    if (!this.service?.wrappedService) {
      throw new SDKError(SDKErrorCode.ComponentNotReady, 'Wake word service not available');
    }

    // Validate input
    input.validate();

    // Track processing time
    const startTime = Date.now();

    // Convert float array to ArrayBuffer for service
    const audioBuffer = new Float32Array(input.audioBuffer).buffer;

    // Process audio buffer
    const result = await this.service.wrappedService.processAudio(
      audioBuffer,
      this.wakeWordConfiguration.sampleRate
    );

    const processingTime = (Date.now() - startTime) / 1000; // seconds

    // Create output
    return {
      detected: result.detected,
      wakeWord: result.detected ? (result.word ?? this.wakeWordConfiguration.wakeWords[0]) : null,
      confidence: result.detected ? (result.confidence ?? this.wakeWordConfiguration.confidenceThreshold) : 0.0,
      metadata: {
        processingTime,
        bufferSize: input.audioBuffer.length,
        sampleRate: this.wakeWordConfiguration.sampleRate,
      },
      timestamp: new Date(),
    };
  }
}

