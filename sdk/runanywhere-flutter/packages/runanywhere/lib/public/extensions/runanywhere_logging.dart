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
    // Sentry is handled by DartBridgeTelemetry
  }

  /// Set minimum SDK log level.
  static void setLogLevel(SDKLogLevel level) {
    SDKLoggerConfig.shared.setMinLevel(level);
  }

  /// Enable / disable local console logging.
  static void setLocalLoggingEnabled(bool enabled) {
    SDKLoggerConfig.shared.setLocalLoggingEnabled(enabled);
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

/// Singleton holding the currently-configured log level +
/// local-console toggle. C++ logging is configured during
/// `DartBridge.initialize()` based on environment.
class SDKLoggerConfig {
  SDKLoggerConfig._();
  static final SDKLoggerConfig shared = SDKLoggerConfig._();

  SDKLogLevel _minLevel = SDKLogLevel.info;
  bool _localLoggingEnabled = true;

  SDKLogLevel get minLevel => _minLevel;
  bool get localLoggingEnabled => _localLoggingEnabled;

  void setMinLevel(SDKLogLevel level) {
    _minLevel = level;
  }

  void setLocalLoggingEnabled(bool enabled) {
    _localLoggingEnabled = enabled;
  }
}
