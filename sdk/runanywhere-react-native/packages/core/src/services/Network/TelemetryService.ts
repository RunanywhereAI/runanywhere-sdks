/**
 * TelemetryService.ts
 *
 * Telemetry service for tracking SDK events and analytics.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Telemetry/TelemetryService.swift
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { HTTPService, SDKEnvironment } from './HTTPService';
import { APIEndpoints } from './APIEndpoints';

const logger = new SDKLogger('TelemetryService');

// React Native globals
declare const setTimeout: (callback: () => void, ms?: number) => number;
declare const setInterval: (callback: () => void, ms: number) => number;
declare const clearInterval: (id: number) => void;

/**
 * Telemetry event categories
 */
export enum TelemetryCategory {
  SDK = 'sdk',
  Model = 'model',
  LLM = 'llm',
  STT = 'stt',
  TTS = 'tts',
  VAD = 'vad',
  VoiceAgent = 'voice_agent',
  Error = 'error',
}

/**
 * Telemetry event interface
 */
export interface TelemetryEvent {
  type: string;
  category: TelemetryCategory;
  properties?: Record<string, unknown>;
  timestamp?: number;
  deviceId?: string;
}

/**
 * TelemetryService - Event tracking for RunAnywhere SDK
 *
 * Tracks SDK events and sends them to the backend for analytics.
 * Events are batched and sent periodically to minimize network calls.
 *
 * Usage:
 * ```typescript
 * TelemetryService.shared.track('model_loaded', TelemetryCategory.Model, {
 *   modelId: 'llama-3.2-1b',
 *   loadTimeMs: 1234,
 * });
 * ```
 */
export class TelemetryService {
  // ============================================================================
  // Singleton
  // ============================================================================

  private static _instance: TelemetryService | null = null;

  /**
   * Get shared TelemetryService instance
   */
  static get shared(): TelemetryService {
    if (!TelemetryService._instance) {
      TelemetryService._instance = new TelemetryService();
    }
    return TelemetryService._instance;
  }

  // ============================================================================
  // State
  // ============================================================================

  private enabled: boolean = true;
  private deviceId: string | null = null;
  private environment: SDKEnvironment = SDKEnvironment.Production;
  private eventQueue: TelemetryEvent[] = [];
  private flushTimer: number | null = null;

  // Configuration
  private readonly BATCH_SIZE = 10;
  private readonly FLUSH_INTERVAL_MS = 30000; // 30 seconds

  // ============================================================================
  // Initialization
  // ============================================================================

  private constructor() {}

  /**
   * Configure telemetry service
   */
  configure(deviceId: string, environment: SDKEnvironment): void {
    this.deviceId = deviceId;
    this.environment = environment;

    // Start flush timer
    this.startFlushTimer();

    logger.debug(`Configured for ${this.getEnvironmentName()}`);
  }

  /**
   * Enable or disable telemetry
   */
  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    logger.debug(`Telemetry ${enabled ? 'enabled' : 'disabled'}`);

    if (!enabled) {
      this.stopFlushTimer();
      this.eventQueue = [];
    } else {
      this.startFlushTimer();
    }
  }

  /**
   * Check if telemetry is enabled
   */
  isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * Shutdown telemetry service
   */
  async shutdown(): Promise<void> {
    this.stopFlushTimer();

    // Flush any remaining events
    if (this.eventQueue.length > 0) {
      await this.flush();
    }
  }

  // ============================================================================
  // Event Tracking
  // ============================================================================

  /**
   * Track an event
   *
   * @param type Event type (e.g., "model_loaded", "generation_started")
   * @param category Event category
   * @param properties Additional event properties
   */
  track(
    type: string,
    category: TelemetryCategory = TelemetryCategory.SDK,
    properties?: Record<string, unknown>
  ): void {
    if (!this.enabled) {
      return;
    }

    const event: TelemetryEvent = {
      type,
      category,
      properties,
      timestamp: Date.now(),
      deviceId: this.deviceId || undefined,
    };

    this.eventQueue.push(event);

    // Flush if batch size reached
    if (this.eventQueue.length >= this.BATCH_SIZE) {
      this.flush().catch((error) => {
        logger.debug(`Failed to flush events: ${error}`);
      });
    }
  }

  /**
   * Track SDK initialization
   */
  trackSDKInit(environment: string, success: boolean): void {
    this.track('sdk_initialized', TelemetryCategory.SDK, {
      environment,
      success,
      sdkVersion: '0.2.0',
      platform: 'react-native',
    });
  }

  /**
   * Track model loading
   */
  trackModelLoad(
    modelId: string,
    modelType: string,
    success: boolean,
    loadTimeMs?: number
  ): void {
    this.track('model_loaded', TelemetryCategory.Model, {
      modelId,
      modelType,
      success,
      loadTimeMs,
    });
  }

  /**
   * Track text generation
   */
  trackGeneration(
    modelId: string,
    promptTokens: number,
    completionTokens: number,
    latencyMs: number
  ): void {
    this.track('generation_completed', TelemetryCategory.LLM, {
      modelId,
      promptTokens,
      completionTokens,
      latencyMs,
    });
  }

  /**
   * Track transcription
   */
  trackTranscription(
    modelId: string,
    audioDurationMs: number,
    latencyMs: number
  ): void {
    this.track('transcription_completed', TelemetryCategory.STT, {
      modelId,
      audioDurationMs,
      latencyMs,
    });
  }

  /**
   * Track speech synthesis
   */
  trackSynthesis(
    voiceId: string,
    textLength: number,
    audioDurationMs: number,
    latencyMs: number
  ): void {
    this.track('synthesis_completed', TelemetryCategory.TTS, {
      voiceId,
      textLength,
      audioDurationMs,
      latencyMs,
    });
  }

  /**
   * Track error
   */
  trackError(
    errorCode: string,
    errorMessage: string,
    context?: Record<string, unknown>
  ): void {
    this.track('error', TelemetryCategory.Error, {
      errorCode,
      errorMessage,
      ...context,
    });
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  private async flush(): Promise<void> {
    if (this.eventQueue.length === 0) {
      return;
    }

    // Take events from queue
    const events = this.eventQueue.splice(0, this.BATCH_SIZE);

    try {
      const endpoint = this.getTelemetryEndpoint();
      await HTTPService.shared.post(endpoint, { events });
      logger.debug(`Flushed ${events.length} telemetry events`);
    } catch (error) {
      // Re-queue events on failure (with limit to prevent memory issues)
      if (this.eventQueue.length < 100) {
        this.eventQueue.unshift(...events);
      }
      logger.debug(`Failed to send telemetry: ${error}`);
    }
  }

  private getTelemetryEndpoint(): string {
    return this.environment === SDKEnvironment.Development
      ? APIEndpoints.DEV_TELEMETRY
      : APIEndpoints.TELEMETRY;
  }

  private getEnvironmentName(): string {
    switch (this.environment) {
      case SDKEnvironment.Development:
        return 'development';
      case SDKEnvironment.Staging:
        return 'staging';
      case SDKEnvironment.Production:
        return 'production';
      default:
        return 'unknown';
    }
  }

  private startFlushTimer(): void {
    if (this.flushTimer) {
      return;
    }

    this.flushTimer = setInterval(() => {
      this.flush().catch((error) => {
        logger.debug(`Periodic flush failed: ${error}`);
      });
    }, this.FLUSH_INTERVAL_MS);
  }

  private stopFlushTimer(): void {
    if (this.flushTimer) {
      clearInterval(this.flushTimer);
      this.flushTimer = null;
    }
  }
}

export default TelemetryService;
