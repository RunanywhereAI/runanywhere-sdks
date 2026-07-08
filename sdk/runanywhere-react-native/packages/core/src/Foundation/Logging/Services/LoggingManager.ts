/**
 * LoggingManager.ts
 *
 * Central logging service: routes log entries to registered destinations
 * based on the current `LoggingConfiguration`.
 *
 * Mirrors the `Logging` class in
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift`.
 */

import { LogLevel } from '../Models/LogLevel';
import {
  type LoggingConfiguration,
  getConfigurationForEnvironment,
} from '../Models/LoggingConfiguration';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

export interface LogEntry {
  level: LogLevel;
  category: string;
  message: string;
  metadata?: Record<string, unknown>;
  timestamp: Date;
}

export interface LogDestination {
  identifier: string;
  isAvailable: boolean;
  write(entry: LogEntry): void;
  flush(): void;
}

export class ConsoleLogDestination implements LogDestination {
  readonly identifier = 'console';
  readonly isAvailable = true;

  write(entry: LogEntry): void {
    const timestamp = entry.timestamp.toISOString();
    const levelStr = describeLevel(entry.level);
    const logMessage = `[${timestamp}] [${levelStr}] [${entry.category}] ${entry.message}`;

    switch (entry.level) {
      case LogLevel.LOG_LEVEL_DEBUG:
        // eslint-disable-next-line no-console
        console.debug(logMessage, entry.metadata ?? '');
        break;
      case LogLevel.LOG_LEVEL_INFO:
        // eslint-disable-next-line no-console
        console.info(logMessage, entry.metadata ?? '');
        break;
      case LogLevel.LOG_LEVEL_WARNING:
        // eslint-disable-next-line no-console
        console.warn(logMessage, entry.metadata ?? '');
        break;
      case LogLevel.LOG_LEVEL_ERROR:
      case LogLevel.LOG_LEVEL_FATAL:
        // eslint-disable-next-line no-console
        console.error(logMessage, entry.metadata ?? '');
        break;
    }
  }

  flush(): void {
    // Console doesn't need flushing.
  }
}

export class LoggingManager {
  private static sharedInstance: LoggingManager | null = null;

  private destinations: Map<string, LogDestination> = new Map();
  private config: LoggingConfiguration;
  private readonly consoleDestination = new ConsoleLogDestination();

  private constructor() {
    this.config = getConfigurationForEnvironment(
      SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
    );
    this.addDestination(this.consoleDestination);
  }

  public static get shared(): LoggingManager {
    if (!LoggingManager.sharedInstance) {
      LoggingManager.sharedInstance = new LoggingManager();
    }
    return LoggingManager.sharedInstance;
  }

  public get configuration(): LoggingConfiguration {
    return { ...this.config };
  }

  public configure(config: LoggingConfiguration): void {
    this.config = { ...config };
    if (!this.config.enableLocalLogging) {
      this.removeDestinationByIdentifier(this.consoleDestination.identifier);
    } else if (!this.destinations.has(this.consoleDestination.identifier)) {
      this.addDestination(this.consoleDestination);
    }
  }

  public applyEnvironmentConfiguration(environment: SDKEnvironment): void {
    this.configure(getConfigurationForEnvironment(environment));
  }

  public setLocalLoggingEnabled(enabled: boolean): void {
    this.config.enableLocalLogging = enabled;
    if (!enabled) {
      this.removeDestinationByIdentifier(this.consoleDestination.identifier);
    } else if (!this.destinations.has(this.consoleDestination.identifier)) {
      this.addDestination(this.consoleDestination);
    }
  }

  public setMinLogLevel(level: LogLevel): void {
    this.config.minLogLevel = level;
  }

  public addDestination(destination: LogDestination): void {
    this.destinations.set(destination.identifier, destination);
  }

  public removeDestination(destination: LogDestination): void {
    this.removeDestinationByIdentifier(destination.identifier);
  }

  private removeDestinationByIdentifier(identifier: string): void {
    this.destinations.delete(identifier);
  }

  public log(
    level: LogLevel,
    category: string,
    message: string,
    metadata?: Record<string, unknown>
  ): void {
    if (level < this.config.minLogLevel) return;
    // Note: no global enableLocalLogging early-return; that flag governs the
    // console destination's presence in the map. App-registered custom
    // destinations keep receiving entries after severity filtering.

    const entry: LogEntry = {
      level,
      category,
      message,
      metadata: sanitizeMetadata(metadata),
      timestamp: new Date(),
    };

    for (const destination of this.destinations.values()) {
      if (!destination.isAvailable) continue;
      try {
        destination.write(entry);
      } catch {
        // Swallow destination errors so logging never crashes the SDK.
      }
    }
  }

  public flush(): void {
    for (const destination of this.destinations.values()) {
      try {
        destination.flush();
      } catch {
        // Swallow flush errors.
      }
    }
  }
}

function describeLevel(level: LogLevel): string {
  switch (level) {
    case LogLevel.LOG_LEVEL_DEBUG:
      return 'DEBUG';
    case LogLevel.LOG_LEVEL_INFO:
      return 'INFO';
    case LogLevel.LOG_LEVEL_WARNING:
      return 'WARN';
    case LogLevel.LOG_LEVEL_ERROR:
      return 'ERROR';
    case LogLevel.LOG_LEVEL_FATAL:
      return 'FAULT';
    case LogLevel.LOG_LEVEL_TRACE:
      return 'TRACE';
    default:
      return 'INFO';
  }
}

// ============================================================================
// Metadata sanitization (Swift SDKLogger.swift:255-280 / commons log_redact.cpp)
// ============================================================================

/**
 * Canonical sensitive-substring list. Lowercase, in declaration order; the
 * C++ logger (`rac_log_metadata_should_redact`, log_redact.cpp), Swift
 * `SDKLogger`, and this list must stay in lockstep. Duplicated here (instead
 * of delegating to the C ABI like Swift) because the RN bridge is async and
 * `log()` is synchronous.
 */
const SENSITIVE_SUBSTRINGS = [
  'key',
  'secret',
  'password',
  'token',
  'auth',
  'credential',
] as const;

function shouldRedact(key: string): boolean {
  const lowered = key.toLowerCase();
  return SENSITIVE_SUBSTRINGS.some((needle) => lowered.includes(needle));
}

/**
 * Redact sensitive metadata values (recursively for nested objects) before
 * the entry reaches any destination. Mirrors Swift `sanitizeMetadata(_:)`.
 */
function sanitizeMetadata(
  metadata?: Record<string, unknown>
): Record<string, unknown> | undefined {
  if (!metadata) return undefined;
  const sanitized: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(metadata)) {
    if (shouldRedact(key)) {
      sanitized[key] = '[REDACTED]';
    } else if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
      sanitized[key] = sanitizeMetadata(value as Record<string, unknown>) ?? {};
    } else {
      sanitized[key] = value;
    }
  }
  return sanitized;
}
