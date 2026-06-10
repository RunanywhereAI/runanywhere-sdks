/**
 * RunAnywhere Web SDK - Logger
 *
 * Logging system matching the pattern across all SDKs.
 * Routes to console.* methods in the browser.
 */

// `LogLevel` and `LoggingConfiguration` are the generated proto types
// (idl/logging.proto). The proto `LogLevel` mirrors the C ABI rac_log_level_t
// (LOG_LEVEL_TRACE=0 .. LOG_LEVEL_FATAL=5), which is numerically identical to
// the Web SDK's previous hand-written enum, so adopting it is value-stable.
// Severity ordering ("larger = more severe") holds, so the `<` comparisons in
// `log()` keep working. The hand-written `LoggingConfiguration` was a subset of
// the generated one (which additionally carries enableRemoteLogging /
// includeSourceLocation / includeDeviceMetadata); the console logger only acts
// on the three fields it supported before and ignores the rest.
import { LogLevel, type LoggingConfiguration } from '@runanywhere/proto-ts/logging';

export { LogLevel };
export type { LoggingConfiguration };

/** Map LogLevel to RACommons rac_log_level_t values. Values are already
 * C-ABI-aligned, so this is the identity mapping. */
export const LOG_LEVEL_TO_RAC: Record<LogLevel, number> = {
  [LogLevel.LOG_LEVEL_TRACE]: 0,
  [LogLevel.LOG_LEVEL_DEBUG]: 1,
  [LogLevel.LOG_LEVEL_INFO]: 2,
  [LogLevel.LOG_LEVEL_WARNING]: 3,
  [LogLevel.LOG_LEVEL_ERROR]: 4,
  [LogLevel.LOG_LEVEL_FATAL]: 5,
  [LogLevel.UNRECOGNIZED]: -1,
};

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
  private static _level: LogLevel = LogLevel.LOG_LEVEL_INFO;
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
    this.log(LogLevel.LOG_LEVEL_TRACE, message);
  }

  debug(message: string): void {
    this.log(LogLevel.LOG_LEVEL_DEBUG, message);
  }

  info(message: string): void {
    this.log(LogLevel.LOG_LEVEL_INFO, message);
  }

  warning(message: string): void {
    this.log(LogLevel.LOG_LEVEL_WARNING, message);
  }

  error(message: string): void {
    this.log(LogLevel.LOG_LEVEL_ERROR, message);
  }

  private log(level: LogLevel, message: string): void {
    const shouldLog = SDKLogger._enabled || SDKLogger._sentryEnabled;
    if (level < SDKLogger._level || !shouldLog) {
      return;
    }

    if (SDKLogger._enabled) {
      const prefix = `[RunAnywhere:${this.category}]`;

      switch (level) {
        case LogLevel.LOG_LEVEL_TRACE:
        case LogLevel.LOG_LEVEL_DEBUG:
          console.debug(prefix, message);
          break;
        case LogLevel.LOG_LEVEL_INFO:
          console.info(prefix, message);
          break;
        case LogLevel.LOG_LEVEL_WARNING:
          console.warn(prefix, message);
          break;
        case LogLevel.LOG_LEVEL_ERROR:
        case LogLevel.LOG_LEVEL_FATAL:
          console.error(prefix, message);
          break;
        case LogLevel.UNRECOGNIZED:
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
