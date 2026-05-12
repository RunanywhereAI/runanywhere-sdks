/**
 * LoggingManager.ts
 *
 * Centralized logging manager with multiple destination support.
 * Routes logs to multiple destinations (Console, Sentry, etc.) based on configuration.
 *
 * Matches iOS: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
 *              (Logging class - central service)
 *
 * Usage:
 *   // Configure for environment
 *   LoggingManager.shared.applyEnvironmentConfiguration(
 *     SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
 *   );
 *
 *   // Add Sentry destination
 *   LoggingManager.shared.addDestination(new SentryDestination(Sentry));
 *
 */

import { LogLevel } from '../Models/LogLevel';
import {
  type LoggingConfiguration,
  SDKEnvironment,
  getConfigurationForEnvironment,
} from '../Models/LoggingConfiguration';
import { SentryDestination } from '../Destinations/SentryDestination';

// ============================================================================
// Log Entry
// ============================================================================

/**
 * Log entry structure
 * Matches iOS: LogEntry
 */
export interface LogEntry {
  /** Log level */
  level: LogLevel;
  /** Category/subsystem */
  category: string;
  /** Log message */
  message: string;
  /** Optional metadata */
  metadata?: Record<string, unknown>;
  /** Timestamp */
  timestamp: Date;
}

// ============================================================================
// Log Destination Protocol
// ============================================================================

/**
 * Log destination interface
 * Matches iOS: LogDestination protocol
 */
export interface LogDestination {
  /** Unique identifier for this destination */
  identifier: string;
  /** Whether destination is available */
  isAvailable: boolean;
  /** Write a log entry */
  write(entry: LogEntry): void;
  /** Flush pending writes */
  flush(): void;
}

// ============================================================================
// Console Destination
// ============================================================================

/**
 * Console log destination (default)
 */
export class ConsoleLogDestination implements LogDestination {
  readonly identifier = 'console';
  readonly name = 'Console';
  readonly isAvailable = true;

  write(entry: LogEntry): void {
    const timestamp = entry.timestamp.toISOString();
    const levelStr = getLogLevelDescription(entry.level);
    const logMessage = `[${timestamp}] [${levelStr}] [${entry.category}] ${entry.message}`;

    switch (entry.level) {
      case LogLevel.Debug:
        // eslint-disable-next-line no-console
        console.debug(logMessage, entry.metadata ?? '');
        break;
      case LogLevel.Info:
        // eslint-disable-next-line no-console
        console.info(logMessage, entry.metadata ?? '');
        break;
      case LogLevel.Warning:
        // eslint-disable-next-line no-console
        console.warn(logMessage, entry.metadata ?? '');
        break;
      case LogLevel.Error:
      case LogLevel.Fault:
        // eslint-disable-next-line no-console
        console.error(logMessage, entry.metadata ?? '');
        break;
    }
  }

  flush(): void {
    // Console doesn't need flushing
  }
}

// ============================================================================
// Logging Manager
// ============================================================================

/**
 * Centralized logging manager with multiple destination support.
 * Matches iOS: Logging class (central service)
 */
export class LoggingManager {
  private static sharedInstance: LoggingManager | null = null;
  private destinations: Map<string, LogDestination> = new Map();

  // Configuration
  private config: LoggingConfiguration;

  // Default destinations
  private readonly consoleDestination = new ConsoleLogDestination();

  private constructor() {
    // Initialize with default development config
    this.config = getConfigurationForEnvironment(
      SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
    );

    // Add default console destination
    this.addDestination(this.consoleDestination);
  }

  // ============================================================================
  // Configuration (matches iOS Logging.configure)
  // ============================================================================

  /**
   * Get current configuration
   */
  public get configuration(): LoggingConfiguration {
    return { ...this.config };
  }

  /**
   * Configure the logging system.
   * Matches iOS: Logging.configure(_ config: LoggingConfiguration)
   *
   * @param config - Configuration to apply
   */
  public configure(config: LoggingConfiguration): void {
    this.config = { ...config };

    // Update console destination based on enableLocalLogging
    if (!this.config.enableLocalLogging) {
      this.removeDestinationByIdentifier(this.consoleDestination.identifier);
    } else if (!this.hasDestination(this.consoleDestination.identifier)) {
      this.addDestination(this.consoleDestination);
    }

    // React Native apps provide the concrete Sentry instance via
    // addLogDestination(...), so disabling removes that destination.
    if (!this.config.enableSentryLogging) {
      this.removeDestinationByIdentifier(SentryDestination.DESTINATION_ID);
    }
  }

  /**
   * Apply configuration for a specific environment.
   * Matches iOS: Logging.applyEnvironmentConfiguration(_ environment:)
   *
   * @param environment - SDK environment
   */
  public applyEnvironmentConfiguration(environment: SDKEnvironment): void {
    const envConfig = getConfigurationForEnvironment(environment);
    this.configure(envConfig);
  }

  /**
   * Set local logging enabled.
   * Matches iOS: Logging.setLocalLoggingEnabled(_ enabled:)
   */
  public setLocalLoggingEnabled(enabled: boolean): void {
    this.config.enableLocalLogging = enabled;
    if (!enabled) {
      this.removeDestinationByIdentifier(this.consoleDestination.identifier);
    } else if (!this.hasDestination(this.consoleDestination.identifier)) {
      this.addDestination(this.consoleDestination);
    }
  }

  /**
   * Set minimum log level.
   * Matches iOS: Logging.setMinLogLevel(_ level:)
   */
  public setMinLogLevel(level: LogLevel): void {
    this.config.minLogLevel = level;
  }

  /**
   * Set include device metadata.
   * Matches iOS: Logging.setIncludeDeviceMetadata(_ include:)
   */
  public setIncludeDeviceMetadata(include: boolean): void {
    this.config.includeDeviceMetadata = include;
  }

  /**
   * Set Sentry logging enabled.
   * Matches iOS: Logging.setSentryLoggingEnabled(_ enabled:)
   */
  public setSentryLoggingEnabled(enabled: boolean): void {
    this.config.enableSentryLogging = enabled;
    if (!enabled) {
      this.removeDestinationByIdentifier(SentryDestination.DESTINATION_ID);
    }
  }

  /**
   * Get shared instance
   */
  public static get shared(): LoggingManager {
    if (!LoggingManager.sharedInstance) {
      LoggingManager.sharedInstance = new LoggingManager();
    }
    return LoggingManager.sharedInstance;
  }

  // ============================================================================
  // Destination Management (matches iOS)
  // ============================================================================

  /**
   * Add a log destination
   * Matches iOS: addDestination(_ destination: LogDestination)
   */
  public addDestination(destination: LogDestination): void {
    this.destinations.set(destination.identifier, destination);
  }

  /**
   * Remove a log destination
   * Matches iOS: removeDestination(_ destination: LogDestination)
   */
  public removeDestination(destination: LogDestination): void {
    this.removeDestinationByIdentifier(destination.identifier);
  }

  /**
   * Get all registered destinations
   */
  public getDestinations(): LogDestination[] {
    return Array.from(this.destinations.values());
  }

  private hasDestination(identifier: string): boolean {
    return this.destinations.has(identifier);
  }

  private removeDestinationByIdentifier(identifier: string): void {
    this.destinations.delete(identifier);
  }

  // ============================================================================
  // Logging Operations
  // ============================================================================

  /**
   * Log a message.
   * Matches iOS: Logging.log(level:category:message:metadata:)
   */
  public log(
    level: LogLevel,
    category: string,
    message: string,
    metadata?: Record<string, unknown>
  ): void {
    // Filter by minimum log level
    if (level < this.config.minLogLevel) {
      return;
    }

    // Check if logging is enabled at all
    if (!this.config.enableLocalLogging && !this.config.enableSentryLogging) {
      return;
    }

    const entry: LogEntry = {
      level,
      category,
      message,
      metadata,
      timestamp: new Date(),
    };

    // Write to all available destinations
    for (const destination of this.destinations.values()) {
      if (destination.isAvailable) {
        try {
          destination.write(entry);
        } catch {
          // Silently ignore destination errors
        }
      }
    }
  }

  /**
   * Flush all destinations
   */
  public flush(): void {
    for (const destination of this.destinations.values()) {
      try {
        destination.flush();
      } catch {
        // Silently ignore flush errors
      }
    }
  }
}

/**
 * Get log level description
 */
function getLogLevelDescription(level: LogLevel): string {
  switch (level) {
    case LogLevel.Debug:
      return 'DEBUG';
    case LogLevel.Info:
      return 'INFO';
    case LogLevel.Warning:
      return 'WARN';
    case LogLevel.Error:
      return 'ERROR';
    case LogLevel.Fault:
      return 'FAULT';
  }
}
