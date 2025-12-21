import 'package:runanywhere/foundation/logging/models/log_entry.dart';
import 'package:runanywhere/foundation/logging/models/log_level.dart';
import 'package:runanywhere/foundation/logging/models/logging_configuration.dart';
import 'package:runanywhere/infrastructure/logging/protocol/log_destination.dart';

/// Protocol defining logging service capabilities
/// Implementations provide log routing, filtering, and destination management
/// Matches iOS LoggingService from Infrastructure/Logging/Protocol/LoggingService.swift
abstract class LoggingService {
  /// Current logging configuration
  LoggingConfiguration get configuration;
  set configuration(LoggingConfiguration config);

  /// Update logging configuration
  void configure(LoggingConfiguration config);

  /// Log a message with the specified level and metadata
  void log({
    required LogLevel level,
    required String category,
    required String message,
    Map<String, dynamic>? metadata,
  });

  /// Register a log destination
  void addDestination(LogDestination destination);

  /// Remove a log destination
  void removeDestination(LogDestination destination);

  /// Get all registered destinations
  List<LogDestination> get destinations;

  /// Force flush all pending logs to all destinations
  void flush();
}

/// Default implementation of LoggingService
class DefaultLoggingService implements LoggingService {
  @override
  LoggingConfiguration configuration;

  final List<LogDestination> _destinations = [];

  DefaultLoggingService({
    LoggingConfiguration? configuration,
  }) : configuration = configuration ?? const LoggingConfiguration();

  @override
  void configure(LoggingConfiguration config) {
    configuration = config;
  }

  @override
  void log({
    required LogLevel level,
    required String category,
    required String message,
    Map<String, dynamic>? metadata,
  }) {
    // Check minimum log level
    if (level.index < configuration.minimumLevel.index) {
      return;
    }

    // Check category filter if enabled
    if (configuration.categoryFilter != null &&
        !configuration.categoryFilter!.contains(category)) {
      return;
    }

    final entry = LogEntry(
      level: level,
      category: category,
      message: message,
      timestamp: DateTime.now(),
      metadata: metadata,
    );

    // Write to all destinations
    for (final destination in _destinations) {
      if (destination.isAvailable) {
        destination.write(entry);
      }
    }
  }

  @override
  void addDestination(LogDestination destination) {
    if (!_destinations.contains(destination)) {
      _destinations.add(destination);
    }
  }

  @override
  void removeDestination(LogDestination destination) {
    _destinations.remove(destination);
  }

  @override
  List<LogDestination> get destinations => List.unmodifiable(_destinations);

  @override
  void flush() {
    for (final destination in _destinations) {
      destination.flush();
    }
  }
}
