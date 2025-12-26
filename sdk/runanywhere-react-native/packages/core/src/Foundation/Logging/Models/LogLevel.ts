/**
 * LogLevel.ts
 *
 * Log severity levels for the SDK
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Logging/Models/LogLevel.swift
 */

/**
 * Log severity levels
 */
export enum LogLevel {
  Debug = 0,
  Info = 1,
  Warning = 2,
  Error = 3,
  Fault = 4,
}

/**
 * Get log level description
 */
export function getLogLevelDescription(level: LogLevel): string {
  switch (level) {
    case LogLevel.Debug:
      return 'debug';
    case LogLevel.Info:
      return 'info';
    case LogLevel.Warning:
      return 'warning';
    case LogLevel.Error:
      return 'error';
    case LogLevel.Fault:
      return 'fault';
  }
}
