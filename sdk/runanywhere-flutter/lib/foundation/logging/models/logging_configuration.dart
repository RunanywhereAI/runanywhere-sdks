import 'log_level.dart';

/// Configuration settings for the logging system
///
/// Aligned with iOS: Sources/RunAnywhere/Infrastructure/Logging/Models/Configuration/LoggingConfiguration.swift
class LoggingConfiguration {
  /// Enable local logging (console output)
  final bool enableLocalLogging;

  /// Enable remote logging (telemetry)
  final bool enableRemoteLogging;

  /// Remote logging endpoint
  final Uri? remoteEndpoint;

  /// Minimum log level filter (also accessible as minimumLevel for compatibility)
  final LogLevel minLogLevel;

  /// Include device metadata in remote logs
  final bool includeDeviceMetadata;

  /// Maximum log entries to batch before sending
  final int batchSize;

  /// Maximum time to wait before sending logs (in seconds)
  final double batchInterval;

  /// Optional category filter - if set, only logs from these categories are recorded
  final Set<String>? categoryFilter;

  const LoggingConfiguration({
    this.enableLocalLogging = true,
    this.enableRemoteLogging = false,
    this.remoteEndpoint,
    this.minLogLevel = LogLevel.info,
    this.includeDeviceMetadata = true,
    this.batchSize = 100,
    this.batchInterval = 60,
    this.categoryFilter,
  });

  /// Alias for minLogLevel for compatibility with infrastructure code
  LogLevel get minimumLevel => minLogLevel;

  /// Create a copy with updated values
  LoggingConfiguration copyWith({
    bool? enableLocalLogging,
    bool? enableRemoteLogging,
    Uri? remoteEndpoint,
    LogLevel? minLogLevel,
    bool? includeDeviceMetadata,
    int? batchSize,
    double? batchInterval,
    Set<String>? categoryFilter,
  }) {
    return LoggingConfiguration(
      enableLocalLogging: enableLocalLogging ?? this.enableLocalLogging,
      enableRemoteLogging: enableRemoteLogging ?? this.enableRemoteLogging,
      remoteEndpoint: remoteEndpoint ?? this.remoteEndpoint,
      minLogLevel: minLogLevel ?? this.minLogLevel,
      includeDeviceMetadata:
          includeDeviceMetadata ?? this.includeDeviceMetadata,
      batchSize: batchSize ?? this.batchSize,
      batchInterval: batchInterval ?? this.batchInterval,
      categoryFilter: categoryFilter ?? this.categoryFilter,
    );
  }

  /// Validate the configuration
  /// Throws ArgumentError if configuration is invalid
  void validate() {
    if (enableRemoteLogging && remoteEndpoint == null) {
      throw ArgumentError(
          'Remote endpoint must be provided when remote logging is enabled');
    }
    if (batchSize <= 0) {
      throw ArgumentError('Batch size must be positive');
    }
    if (batchInterval <= 0) {
      throw ArgumentError('Batch interval must be positive');
    }
  }

  /// Configuration preset for development environment
  static const development = LoggingConfiguration(
    enableLocalLogging: true,
    minLogLevel: LogLevel.debug,
    includeDeviceMetadata: false,
  );

  /// Configuration preset for staging environment
  static const staging = LoggingConfiguration(
    enableLocalLogging: true,
    minLogLevel: LogLevel.info,
    includeDeviceMetadata: true,
  );

  /// Configuration preset for production environment
  static const production = LoggingConfiguration(
    enableLocalLogging: false,
    minLogLevel: LogLevel.warning,
    includeDeviceMetadata: true,
  );
}
