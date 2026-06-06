/// SDK Logger
///
/// Centralized logging utility.
/// Matches iOS SDKLogger from Foundation/Logging/SDKLogger.swift
library;

import 'package:runanywhere/generated/logging.pbenum.dart' show LogLevel;

// Re-export the canonical generated severity enum so the ~40 call sites that
// `import '.../sdk_logger.dart'` keep resolving `LogLevel`. The hand-written
// `enum LogLevel { debug, info, warning, error, fault }` was deleted in favour
// of the generated `LogLevel` (LOG_LEVEL_TRACE = 0 … LOG_LEVEL_FATAL = 5).
export 'package:runanywhere/generated/logging.pbenum.dart' show LogLevel;

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
    _log(LogLevel.LOG_LEVEL_DEBUG, message, metadata: metadata);
  }

  /// Log an info message
  void info(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.LOG_LEVEL_INFO, message, metadata: metadata);
  }

  /// Log a warning message
  void warning(String message, {Map<String, dynamic>? metadata}) {
    _log(LogLevel.LOG_LEVEL_WARNING, message, metadata: metadata);
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

    _log(LogLevel.LOG_LEVEL_ERROR, message, metadata: enrichedMetadata);
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

    // `fault` is the legacy name; the generated enum's highest severity is
    // LOG_LEVEL_FATAL.
    _log(LogLevel.LOG_LEVEL_FATAL, message, metadata: enrichedMetadata);
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

    _log(LogLevel.LOG_LEVEL_INFO, '$metric: $value',
        metadata: enrichedMetadata);
  }

  // MARK: - Private Methods

  void _log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    final timestamp = DateTime.now().toIso8601String();
    // Generated enum names are `LOG_LEVEL_<SEVERITY>`; strip the prefix for a
    // readable console tag (e.g. `DEBUG`).
    final levelStr = level.name.replaceFirst('LOG_LEVEL_', '');

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
