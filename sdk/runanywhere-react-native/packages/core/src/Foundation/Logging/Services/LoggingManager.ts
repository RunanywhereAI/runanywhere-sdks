/**
 * LoggingManager.ts
 *
 * Central logging service: routes log entries to registered destinations
 * (console, Sentry, custom) based on the current `LoggingConfiguration`.
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
import { SentryDestination } from '../Destinations/SentryDestination';

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
    if (!this.config.enableSentryLogging) {
      this.removeDestinationByIdentifier(SentryDestination.DESTINATION_ID);
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

  public setSentryLoggingEnabled(enabled: boolean): void {
    this.config.enableSentryLogging = enabled;
    if (!enabled) {
      this.removeDestinationByIdentifier(SentryDestination.DESTINATION_ID);
    }
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
