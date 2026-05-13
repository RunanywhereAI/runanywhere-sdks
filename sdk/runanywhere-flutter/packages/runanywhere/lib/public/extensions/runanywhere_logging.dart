// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_logging.dart — SDK logging configuration.
// Mirrors Swift `RunAnywhere+Logging.swift` (one-to-one method parity).
//
// Public API surface (matches Swift):
//   - configureLogging(LoggingConfiguration)
//   - setLocalLoggingEnabled(bool)
//   - setLogLevel(LogLevel)
//   - setSentryLoggingEnabled(bool)
//   - addLogDestination(LogDestination)
//   - setDebugMode(bool)
//   - flushLogs()
//
// Public types (matches Swift):
//   - LogLevel             (re-exported from foundation/logging/sdk_logger.dart)
//   - LoggingConfiguration (struct with .development/.staging/.production presets)
//   - LogDestination       (abstract sink interface)
//   - LogEntry             (single log record)

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';

/// Convert [LogLevel] to the C++ log level integer (`rac_log_level_t`).
///
/// C++ enum ordering: `TRACE=0, DEBUG=1, INFO=2, WARNING=3, ERROR=4,
/// FATAL=5`. Swift's `.fault` (the highest level) maps to C++ `FATAL`.
/// Mirrors Swift `LogLevel` raw values via the same DEBUG..FAULT order.
extension LogLevelC on LogLevel {
  int toC() {
    switch (this) {
      case LogLevel.debug:
        return 1;
      case LogLevel.info:
        return 2;
      case LogLevel.warning:
        return 3;
      case LogLevel.error:
        return 4;
      case LogLevel.fault:
        return 5;
    }
  }
}

/// Single log message with metadata. Mirrors Swift's `LogEntry`.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String category;
  final String message;
  final Map<String, String>? metadata;

  LogEntry({
    DateTime? timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// SDK logging configuration. Mirrors Swift's `LoggingConfiguration` struct.
class LoggingConfiguration {
  /// Whether local console logging is enabled.
  final bool enableLocalLogging;

  /// Minimum log level — messages below this severity are dropped.
  final LogLevel minLogLevel;

  /// Whether to attach device metadata (model, OS version, etc.) to
  /// each log entry.
  final bool includeDeviceMetadata;

  /// Whether to ship error-level events to Sentry.
  final bool enableSentryLogging;

  const LoggingConfiguration({
    this.enableLocalLogging = true,
    this.minLogLevel = LogLevel.info,
    this.includeDeviceMetadata = true,
    this.enableSentryLogging = false,
  });

  /// Development preset — verbose logging, Sentry on (matches Swift).
  static const development = LoggingConfiguration(
    enableLocalLogging: true,
    minLogLevel: LogLevel.debug,
    includeDeviceMetadata: false,
    enableSentryLogging: true,
  );

  /// Staging preset — info-level logging, Sentry off (matches Swift).
  static const staging = LoggingConfiguration(
    enableLocalLogging: true,
    minLogLevel: LogLevel.info,
    includeDeviceMetadata: true,
    enableSentryLogging: false,
  );

  /// Production preset — warnings + errors only, local logging off,
  /// Sentry off (matches Swift).
  static const production = LoggingConfiguration(
    enableLocalLogging: false,
    minLogLevel: LogLevel.warning,
    includeDeviceMetadata: true,
    enableSentryLogging: false,
  );
}

/// A pluggable log sink. Implement this to route SDK logs to your own
/// telemetry/file/network destination. Mirrors Swift's `LogDestination`
/// protocol.
abstract class LogDestination {
  /// Stable identifier for this destination (e.g. `"console"`,
  /// `"sentry"`, `"file"`). Used to deduplicate registrations.
  String get identifier;

  /// Whether this destination is currently available (e.g. network
  /// reachable, file handle open).
  bool get isAvailable;

  /// Receive a single log record.
  void write(LogEntry entry);

  /// Force-flush any buffered records.
  void flush();
}

/// Static helpers for configuring SDK logging.
///
/// One-to-one parity with Swift's `extension RunAnywhere` in
/// `RunAnywhere+Logging.swift`. Swift defines these as static functions
/// on the `RunAnywhere` enum; Dart has no static extensions on free
/// types, so we expose the same surface via a non-instantiable
/// `RunAnywhereLogging` class.
class RunAnywhereLogging {
  RunAnywhereLogging._();

  // MARK: - Logging Configuration

  /// Configure logging with a predefined configuration.
  /// Mirrors Swift's `configureLogging(_:)`.
  static void configureLogging(LoggingConfiguration config) {
    SDKLoggerConfig.shared.configure(config);
  }

  /// Enable or disable local console logging.
  /// Mirrors Swift's `setLocalLoggingEnabled(_:)`.
  static void setLocalLoggingEnabled(bool enabled) {
    SDKLoggerConfig.shared.setLocalLoggingEnabled(enabled);
  }

  /// Set minimum log level for SDK logging.
  /// Mirrors Swift's `setLogLevel(_:)`.
  static void setLogLevel(LogLevel level) {
    SDKLoggerConfig.shared.setMinLogLevel(level);
  }

  /// Enable or disable Sentry error tracking.
  /// Mirrors Swift's `setSentryLoggingEnabled(_:)`.
  static void setSentryLoggingEnabled(bool enabled) {
    SDKLoggerConfig.shared.setSentryLoggingEnabled(enabled);
  }

  /// Add a custom log destination.
  /// Mirrors Swift's `addLogDestination(_:)`. Destinations receive every
  /// log record after filtering by [LogLevel].
  static void addLogDestination(LogDestination destination) {
    SDKLoggerConfig.shared.addDestination(destination);
  }

  /// Remove a previously-registered log destination.
  ///
  /// Flutter-specific extension: Swift's `Logging.shared` exposes a
  /// remove-by-identifier method internally but does not surface a
  /// public removal API in `RunAnywhere+Logging.swift`. We keep this
  /// for symmetry with `addLogDestination` because Dart does not have
  /// destination management hooks elsewhere on the public surface.
  static void removeLogDestination(LogDestination destination) {
    SDKLoggerConfig.shared.removeDestination(destination);
  }

  // MARK: - Debugging Helpers

  /// Enable verbose debugging mode.
  /// Mirrors Swift's `setDebugMode(_:)`.
  static void setDebugMode(bool enabled) {
    setLogLevel(enabled ? LogLevel.debug : LogLevel.info);
    setLocalLoggingEnabled(enabled);
  }

  /// Force flush all pending logs to destinations.
  /// Mirrors Swift's `flushLogs()`.
  static void flushLogs() {
    for (final destination in SDKLoggerConfig.shared.destinations) {
      destination.flush();
    }
    DartBridgeTelemetry.flush();
  }
}

/// Singleton holding the currently-configured logging configuration +
/// registered destinations. C++ logging is configured during
/// `DartBridge.initialize()` based on environment.
class SDKLoggerConfig {
  SDKLoggerConfig._();
  static final SDKLoggerConfig shared = SDKLoggerConfig._();

  LoggingConfiguration _configuration = const LoggingConfiguration();
  final List<LogDestination> _destinations = <LogDestination>[];

  LoggingConfiguration get configuration => _configuration;
  List<LogDestination> get destinations =>
      List<LogDestination>.unmodifiable(_destinations);

  void configure(LoggingConfiguration config) {
    _configuration = config;
  }

  void setMinLogLevel(LogLevel level) {
    _configuration = LoggingConfiguration(
      enableLocalLogging: _configuration.enableLocalLogging,
      minLogLevel: level,
      includeDeviceMetadata: _configuration.includeDeviceMetadata,
      enableSentryLogging: _configuration.enableSentryLogging,
    );
  }

  void setLocalLoggingEnabled(bool enabled) {
    _configuration = LoggingConfiguration(
      enableLocalLogging: enabled,
      minLogLevel: _configuration.minLogLevel,
      includeDeviceMetadata: _configuration.includeDeviceMetadata,
      enableSentryLogging: _configuration.enableSentryLogging,
    );
  }

  void setSentryLoggingEnabled(bool enabled) {
    _configuration = LoggingConfiguration(
      enableLocalLogging: _configuration.enableLocalLogging,
      minLogLevel: _configuration.minLogLevel,
      includeDeviceMetadata: _configuration.includeDeviceMetadata,
      enableSentryLogging: enabled,
    );
  }

  void addDestination(LogDestination destination) {
    if (!_destinations.any((d) => d.identifier == destination.identifier)) {
      _destinations.add(destination);
    }
  }

  void removeDestination(LogDestination destination) {
    _destinations.removeWhere((d) => d.identifier == destination.identifier);
  }
}
