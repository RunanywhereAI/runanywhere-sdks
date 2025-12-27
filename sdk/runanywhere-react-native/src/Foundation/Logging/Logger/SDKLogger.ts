/**
 * SDKLogger.ts
 *
 * Centralized logging utility for SDK components
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Logging/Logger/SDKLogger.swift
 */

import { LoggingManager } from '../Services/LoggingManager';
import { LogLevel } from '../Models/LogLevel';

/**
 * Centralized logging utility with sensitive data protection
 */
export class SDKLogger {
  private category: string;

  constructor(category: string = 'SDK') {
    this.category = category;
  }

  /**
   * Log a debug message
   */
  public debug(message: string, metadata?: { [key: string]: any }): void {
    LoggingManager.shared.log(LogLevel.Debug, this.category, message, metadata);
  }

  /**
   * Log an info message
   */
  public info(message: string, metadata?: { [key: string]: any }): void {
    LoggingManager.shared.log(LogLevel.Info, this.category, message, metadata);
  }

  /**
   * Log a warning message
   */
  public warning(message: string, metadata?: { [key: string]: any }): void {
    LoggingManager.shared.log(LogLevel.Warning, this.category, message, metadata);
  }

  /**
   * Log an error message
   */
  public error(message: string, metadata?: { [key: string]: any }): void {
    LoggingManager.shared.log(LogLevel.Error, this.category, message, metadata);
  }

  /**
   * Log a fault message
   */
  public fault(message: string, metadata?: { [key: string]: any }): void {
    LoggingManager.shared.log(LogLevel.Fault, this.category, message, metadata);
  }

  /**
   * Log a message with a specific level
   */
  public log(
    level: LogLevel,
    message: string,
    metadata?: { [key: string]: any }
  ): void {
    LoggingManager.shared.log(level, this.category, message, metadata);
  }
}
