/**
 * LoggingManager.ts
 *
 * Centralized logging manager
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Logging/Services/LoggingManager.swift
 */

import { LogLevel } from '../Models/LogLevel';

/**
 * Centralized logging manager
 */
export class LoggingManager {
  private static sharedInstance: LoggingManager | null = null;
  private logLevel: LogLevel = LogLevel.Info;

  /**
   * Get shared instance
   */
  public static get shared(): LoggingManager {
    if (!LoggingManager.sharedInstance) {
      LoggingManager.sharedInstance = new LoggingManager();
    }
    return LoggingManager.sharedInstance;
  }

  /**
   * Set log level
   */
  public setLogLevel(level: LogLevel): void {
    this.logLevel = level;
  }

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

    const timestamp = new Date().toISOString();
    const levelStr = getLogLevelDescription(level);
    const logMessage = `[${timestamp}] [${levelStr}] [${category}] ${message}`;

    if (metadata) {
      console.log(logMessage, metadata);
    } else {
      console.log(logMessage);
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
