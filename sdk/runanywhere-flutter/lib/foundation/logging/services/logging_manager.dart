import 'dart:developer' as developer;

import '../models/log_entry.dart';
import '../models/log_level.dart';
import '../models/logging_configuration.dart';
import '../models/sensitive_data_policy.dart';
import '../../../public/configuration/sdk_environment.dart';
import 'log_batcher.dart';

/// Centralized logging manager for the SDK
///
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Services/LoggingManager.swift
class LoggingManager {
  // Singleton
  static final LoggingManager shared = LoggingManager._();

  LoggingManager._() {
    _applyEnvironmentConfiguration();
  }

  /// Current logging configuration
  LoggingConfiguration configuration = LoggingConfiguration();

  /// SDK Environment (set during SDK initialization)
  SDKEnvironment _environment = SDKEnvironment.production;

  /// Set the SDK environment
  void setEnvironment(SDKEnvironment environment) {
    _environment = environment;
    _applyEnvironmentConfiguration();
  }

  /// Log batcher for remote submission
  LogBatcher? _batcher;

  // MARK: - Public Methods

  /// Update logging configuration
  void configure(LoggingConfiguration config) {
    configuration = config;
    _updateBatcher();
  }

  /// Configure SDK logging endpoint (for SDK team debugging)
  void configureSDKLogging({Uri? endpoint, bool enabled = true}) {
    configuration = configuration.copyWith(
      remoteEndpoint: endpoint,
      enableRemoteLogging: enabled && endpoint != null,
    );
    _updateBatcher();

    // Log configuration change
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      category: 'LoggingManager',
      message: 'SDK logging configured: ${enabled ? "enabled" : "disabled"}',
    );
    _logToConsole(entry, isSensitive: false);
  }

  /// Log a message with the specified level and metadata
  void log({
    required LogLevel level,
    required String category,
    required String message,
    Map<String, dynamic>? metadata,
  }) {
    // Check against SDK configuration minimum log level
    if (level.value < configuration.minLogLevel.value) return;

    // Check if this contains sensitive data
    final isSensitive = _checkIfSensitive(metadata);

    // Create log entry
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      metadata: metadata,
      deviceInfo:
          configuration.includeDeviceMetadata ? _getCurrentDeviceInfo() : null,
    );

    // Local logging
    if (configuration.enableLocalLogging) {
      _logToConsole(entry, isSensitive: isSensitive);
    }

    // Remote logging - ONLY if not sensitive
    if (configuration.enableRemoteLogging && !isSensitive) {
      _batcher?.add(entry);
    }
  }

  /// Force flush all pending logs
  void flush() {
    _batcher?.flush();
  }

  // MARK: - Private Methods

  void _logToConsole(LogEntry entry, {required bool isSensitive}) {
    final levelEmoji = _levelEmoji(entry.level);
    final sensitiveMarker = isSensitive ? ' [SENSITIVE]' : '';
    final metadataStr = _formatMetadata(entry.metadata);

    final logMessage =
        '$levelEmoji [${entry.category}]$sensitiveMarker ${entry.message}$metadataStr';

    // Use dart:developer log for structured output
    developer.log(
      logMessage,
      name: entry.category,
      level: _developerLogLevel(entry.level),
      time: entry.timestamp,
    );
  }

  String _levelEmoji(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '[DEBUG]';
      case LogLevel.info:
        return '[INFO]';
      case LogLevel.warning:
        return '[WARN]';
      case LogLevel.error:
        return '[ERROR]';
      case LogLevel.fault:
        return '[FAULT]';
    }
  }

  int _developerLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
      case LogLevel.fault:
        return 1200;
    }
  }

  String _formatMetadata(Map<String, String>? metadata) {
    if (metadata == null || metadata.isEmpty) return '';

    // Filter out internal markers
    final filtered = Map.fromEntries(
      metadata.entries.where((e) => !e.key.startsWith('__')),
    );

    if (filtered.isEmpty) return '';

    return ' | ${filtered.entries.map((e) => '${e.key}=${e.value}').join(', ')}';
  }

  bool _checkIfSensitive(Map<String, dynamic>? metadata) {
    if (metadata == null) return false;

    // Check for sensitive data markers
    if (metadata.containsKey(LogMetadataKeys.sensitiveDataPolicy)) {
      return true;
    }

    if (metadata.containsKey(LogMetadataKeys.sensitiveDataCategory)) {
      return true;
    }

    return false;
  }

  DeviceInfo? _getCurrentDeviceInfo() {
    // Return mock device info for now
    // TODO: Implement actual device info collection via platform channel
    return null;
  }

  void _applyEnvironmentConfiguration() {
    // Set defaults based on environment
    switch (_environment) {
      case SDKEnvironment.development:
        configuration = configuration.copyWith(
          enableLocalLogging: true,
          enableRemoteLogging: false,
          minLogLevel: LogLevel.debug,
          includeDeviceMetadata: false,
        );
      case SDKEnvironment.staging:
        configuration = configuration.copyWith(
          enableLocalLogging: false,
          enableRemoteLogging: true,
          minLogLevel: LogLevel.info,
          includeDeviceMetadata: true,
        );
      case SDKEnvironment.production:
        configuration = configuration.copyWith(
          enableLocalLogging: false,
          enableRemoteLogging: true,
          minLogLevel: LogLevel.warning,
          includeDeviceMetadata: true,
        );
    }

    _updateBatcher();

    // Log current environment for debugging
    if (_environment == SDKEnvironment.development) {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        category: 'LoggingManager',
        message:
            'Running in ${_environment.name} environment - Remote: ${configuration.enableRemoteLogging}, MinLevel: ${configuration.minLogLevel}',
      );
      _logToConsole(entry, isSensitive: false);
    }
  }

  void _updateBatcher() {
    if (configuration.enableRemoteLogging) {
      _batcher ??= LogBatcher(
        configuration: configuration,
        onBatchReady: _handleBatchReady,
      );
      _batcher!.updateConfiguration(configuration);
    } else {
      _batcher?.dispose();
      _batcher = null;
    }
  }

  void _handleBatchReady(List<LogEntry> entries) {
    // TODO: Implement remote logging submission
    // This will be replaced with external service (e.g., Sentry, DataDog)
  }
}
