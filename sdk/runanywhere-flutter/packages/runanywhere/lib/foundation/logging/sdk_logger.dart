/// SDK Logger
///
/// Centralized logging utility.
/// Matches iOS SDKLogger from Foundation/Logging/SDKLogger.swift
library sdk_logger;

/// Log levels
enum LogLevel {
  debug,
  info,
  warning,
  error,
  fault,
}

/// Centralized logging utility
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Logger/SDKLogger.swift
class SDKLogger {
  final String category;

  /// Create a logger with the specified category
  /// [category] - The log category (e.g., 'DartBridge.Auth')
  SDKLogger([this.category = 'SDK']);

  // MARK: - Standard Logging Methods

  /// Log a debug message
  void debug(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.debug, message, metadata: metadata);
  }

  /// Log an info message
  void info(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.info, message, metadata: metadata);
  }

  /// Log a warning message
  void warning(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.warning, message, metadata: metadata);
  }

  /// Log an error message
  void error(String message,
      {Object? error, StackTrace? stackTrace, Map<String, dynamic>? metadata}) {
    final enrichedMetadata = metadata ?? <String, dynamic>{};
    if (error != null) {
      enrichedMetadata['error'] = error.toString();
    }
    if (stackTrace != null) {
      enrichedMetadata['stackTrace'] = stackTrace.toString();
    }

    _log(LogLevel.error, message, metadata: enrichedMetadata);
  }

  /// Log a fault message (highest severity)
  void fault(String message,
      {Object? error, StackTrace? stackTrace, Map<String, dynamic>? metadata}) {
    final enrichedMetadata = metadata ?? <String, dynamic>{};
    if (error != null) {
      enrichedMetadata['error'] = error.toString();
    }
    if (stackTrace != null) {
      enrichedMetadata['stackTrace'] = stackTrace.toString();
    }

    _log(LogLevel.fault, message, metadata: enrichedMetadata);
  }

  /// Log a message with a specific level
  void log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    _log(level, message, metadata: metadata);
  }

  // MARK: - Performance Logging

  /// Log performance metrics
  void performance(String metric, double value,
      {Map<String, dynamic>? metadata}) {
    final enrichedMetadata = metadata ?? <String, dynamic>{};
    enrichedMetadata['metric'] = metric;
    enrichedMetadata['value'] = value;
    enrichedMetadata['type'] = 'performance';

    _log(LogLevel.info, '$metric: $value', metadata: enrichedMetadata);
  }

  // MARK: - Private Methods

  void _log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    final timestamp = DateTime.now().toIso8601String();
    final levelStr = level.name.toUpperCase();

    // For now, just print to console
    // In production, this would route to native logging via FFI
    // ignore: avoid_print
    print('[$timestamp] [$levelStr] [$category] $message');

    if (metadata != null && metadata.isNotEmpty) {
      // ignore: avoid_print
      print('  metadata: $metadata');
    }
  }
}
