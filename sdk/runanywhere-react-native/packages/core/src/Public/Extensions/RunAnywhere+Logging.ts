/**
 * RunAnywhere+Logging.ts
 *
 * Logging extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+Logging.swift
 */

import type { LogLevel } from '../../Foundation/Logging/Models/LogLevel';
import type {
  LogEventCallback,
  LogDestination,
} from '../../Foundation/Logging';

// ============================================================================
// Logging Extension
// ============================================================================

/**
 * Set SDK log level
 * Matches iOS: static func setLogLevel(_ level: LogLevel)
 */
export function setLogLevel(level: LogLevel): void {
  const { LoggingManager } = require('../../Foundation/Logging');
  LoggingManager.shared.setLogLevel(level);
}

/**
 * Subscribe to all SDK log events
 * Matches iOS pattern of exposing log events publicly.
 */
export function onLog(callback: LogEventCallback): () => void {
  const { LoggingManager } = require('../../Foundation/Logging');
  return LoggingManager.shared.onLog(callback);
}

/**
 * Add a custom log destination
 * Matches iOS: static func addLogDestination(_ destination: LogDestination)
 */
export function addLogDestination(destination: LogDestination): void {
  const { LoggingManager } = require('../../Foundation/Logging');
  LoggingManager.shared.addDestination(destination);
}

/**
 * Remove a log destination by identifier
 */
export function removeLogDestination(identifier: string): void {
  const { LoggingManager } = require('../../Foundation/Logging');
  LoggingManager.shared.removeDestination(identifier);
}
