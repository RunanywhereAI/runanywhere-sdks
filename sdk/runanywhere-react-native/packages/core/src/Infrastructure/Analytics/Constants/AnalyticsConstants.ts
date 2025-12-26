/**
 * AnalyticsConstants.ts
 * RunAnywhere SDK
 *
 * Analytics and telemetry configuration constants.
 * Matches iOS: Infrastructure/Analytics/Constants/AnalyticsConstants.swift
 */

/**
 * Analytics and telemetry configuration constants
 */
export const AnalyticsConstants = {
  // MARK: - Telemetry Defaults

  /** Batch size for telemetry sync */
  telemetryBatchSize: 50,

  /** Maximum queue size before dropping old events */
  maxQueueSize: 1000,

  /** Flush interval in milliseconds */
  flushIntervalMs: 30000,

  // MARK: - Session Configuration

  /** Session timeout in milliseconds (30 minutes) */
  sessionTimeout: 30 * 60 * 1000,

  /** Maximum session duration in milliseconds (24 hours) */
  maxSessionDuration: 24 * 60 * 60 * 1000,

  // MARK: - Event Configuration

  /** Maximum event properties count */
  maxEventProperties: 50,

  /** Maximum property value length */
  maxPropertyValueLength: 1024,

  /** Maximum event name length */
  maxEventNameLength: 128,
} as const;

/**
 * Type for AnalyticsConstants
 */
export type AnalyticsConstantsType = typeof AnalyticsConstants;
