/**
 * LoggingManager.ts
 *
 * Centralized logging manager with multiple destination support
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Logging/Services/LoggingManager.swift
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/Protocol/LogDestination.swift
 */

import { LogLevel } from '../Models/LogLevel';

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
  /** Human-readable name */
  name: string;
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
        console.warn(logMessage, entry.metadata ?? '');
        break;
      case LogLevel.Error:
      case LogLevel.Fault:
        console.error(logMessage, entry.metadata ?? '');
        break;
    }
  }

  flush(): void {
    // Console doesn't need flushing
  }
}

// ============================================================================
// Event Destination (for public exposure)
// ============================================================================

/**
 * Log event callback type
 */
export type LogEventCallback = (entry: LogEntry) => void;

/**
 * Event-based log destination for public log exposure
 * Allows external consumers to subscribe to log events
 */
export class EventLogDestination implements LogDestination {
  readonly identifier = 'event';
  readonly name = 'Event Emitter';
  readonly isAvailable = true;

  private callbacks: Set<LogEventCallback> = new Set();

  /**
   * Subscribe to log events
   * @returns Unsubscribe function
   */
  subscribe(callback: LogEventCallback): () => void {
    this.callbacks.add(callback);
    return () => {
      this.callbacks.delete(callback);
    };
  }

  write(entry: LogEntry): void {
    for (const callback of this.callbacks) {
      try {
        callback(entry);
      } catch {
        // Ignore callback errors
      }
    }
  }

  flush(): void {
    // No buffering
  }
}

// ============================================================================
// Logging Manager
// ============================================================================

/**
 * Centralized logging manager with multiple destination support
 * Matches iOS: LoggingManager + DefaultLoggingService
 */
export class LoggingManager {
  private static sharedInstance: LoggingManager | null = null;
  private logLevel: LogLevel = LogLevel.Info;
  private destinations: Map<string, LogDestination> = new Map();

  // Default destinations
  private readonly consoleDestination = new ConsoleLogDestination();
  private readonly eventDestination = new EventLogDestination();

  private constructor() {
    // Add default console destination
    this.addDestination(this.consoleDestination);
    // Add event destination for public log exposure
    this.addDestination(this.eventDestination);
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
  // Configuration
  // ============================================================================

  /**
   * Set log level
   */
  public setLogLevel(level: LogLevel): void {
    this.logLevel = level;
  }

  /**
   * Get current log level
   */
  public getLogLevel(): LogLevel {
    return this.logLevel;
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
   * Matches iOS: removeDestination(_ identifier: String)
   */
  public removeDestination(identifier: string): void {
    this.destinations.delete(identifier);
  }

  /**
   * Get all registered destinations
   */
  public getDestinations(): LogDestination[] {
    return Array.from(this.destinations.values());
  }

  /**
   * Check if a destination is registered
   */
  public hasDestination(identifier: string): boolean {
    return this.destinations.has(identifier);
  }

  // ============================================================================
  // Public Log Event Subscription
  // ============================================================================

  /**
   * Subscribe to all log events (for public exposure)
   * This allows consumers to receive log events for their own logging infrastructure.
   * Matches iOS pattern of exposing log events.
   *
   * @param callback - Function called for each log entry
   * @returns Unsubscribe function
   */
  public onLog(callback: LogEventCallback): () => void {
    return this.eventDestination.subscribe(callback);
  }

  // ============================================================================
  // Logging Operations
  // ============================================================================

  /**
   * Log a message
   */
  public log(
    level: LogLevel,
    category: string,
    message: string,
    metadata?: Record<string, unknown>
  ): void {
    if (level < this.logLevel) {
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
