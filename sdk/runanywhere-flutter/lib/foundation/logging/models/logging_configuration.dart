import 'log_level.dart';

/// Configuration settings for the logging system
///
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Models/LoggingConfiguration.swift
class LoggingConfiguration {
  /// Enable local logging (console output)
  bool enableLocalLogging;

  /// Enable remote logging (telemetry)
  bool enableRemoteLogging;

  /// Remote logging endpoint
  Uri? remoteEndpoint;

  /// Minimum log level filter
  LogLevel minLogLevel;

  /// Include device metadata in remote logs
  bool includeDeviceMetadata;

  /// Maximum log entries to batch before sending
  int batchSize;

  /// Maximum time to wait before sending logs (in seconds)
  double batchInterval;

  LoggingConfiguration({
    this.enableLocalLogging = true,
    this.enableRemoteLogging = false,
    this.remoteEndpoint,
    this.minLogLevel = LogLevel.info,
    this.includeDeviceMetadata = true,
    this.batchSize = 100,
    this.batchInterval = 60,
  });

  /// Create a copy with updated values
  LoggingConfiguration copyWith({
    bool? enableLocalLogging,
    bool? enableRemoteLogging,
    Uri? remoteEndpoint,
    LogLevel? minLogLevel,
    bool? includeDeviceMetadata,
    int? batchSize,
    double? batchInterval,
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
    );
  }
}
