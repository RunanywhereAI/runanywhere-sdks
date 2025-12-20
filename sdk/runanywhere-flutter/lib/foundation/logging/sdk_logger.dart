import 'models/log_level.dart';
import 'models/sensitive_data_policy.dart';
import 'services/logging_manager.dart';

/// Centralized logging utility with sensitive data protection
///
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Logger/SDKLogger.swift
class SDKLogger {
  final String category;

  SDKLogger({this.category = 'SDK'});

  // MARK: - Standard Logging Methods

  /// Log a debug message
  void debug(String message, {Map<String, dynamic>? metadata}) {
    LoggingManager.shared.log(
      level: LogLevel.debug,
      category: category,
      message: message,
      metadata: metadata,
    );
  }

  /// Log an info message
  void info(String message, {Map<String, dynamic>? metadata}) {
    LoggingManager.shared.log(
      level: LogLevel.info,
      category: category,
      message: message,
      metadata: metadata,
    );
  }

  /// Log a warning message
  void warning(String message, {Map<String, dynamic>? metadata}) {
    LoggingManager.shared.log(
      level: LogLevel.warning,
      category: category,
      message: message,
      metadata: metadata,
    );
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

    LoggingManager.shared.log(
      level: LogLevel.error,
      category: category,
      message: message,
      metadata: enrichedMetadata,
    );
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

    LoggingManager.shared.log(
      level: LogLevel.fault,
      category: category,
      message: message,
      metadata: enrichedMetadata,
    );
  }

  /// Log a message with a specific level
  void log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    LoggingManager.shared.log(
      level: level,
      category: category,
      message: message,
      metadata: metadata,
    );
  }

  // MARK: - Sensitive Data Logging

  /// Log a debug message with sensitive data protection
  void debugSensitive(
    String message, {
    required SensitiveDataCategory sensitiveCategory,
    Map<String, dynamic>? metadata,
  }) {
    _logSensitive(
      level: LogLevel.debug,
      message: message,
      sensitiveCategory: sensitiveCategory,
      metadata: metadata,
    );
  }

  /// Log an info message with sensitive data protection
  void infoSensitive(
    String message, {
    required SensitiveDataCategory sensitiveCategory,
    Map<String, dynamic>? metadata,
  }) {
    _logSensitive(
      level: LogLevel.info,
      message: message,
      sensitiveCategory: sensitiveCategory,
      metadata: metadata,
    );
  }

  /// Log a warning message with sensitive data protection
  void warningSensitive(
    String message, {
    required SensitiveDataCategory sensitiveCategory,
    Map<String, dynamic>? metadata,
  }) {
    _logSensitive(
      level: LogLevel.warning,
      message: message,
      sensitiveCategory: sensitiveCategory,
      metadata: metadata,
    );
  }

  /// Log an error message with sensitive data protection
  void errorSensitive(
    String message, {
    required SensitiveDataCategory sensitiveCategory,
    Map<String, dynamic>? metadata,
  }) {
    _logSensitive(
      level: LogLevel.error,
      message: message,
      sensitiveCategory: sensitiveCategory,
      metadata: metadata,
    );
  }

  /// Log sensitive data with appropriate protection
  void _logSensitive({
    required LogLevel level,
    required String message,
    required SensitiveDataCategory sensitiveCategory,
    Map<String, dynamic>? metadata,
  }) {
    final enrichedMetadata = metadata ?? <String, dynamic>{};
    enrichedMetadata[LogMetadataKeys.sensitiveDataCategory] =
        sensitiveCategory.name;
    enrichedMetadata[LogMetadataKeys.sensitiveDataPolicy] =
        sensitiveCategory.defaultPolicy.name;

    // Sanitize message based on policy
    final sanitizedMessage = _sanitizeMessage(message, sensitiveCategory);

    LoggingManager.shared.log(
      level: level,
      category: category,
      message: sanitizedMessage,
      metadata: enrichedMetadata,
    );
  }

  // MARK: - Performance Logging

  /// Log performance metrics
  void performance(String metric, double value,
      {Map<String, dynamic>? metadata}) {
    final enrichedMetadata = metadata ?? <String, dynamic>{};
    enrichedMetadata['metric'] = metric;
    enrichedMetadata['value'] = value;
    enrichedMetadata['type'] = 'performance';

    LoggingManager.shared.log(
      level: LogLevel.info,
      category: '$category.Performance',
      message: '$metric: $value',
      metadata: enrichedMetadata,
    );
  }

  // MARK: - Private Methods

  String _sanitizeMessage(
      String message, SensitiveDataCategory sensitiveCategory) {
    final policy = sensitiveCategory.defaultPolicy;

    switch (policy) {
      case SensitiveDataPolicy.none:
        return message;
      case SensitiveDataPolicy.sensitive:
        // In production, replace with placeholder
        // For now, show full message (would check kDebugMode in release)
        return message;
      case SensitiveDataPolicy.critical:
        return sensitiveCategory.sanitizedPlaceholder;
      case SensitiveDataPolicy.redacted:
        return '[REDACTED]';
    }
  }
}
