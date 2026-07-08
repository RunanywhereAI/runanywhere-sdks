/**
 * RunAnywhere+Logging.ts
 *
 * Logging configuration namespace — mirrors Swift's `RunAnywhere+Logging.swift`.
 * Provides `RunAnywhere.logging.*` surface for controlling SDK log output.
 * One-to-one method parity with Swift RunAnywhere+Logging.swift.
 */

import {
  SDKLogger,
  LogLevel,
  type LoggingConfiguration,
  type LogDestination,
} from '../../Foundation/SDKLogger';

export { LogLevel };
export type { LoggingConfiguration, LogDestination };

export const Logging = {
  /**
   * Configure logging with a predefined configuration.
   * Matches iOS: static func configureLogging(_ config: LoggingConfiguration)
   */
  configureLogging(config: LoggingConfiguration): void {
    SDKLogger.configure(config);
  },

  /**
   * Enable or disable local console logging.
   * Matches iOS: static func setLocalLoggingEnabled(_ enabled: Bool)
   */
  setLocalLoggingEnabled(enabled: boolean): void {
    SDKLogger.setLocalLoggingEnabled(enabled);
  },

  /**
   * Set minimum log level for SDK logging.
   * Matches iOS: static func setLogLevel(_ level: LogLevel)
   */
  setLogLevel(level: LogLevel): void {
    SDKLogger.setMinLogLevel(level);
  },

  /**
   * Add a custom log destination.
   * Matches iOS: static func addLogDestination(_ destination: LogDestination)
   */
  addLogDestination(destination: LogDestination): void {
    SDKLogger.addDestination(destination);
  },

  /**
   * Enable verbose debugging mode.
   * Matches iOS: static func setDebugMode(_ enabled: Bool)
   */
  setDebugMode(enabled: boolean): void {
    SDKLogger.setMinLogLevel(enabled ? LogLevel.LOG_LEVEL_DEBUG : LogLevel.LOG_LEVEL_INFO);
    SDKLogger.setLocalLoggingEnabled(enabled);
  },

  /**
   * Force flush all pending logs to destinations.
   * Matches iOS: static func flushLogs()
   */
  flushLogs(): void {
    SDKLogger.flush();
  },
};
