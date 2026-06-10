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
// Public types:
//   - LogLevel             (generated, re-exported via sdk_logger.dart)
//   - LoggingConfiguration (generated proto message; per-environment presets
//                           below stay in Dart as factory helpers)
//   - LogEntry             (generated proto message — single log record)
//   - LogDestination       (hand-written host-side sink interface)

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/logging.pb.dart'
    show LoggingConfiguration, LogEntry;
import 'package:runanywhere/native/dart_bridge_telemetry.dart';

/// Per-environment [LoggingConfiguration] presets. The generated proto message
/// cannot be `const`-constructed, so the development/staging/production presets
/// that used to be `static const` fields on the hand-written class now live
/// here as factory helpers (mirrors Swift's environment factory helpers).
class LoggingConfigurations {
  LoggingConfigurations._();

  /// Default configuration: local logging on, INFO floor, device metadata on,
  /// Sentry off. Replaces the old `const LoggingConfiguration()` default.
  static LoggingConfiguration get defaults => LoggingConfiguration(
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_INFO,
        includeDeviceMetadata: true,
        enableSentryLogging: false,
      );

  /// Development preset — verbose logging, Sentry on (matches Swift).
  static LoggingConfiguration get development => LoggingConfiguration(
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_DEBUG,
        includeDeviceMetadata: false,
        enableSentryLogging: true,
      );

  /// Staging preset — info-level logging, Sentry off (matches Swift).
  static LoggingConfiguration get staging => LoggingConfiguration(
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_INFO,
        includeDeviceMetadata: true,
        enableSentryLogging: false,
      );

  /// Production preset — warnings + errors only, local logging off,
  /// Sentry off (matches Swift).
  static LoggingConfiguration get production => LoggingConfiguration(
        enableLocalLogging: false,
        minLogLevel: LogLevel.LOG_LEVEL_WARNING,
        includeDeviceMetadata: true,
        enableSentryLogging: false,
      );
}

/// A pluggable log sink. Implement this to route SDK logs to your own
/// telemetry/file/network destination. Mirrors Swift's `LogDestination`
/// protocol. This is a host-side interface (carries no wire payload) and so
/// stays hand-written rather than moving to the proto contract.
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
    setLogLevel(
        enabled ? LogLevel.LOG_LEVEL_DEBUG : LogLevel.LOG_LEVEL_INFO);
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

  LoggingConfiguration _configuration = LoggingConfigurations.defaults;
  final List<LogDestination> _destinations = <LogDestination>[];

  LoggingConfiguration get configuration => _configuration;
  List<LogDestination> get destinations =>
      List<LogDestination>.unmodifiable(_destinations);

  void configure(LoggingConfiguration config) {
    _configuration = config;
  }

  void setMinLogLevel(LogLevel level) {
    _configuration = _configuration.deepCopy()..minLogLevel = level;
  }

  void setLocalLoggingEnabled(bool enabled) {
    _configuration = _configuration.deepCopy()..enableLocalLogging = enabled;
  }

  void setSentryLoggingEnabled(bool enabled) {
    _configuration = _configuration.deepCopy()..enableSentryLogging = enabled;
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
