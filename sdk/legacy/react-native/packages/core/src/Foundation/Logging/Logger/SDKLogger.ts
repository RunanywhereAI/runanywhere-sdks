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
    LoggingManager.shared.log(LogLevel.Debug, this.category, message, metadata);
  }

  /**
   * Log an info message.
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public info(message: string, metadata?: Record<string, unknown>): void {
    LoggingManager.shared.log(LogLevel.Info, this.category, message, metadata);
  }

  /**
   * Log a warning message.
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public warning(message: string, metadata?: Record<string, unknown>): void {
    LoggingManager.shared.log(
      LogLevel.Warning,
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
    LoggingManager.shared.log(LogLevel.Error, this.category, message, metadata);
  }

  /**
   * Log a fault message (critical/fatal error).
   *
   * @param message - Log message
   * @param metadata - Optional metadata key-value pairs
   */
  public fault(message: string, metadata?: Record<string, unknown>): void {
    LoggingManager.shared.log(LogLevel.Fault, this.category, message, metadata);
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
   * Log an Error object with full context.
   * Extracts error information and logs with appropriate metadata.
   *
   * Matches iOS: logError(_ error:, additionalInfo:, file:, line:, function:)
   *
   * @param error - Error to log
   * @param additionalInfo - Optional additional context
   */
  public logError(error: Error, additionalInfo?: string): void {
    const errorDesc = error.message || 'Unknown error';

    let message = errorDesc;
    if (additionalInfo) {
      message += ` | Context: ${additionalInfo}`;
    }

    const metadata: Record<string, unknown> = {
      error_name: error.name,
      error_message: error.message,
      error_stack: error.stack,
    };

    // If SDKError, include additional fields
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const sdkError = error as any;
    if (sdkError.code !== undefined) {
      metadata.error_code = sdkError.code;
    }
    if (sdkError.category !== undefined) {
      metadata.error_category = sdkError.category;
    }
    if (sdkError.underlyingError !== undefined) {
      metadata.underlying_error = sdkError.underlyingError.message;
    }

    LoggingManager.shared.log(LogLevel.Error, this.category, message, metadata);
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
