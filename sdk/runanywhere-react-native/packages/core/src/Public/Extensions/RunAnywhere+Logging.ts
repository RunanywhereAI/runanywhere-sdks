/**
 * RunAnywhere+Logging.ts
 *
 * Logging extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+Logging.swift
 */

import {
  LogLevel,
  LoggingManager,
  type LoggingConfiguration,
  type LogDestination,
} from '../../Foundation/Logging';

// ============================================================================
// Logging Extension
// ============================================================================

/**
 * Configure SDK logging
 * Matches iOS: static func configureLogging(_ config: LoggingConfiguration)
 */
export function configureLogging(config: LoggingConfiguration): void {
  LoggingManager.shared.configure(config);
}

/**
 * Enable or disable local console logging
 * Matches iOS: static func setLocalLoggingEnabled(_ enabled: Bool)
 */
export function setLocalLoggingEnabled(enabled: boolean): void {
  LoggingManager.shared.setLocalLoggingEnabled(enabled);
}

/**
 * Set SDK log level
 * Matches iOS: static func setLogLevel(_ level: LogLevel)
 */
export function setLogLevel(level: LogLevel): void {
  LoggingManager.shared.setMinLogLevel(level);
}

/**
 * Add a custom log destination
 * Matches iOS: static func addLogDestination(_ destination: LogDestination)
 */
export function addLogDestination(destination: LogDestination): void {
  LoggingManager.shared.addDestination(destination);
}

/**
 * Enable verbose debugging mode
 * Matches iOS: static func setDebugMode(_ enabled: Bool)
 */
export function setDebugMode(enabled: boolean): void {
  setLogLevel(enabled ? LogLevel.LOG_LEVEL_DEBUG : LogLevel.LOG_LEVEL_INFO);
  setLocalLoggingEnabled(enabled);
}

/**
 * Force flush all pending logs to destinations
 * Matches iOS: static func flushLogs()
 */
export function flushLogs(): void {
  LoggingManager.shared.flush();
}
