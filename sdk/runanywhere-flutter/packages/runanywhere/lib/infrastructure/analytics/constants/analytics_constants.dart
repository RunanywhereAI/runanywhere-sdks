//
//  analytics_constants.dart
//  RunAnywhere SDK
//
//  Analytics and telemetry configuration constants
//  Matches iOS SDK's AnalyticsConstants.swift
//

/// Analytics and telemetry configuration constants
class AnalyticsConstants {
  // Private constructor to prevent instantiation
  AnalyticsConstants._();

  /// Batch size for telemetry sync
  static const int telemetryBatchSize = 50;

  /// Retention period for telemetry events (7 days)
  static const Duration telemetryRetentionPeriod = Duration(days: 7);

  /// Flush interval for analytics queue
  static const Duration flushInterval = Duration(seconds: 30);

  /// Maximum retry attempts for failed syncs
  static const int maxRetryAttempts = 3;

  /// Database name for telemetry storage
  static const String databaseName = 'runanywhere_telemetry.db';

  /// Database version
  static const int databaseVersion = 1;
}
