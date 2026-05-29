/**
 * RunAnywhere Web SDK - Logger
 *
 * Logging system matching the pattern across all SDKs.
 * Routes to console.* methods in the browser.
 */

export enum LogLevel {
  Trace = 0,
  Debug = 1,
  Info = 2,
  Warning = 3,
  Error = 4,
  Fatal = 5,
}

/** Map LogLevel to RACommons rac_log_level_t values */
export const LOG_LEVEL_TO_RAC: Record<LogLevel, number> = {
  [LogLevel.Trace]: 0,
  [LogLevel.Debug]: 1,
  [LogLevel.Info]: 2,
  [LogLevel.Warning]: 3,
  [LogLevel.Error]: 4,
  [LogLevel.Fatal]: 5,
};

/**
 * Configuration shape for the SDK logging system.
 * Mirrors Swift `LoggingConfiguration` in SDKLogger.swift.
 */
export interface LoggingConfiguration {
  /** Enable local console logging. */
  enableLocalLogging: boolean;
  /** Minimum severity to emit. */
  minLogLevel: LogLevel;
  /** Enable Sentry error forwarding. */
  enableSentryLogging: boolean;
}

/**
 * Represents a destination that can receive log entries.
 * Mirrors Swift `LogDestination` protocol.
 */
export interface LogDestination {
  readonly identifier: string;
  write(level: LogLevel, category: string, message: string): void;
  flush(): void;
}

export class SDKLogger {
  private static _level: LogLevel = LogLevel.Info;
  private static _enabled = true;
  private static _sentryEnabled = false;
  private static _extraDestinations: Map<string, LogDestination> = new Map();

  private readonly category: string;

  constructor(category: string) {
    this.category = category;
  }

  // -------------------------------------------------------------------------
  // Static configuration surface — mirrors Swift Logging.shared.*
  // -------------------------------------------------------------------------

  static get level(): LogLevel {
    return SDKLogger._level;
  }

  static set level(level: LogLevel) {
    SDKLogger._level = level;
  }

  static get enabled(): boolean {
    return SDKLogger._enabled;
  }

  static set enabled(value: boolean) {
    SDKLogger._enabled = value;
  }

  /** Apply a full logging configuration in one call. Mirrors Swift `Logging.shared.configure(_:)`. */
  static configure(config: LoggingConfiguration): void {
    SDKLogger._enabled = config.enableLocalLogging;
    SDKLogger._level = config.minLogLevel;
    SDKLogger._sentryEnabled = config.enableSentryLogging;
  }

  /** Enable or disable local console output. Mirrors Swift `Logging.shared.setLocalLoggingEnabled(_:)`. */
  static setLocalLoggingEnabled(enabled: boolean): void {
    SDKLogger._enabled = enabled;
  }

  /** Set minimum log level. Mirrors Swift `Logging.shared.setMinLogLevel(_:)`. */
  static setMinLogLevel(level: LogLevel): void {
    SDKLogger._level = level;
  }

  /** Enable or disable Sentry error forwarding. Mirrors Swift `Logging.shared.setSentryLoggingEnabled(_:)`. */
  static setSentryLoggingEnabled(enabled: boolean): void {
    SDKLogger._sentryEnabled = enabled;
  }

  /** Register a custom log destination. Mirrors Swift `Logging.shared.addDestination(_:)`. */
  static addDestination(destination: LogDestination): void {
    SDKLogger._extraDestinations.set(destination.identifier, destination);
  }

  /** Flush all registered destinations. Mirrors Swift `Logging.shared.flush()`. */
  static flush(): void {
    for (const destination of SDKLogger._extraDestinations.values()) {
      try {
        destination.flush();
      } catch { /* Swallow flush errors so logging never crashes the SDK. */ }
    }
  }

  trace(message: string): void {
    this.log(LogLevel.Trace, message);
  }

  debug(message: string): void {
    this.log(LogLevel.Debug, message);
  }

  info(message: string): void {
    this.log(LogLevel.Info, message);
  }

  warning(message: string): void {
    this.log(LogLevel.Warning, message);
  }

  error(message: string): void {
    this.log(LogLevel.Error, message);
  }

  private log(level: LogLevel, message: string): void {
    const shouldLog = SDKLogger._enabled || SDKLogger._sentryEnabled;
    if (level < SDKLogger._level || !shouldLog) {
      return;
    }

    if (SDKLogger._enabled) {
      const prefix = `[RunAnywhere:${this.category}]`;

      switch (level) {
        case LogLevel.Trace:
        case LogLevel.Debug:
          console.debug(prefix, message);
          break;
        case LogLevel.Info:
          console.info(prefix, message);
          break;
        case LogLevel.Warning:
          console.warn(prefix, message);
          break;
        case LogLevel.Error:
        case LogLevel.Fatal:
          console.error(prefix, message);
          break;
      }
    }

    for (const destination of SDKLogger._extraDestinations.values()) {
      try {
        destination.write(level, this.category, message);
      } catch { /* Swallow destination errors so logging never crashes the SDK. */ }
    }
  }
}
