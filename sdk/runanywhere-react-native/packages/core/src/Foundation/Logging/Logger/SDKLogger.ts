/**
 * SDKLogger.ts
 *
 * Centralized logging utility for SDK components.
 * Provides structured logging with category-based filtering and metadata support.
 *
 * Matches iOS: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
 *
 * Usage:
 *   // Use convenience loggers
 *   SDKLogger.shared.info('SDK initialized');
 *   SDKLogger.download.debug('Starting download', { url: 'https://...' });
 *   SDKLogger.llm.error('Generation failed', { modelId: 'llama-3.2' });
 *
 *   // Create custom logger
 *   const logger = new SDKLogger('MyComponent');
 *   logger.info('Component ready');
 */

import { LoggingManager } from '../Services/LoggingManager';
import { LogLevel } from '../Models/LogLevel';

// ============================================================================
// SDK Logger
// ============================================================================

/**
 * Simple logger for SDK components with category-based filtering.
 * Thread-safe (JS is single-threaded) and easy to use.
 *
 * Matches iOS: SDKLogger struct
 */
export class SDKLogger {
  /** Logger category (e.g., "LLM", "Download", "Models") */
  public readonly category: string;

  /**
   * Create a new logger with the specified category.
   * @param category - Category name for log filtering
   */
  constructor(category: string = 'SDK') {
    this.category = category;
  }

  // ==========================================================================
  // Logging Methods
  // ==========================================================================

  /**
   * Log a debug message.
   * Only logged when minLogLevel is Debug or lower.
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public debug(message: string, metadata?: Record<string, unknown>): void {
    // Swift parity: debug() is compiled out of release builds via `#if DEBUG`
    // (SDKLogger.swift:319-320). RN's equivalent gate is the `__DEV__` global.
    if (typeof __DEV__ !== 'undefined' && !__DEV__) {
      return;
    }
    LoggingManager.shared.log(LogLevel.LOG_LEVEL_DEBUG, this.category, message, metadata);
  }

  /**
   * Log an info message.
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public info(message: string, metadata?: Record<string, unknown>): void {
    LoggingManager.shared.log(LogLevel.LOG_LEVEL_INFO, this.category, message, metadata);
  }

  /**
   * Log a warning message.
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public warning(message: string, metadata?: Record<string, unknown>): void {
    LoggingManager.shared.log(
      LogLevel.LOG_LEVEL_WARNING,
      this.category,
      message,
      metadata
    );
  }

  /**
   * Log an error message.
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public error(message: string, metadata?: Record<string, unknown>): void {
    LoggingManager.shared.log(LogLevel.LOG_LEVEL_ERROR, this.category, message, metadata);
  }

  /**
   * Log a fault message (critical/fatal error).
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public fault(message: string, metadata?: Record<string, unknown>): void {
    LoggingManager.shared.log(LogLevel.LOG_LEVEL_FATAL, this.category, message, metadata);
  }

  /**
   * Log a message with a specific level.
   *
   * @param level - Log level
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public log(
    level: LogLevel,
    message: string,
    metadata?: Record<string, unknown>
  ): void {
    LoggingManager.shared.log(level, this.category, message, metadata);
  }

  // ==========================================================================
  // Error Logging with Context
  // ==========================================================================

  /**
   * Log an Error object using only non-secret structural identifiers.
   * Arbitrary messages, stacks, nested transport errors, and caller context
   * can contain credentials or request bodies and therefore stay out of
   * device logs. The original exception remains available to the caller.
   *
   * Matches iOS: logError(_ error:, additionalInfo:, file:, line:, function:)
   *
   * @param error - Error to log
   * @param additionalInfo - Optional additional context
   */
  public logError(error: Error, additionalInfo?: string): void {
    const metadata: Record<string, unknown> = {
      error_name: error.name,
      context_provided: Boolean(additionalInfo),
    };

    // SDKException-shaped fields are optional because this logger deliberately
    // accepts the base Error type and must not depend on one throwable class.
    const sdkErr = error as Error & {
      readonly code?: unknown;
      readonly category?: unknown;
    };
    if (typeof sdkErr.code === 'number') {
      metadata.error_code = sdkErr.code;
    }
    if (typeof sdkErr.category === 'number') {
      metadata.error_category = sdkErr.category;
    }

    LoggingManager.shared.log(
      LogLevel.LOG_LEVEL_ERROR,
      this.category,
      'SDK operation failed',
      metadata
    );
  }

  // ==========================================================================
  // Convenience Loggers (Static)
  // ==========================================================================

  /**
   * Shared logger for general SDK operations.
   * Category: "RunAnywhere"
   */
  public static readonly shared = new SDKLogger('RunAnywhere');

  /**
   * Logger for LLM operations.
   * Category: "LLM"
   */
  public static readonly llm = new SDKLogger('LLM');

  /**
   * Logger for STT (Speech-to-Text) operations.
   * Category: "STT"
   */
  public static readonly stt = new SDKLogger('STT');

  /**
   * Logger for TTS (Text-to-Speech) operations.
   * Category: "TTS"
   */
  public static readonly tts = new SDKLogger('TTS');

  /**
   * Logger for download operations.
   * Category: "Download"
   */
  public static readonly download = new SDKLogger('Download');

  /**
   * Logger for model operations.
   * Category: "Models"
   */
  public static readonly models = new SDKLogger('Models');

  /**
   * Logger for core SDK operations.
   * Category: "Core"
   */
  public static readonly core = new SDKLogger('Core');

  /**
   * Logger for VAD (Voice Activity Detection) operations.
   * Category: "VAD"
   */
  public static readonly vad = new SDKLogger('VAD');

  /**
   * Logger for network operations.
   * Category: "Network"
   */
  public static readonly network = new SDKLogger('Network');

  /**
   * Logger for events.
   * Category: "Events"
   */
  public static readonly events = new SDKLogger('Events');

  /**
   * Logger for archive/extraction operations.
   * Category: "Archive"
   */
  public static readonly archive = new SDKLogger('Archive');
}
