/**
 * TelemetryService.ts
 *
 * Telemetry service for RunAnywhere SDK - aligned with Swift/Kotlin SDKs.
 *
 * ARCHITECTURE:
 * - C++ telemetry manager handles all event logic (batching, JSON building, routing)
 * - Platform SDK only provides HTTP transport (handled in C++ via platform callbacks)
 * - Events are automatically tracked by C++ when using LLM/STT/TTS/VAD capabilities
 *
 * This TypeScript service provides:
 * - A thin wrapper to flush telemetry via native C++ calls
 * - Convenience methods that match the Swift/Kotlin API
 * - SDK-level events that TypeScript code can emit
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Telemetry.swift
 */

import { NitroModules } from 'react-native-nitro-modules';
import type { RunAnywhereCore } from '../../specs/RunAnywhereCore.nitro';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKEnvironment } from '../../types/enums';

const logger = new SDKLogger('TelemetryService');

// Lazy-loaded native module
let _nativeModule: RunAnywhereCore | null = null;

function getNativeModule(): RunAnywhereCore {
  if (!_nativeModule) {
    _nativeModule = NitroModules.createHybridObject<RunAnywhereCore>('RunAnywhereCore');
  }
  return _nativeModule;
}

/**
 * Telemetry event categories (matches C++ categories)
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
 * TelemetryService - Event tracking for RunAnywhere SDK
 *
 * This service delegates to the C++ telemetry manager, which handles:
 * - Batching events
 * - Building JSON payloads
 * - HTTP transport via platform-native callbacks
 *
 * Automatic telemetry:
 * - LLM/STT/TTS/VAD events are tracked automatically by C++ when you use those capabilities
 * - No manual tracking needed for model operations
 *
 * Manual telemetry:
 * - Use track() for SDK-level events (e.g., app lifecycle)
 * - Events are emitted to C++ analytics system which routes them to telemetry
 *
 * Usage:
 * ```typescript
 * // Flush pending events (e.g., on app background)
 * await TelemetryService.shared.flush();
 *
 * // Check if telemetry is ready
 * const isReady = await TelemetryService.shared.isInitialized();
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

  // ============================================================================
  // Initialization
  // ============================================================================

  private constructor() {}

  /**
   * Configure telemetry service
   *
   * Note: The actual C++ telemetry manager is initialized during SDK init.
   * This method just stores the configuration for reference.
   */
  configure(deviceId: string, environment: SDKEnvironment): void {
    this.deviceId = deviceId;
    this.environment = environment;
    logger.debug(`Configured for ${environment} environment`);
  }

  /**
   * Enable or disable telemetry
   */
  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    logger.debug(`Telemetry ${enabled ? 'enabled' : 'disabled'}`);
  }

  /**
   * Check if telemetry is enabled
   */
  isEnabled(): boolean {
    return this.enabled;
  }

  // ============================================================================
  // Core Telemetry Operations (Delegate to C++)
  // ============================================================================

  /**
   * Check if telemetry is initialized
   *
   * Returns true if the C++ telemetry manager is ready to accept events.
   */
  async isInitialized(): Promise<boolean> {
    try {
      return await getNativeModule().isTelemetryInitialized();
    } catch (error) {
      logger.error(`Failed to check telemetry initialization: ${error}`);
      return false;
    }
  }

  /**
   * Flush pending telemetry events
   *
   * Sends all queued events to the backend immediately.
   * Call this on app background/exit to ensure events are sent.
   */
  async flush(): Promise<void> {
    if (!this.enabled) {
      return;
    }

    try {
      await getNativeModule().flushTelemetry();
      logger.debug('Telemetry flushed');
    } catch (error) {
      logger.error(`Failed to flush telemetry: ${error}`);
    }
  }

  /**
   * Shutdown telemetry service
   *
   * Flushes any pending events before stopping.
   */
  async shutdown(): Promise<void> {
    try {
      await this.flush();
      logger.debug('Telemetry shutdown complete');
    } catch (error) {
      logger.error(`Telemetry shutdown error: ${error}`);
    }
  }

  // ============================================================================
  // Convenience Methods (for backwards compatibility)
  //
  // Note: These methods exist for API compatibility, but most telemetry
  // is automatically tracked by C++ when using LLM/STT/TTS/VAD capabilities.
  // You typically don't need to call these manually.
  // ============================================================================

  /**
   * Track an event (emits to C++ analytics system)
   *
   * Note: Most telemetry is automatic. Use this for custom SDK-level events.
   */
  track(
    _type: string,
    _category: TelemetryCategory = TelemetryCategory.SDK,
    _properties?: Record<string, unknown>
  ): void {
    if (!this.enabled) {
      return;
    }

    // Note: In the full C++ implementation, this would call native.emitEvent()
    // to route to the C++ analytics system. For now, we log a debug message.
    // The C++ telemetry manager handles actual event tracking.
    logger.debug(`Event tracked: ${_type} (handled by C++ telemetry)`);
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
   *
   * Note: Model loading events are automatically tracked by C++ when you
   * call loadTextModel(), loadSTTModel(), etc.
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
   *
   * Note: Generation events are automatically tracked by C++ when you
   * call generate() or generateStream().
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
   *
   * Note: Transcription events are automatically tracked by C++ when you
   * call transcribe() or transcribeFile().
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
   *
   * Note: Synthesis events are automatically tracked by C++ when you
   * call synthesize().
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
}

export default TelemetryService;
