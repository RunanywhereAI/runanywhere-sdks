// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_logging.dart — SDK logging configuration.
// Mirrors Swift `RunAnywhere+Logging.swift`.

import 'package:runanywhere/native/dart_bridge_telemetry.dart';

/// SDK log levels.
enum SDKLogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  fatal;

  /// Convert to the C++ log level integer (matches the native enum).
  int toC() {
    switch (this) {
      case SDKLogLevel.trace:
        return 0;
      case SDKLogLevel.debug:
        return 1;
      case SDKLogLevel.info:
        return 2;
      case SDKLogLevel.warning:
        return 3;
      case SDKLogLevel.error:
        return 4;
      case SDKLogLevel.fatal:
        return 5;
    }
  }
}

/// SDK logging configuration.
class LoggingConfiguration {
  final SDKLogLevel minimumLevel;
  final bool localLoggingEnabled;
  final bool sentryEnabled;

  const LoggingConfiguration({
    this.minimumLevel = SDKLogLevel.info,
    this.localLoggingEnabled = true,
    this.sentryEnabled = false,
  });

  /// Development preset — verbose logging, no Sentry.
  static const development = LoggingConfiguration(
    minimumLevel: SDKLogLevel.debug,
    localLoggingEnabled: true,
    sentryEnabled: false,
  );

  /// Production preset — minimal logging, Sentry on.
  static const production = LoggingConfiguration(
    minimumLevel: SDKLogLevel.warning,
    localLoggingEnabled: false,
    sentryEnabled: true,
  );
}

/// Static helpers for configuring SDK logging.
class RunAnywhereLogging {
  RunAnywhereLogging._();

  /// Apply a predefined [LoggingConfiguration].
  static void configureLogging(LoggingConfiguration config) {
    setLogLevel(config.minimumLevel);
    setLocalLoggingEnabled(config.localLoggingEnabled);
    setSentryLoggingEnabled(config.sentryEnabled);
  }

  /// Set minimum SDK log level.
  static void setLogLevel(SDKLogLevel level) {
    SDKLoggerConfig.shared.setMinLevel(level);
  }

  /// Enable / disable local console logging.
  static void setLocalLoggingEnabled(bool enabled) {
    SDKLoggerConfig.shared.setLocalLoggingEnabled(enabled);
  }

  /// Enable / disable Sentry error reporting. Mirrors Swift's
  /// `setSentryLoggingEnabled(_:)`.
  static void setSentryLoggingEnabled(bool enabled) {
    SDKLoggerConfig.shared.setSentryEnabled(enabled);
  }

  /// Register an additional log destination (file, network, custom
  /// sink). Mirrors Swift's `addLogDestination(_:)`. Destinations
  /// receive every log record after filtering by [SDKLogLevel].
  static void addLogDestination(LogDestination destination) {
    SDKLoggerConfig.shared.addDestination(destination);
  }

  /// Remove a previously-registered log destination.
  static void removeLogDestination(LogDestination destination) {
    SDKLoggerConfig.shared.removeDestination(destination);
  }

  /// Convenience: enable / disable verbose debug logging.
  static void setDebugMode(bool enabled) {
    setLogLevel(enabled ? SDKLogLevel.debug : SDKLogLevel.info);
    setLocalLoggingEnabled(enabled);
  }

  /// Flush any pending log buffers.
  static void flushLogs() {
    DartBridgeTelemetry.flush();
  }
}

/// A pluggable log sink. Implement this to route SDK logs to your own
/// telemetry/file/network destination. Mirrors Swift's `LogDestination`.
abstract class LogDestination {
  /// Receives a single log record.
  void write({
    required SDKLogLevel level,
    required String category,
    required String message,
    DateTime? timestamp,
  });
}

/// Singleton holding the currently-configured log level +
/// local-console toggle. C++ logging is configured during
/// `DartBridge.initialize()` based on environment.
class SDKLoggerConfig {
  SDKLoggerConfig._();
  static final SDKLoggerConfig shared = SDKLoggerConfig._();

  SDKLogLevel _minLevel = SDKLogLevel.info;
  bool _localLoggingEnabled = true;
  bool _sentryEnabled = false;
  final List<LogDestination> _destinations = <LogDestination>[];

  SDKLogLevel get minLevel => _minLevel;
  bool get localLoggingEnabled => _localLoggingEnabled;
  bool get sentryEnabled => _sentryEnabled;
  List<LogDestination> get destinations =>
      List<LogDestination>.unmodifiable(_destinations);

  void setMinLevel(SDKLogLevel level) {
    _minLevel = level;
  }

  void setLocalLoggingEnabled(bool enabled) {
    _localLoggingEnabled = enabled;
  }

  void setSentryEnabled(bool enabled) {
    _sentryEnabled = enabled;
  }

  void addDestination(LogDestination destination) {
    if (!_destinations.contains(destination)) {
      _destinations.add(destination);
    }
  }

  void removeDestination(LogDestination destination) {
    _destinations.remove(destination);
  }
}
