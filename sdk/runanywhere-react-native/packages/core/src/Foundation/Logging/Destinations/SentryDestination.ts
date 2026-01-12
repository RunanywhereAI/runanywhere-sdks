/**
 * SentryDestination.ts
 *
 * Log destination that sends logs to Sentry for error tracking.
 *
 * Matches iOS: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/SentryDestination.swift
 *
 * Usage:
 *   import * as Sentry from '@sentry/react-native';
 *   import { SentryDestination, LoggingManager } from '@runanywhere/core';
 *
 *   // Initialize Sentry first
 *   Sentry.init({ dsn: 'your-dsn-here' });
 *
 *   // Add Sentry destination
 *   const sentryDest = new SentryDestination(Sentry);
 *   LoggingManager.shared.addDestination(sentryDest);
 */

import { LogLevel } from '../Models/LogLevel';
import type { LogDestination, LogEntry } from '../Services/LoggingManager';

// ============================================================================
// Sentry Types (minimal interface to avoid hard dependency)
// ============================================================================

/**
 * Minimal Sentry interface for logging
 * This allows apps to pass their own Sentry instance
 */
export interface SentryInterface {
  addBreadcrumb(breadcrumb: {
    message?: string;
    category?: string;
    level?: 'fatal' | 'error' | 'warning' | 'info' | 'debug';
    data?: Record<string, unknown>;
    timestamp?: number;
  }): void;

  captureMessage(
    message: string,
    level?: 'fatal' | 'error' | 'warning' | 'info' | 'debug'
  ): string;

  captureException(exception: Error, hint?: { extra?: Record<string, unknown> }): string;

  setExtra(key: string, extra: unknown): void;
  setTag(key: string, value: string): void;

  flush(timeout?: number): Promise<boolean>;
}

// ============================================================================
// Sentry Destination
// ============================================================================

/**
 * Log destination that sends warning+ logs to Sentry.
 * Matches iOS: SentryDestination
 */
export class SentryDestination implements LogDestination {
  static readonly DESTINATION_ID = 'com.runanywhere.logging.sentry';

  readonly identifier = SentryDestination.DESTINATION_ID;
  readonly name = 'Sentry';

  private sentry: SentryInterface | null = null;
  private initialized = false;

  /** Minimum level to send to Sentry (warning and above) */
  private readonly minSentryLevel: LogLevel = LogLevel.Warning;

  constructor(sentry?: SentryInterface) {
    if (sentry) {
      this.initialize(sentry);
    }
  }

  // ==========================================================================
  // Initialization
  // ==========================================================================

  /**
   * Initialize with a Sentry instance
   * @param sentry - Sentry SDK instance
   */
  initialize(sentry: SentryInterface): void {
    this.sentry = sentry;
    this.initialized = true;
  }

  /**
   * Check if Sentry is available
   */
  get isAvailable(): boolean {
    return this.initialized && this.sentry !== null;
  }

  // ==========================================================================
  // LogDestination Implementation
  // ==========================================================================

  /**
   * Write a log entry to Sentry
   * Matches iOS: write(_ entry: LogEntry)
   */
  write(entry: LogEntry): void {
    if (!this.isAvailable || !this.sentry) return;
    if (entry.level < this.minSentryLevel) return;

    // Add breadcrumb for context trail
    this.addBreadcrumb(entry);

    // For error and fault levels, capture as Sentry event
    if (entry.level >= LogLevel.Error) {
      this.captureEvent(entry);
    }
  }

  /**
   * Flush pending Sentry events
   */
  flush(): void {
    if (!this.isAvailable || !this.sentry) return;
    // Fire and forget - Sentry.flush returns a promise but we don't wait
    void this.sentry.flush(2000);
  }

  // ==========================================================================
  // Private Helpers
  // ==========================================================================

  /**
   * Add a breadcrumb for the log entry
   */
  private addBreadcrumb(entry: LogEntry): void {
    if (!this.sentry) return;

    this.sentry.addBreadcrumb({
      message: entry.message,
      category: entry.category,
      level: this.convertToSentryLevel(entry.level),
      data: entry.metadata as Record<string, unknown>,
      timestamp: entry.timestamp.getTime() / 1000, // Sentry uses seconds
    });
  }

  /**
   * Capture an event for error/fault level logs
   */
  private captureEvent(entry: LogEntry): void {
    if (!this.sentry) return;

    // Set tags
    this.sentry.setTag('category', entry.category);
    this.sentry.setTag('log_level', this.getLogLevelDescription(entry.level));

    // Set extras
    if (entry.metadata) {
      for (const [key, value] of Object.entries(entry.metadata)) {
        this.sentry.setExtra(key, value);
      }
    }

    // Capture the message
    this.sentry.captureMessage(
      `[${entry.category}] ${entry.message}`,
      this.convertToSentryLevel(entry.level)
    );
  }

  /**
   * Convert LogLevel to Sentry severity level
   */
  private convertToSentryLevel(
    level: LogLevel
  ): 'fatal' | 'error' | 'warning' | 'info' | 'debug' {
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
        return 'fatal';
    }
  }

  /**
   * Get log level description
   */
  private getLogLevelDescription(level: LogLevel): string {
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
}
