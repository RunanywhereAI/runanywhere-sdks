/// RunAnywhere + Logging
///
/// Public API for configuring SDK logging.
/// Mirrors Swift's RunAnywhere+Logging.swift.
library runanywhere_logging;

import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/public/runanywhere.dart';

// =============================================================================
// Log Level Enum
// =============================================================================

/// SDK Log levels
enum SDKLogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  fatal;

  /// Convert to C++ log level
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

// =============================================================================
// Logging Configuration
// =============================================================================

/// Configuration for SDK logging
class LoggingConfiguration {
  final SDKLogLevel minimumLevel;
  final bool localLoggingEnabled;
  final bool sentryEnabled;

  const LoggingConfiguration({
    this.minimumLevel = SDKLogLevel.info,
    this.localLoggingEnabled = true,
    this.sentryEnabled = false,
  });

  /// Development configuration - verbose logging
  static const development = LoggingConfiguration(
    minimumLevel: SDKLogLevel.debug,
    localLoggingEnabled: true,
    sentryEnabled: false,
  );

  /// Production configuration - minimal logging
  static const production = LoggingConfiguration(
    minimumLevel: SDKLogLevel.warning,
    localLoggingEnabled: false,
    sentryEnabled: true,
  );
}

// =============================================================================
// RunAnywhere Logging Extensions
// =============================================================================

/// Extension methods for logging configuration
extension RunAnywhereLogging on RunAnywhere {
  /// Configure logging with a predefined configuration
  static void configureLogging(LoggingConfiguration config) {
    setLogLevel(config.minimumLevel);
    setLocalLoggingEnabled(config.localLoggingEnabled);
    // Sentry is handled by DartBridgeTelemetry
  }

  /// Set minimum log level for SDK logging
  static void setLogLevel(SDKLogLevel level) {
    SDKLoggerConfig.shared.setMinLevel(level);
  }

  /// Enable or disable local console logging
  static void setLocalLoggingEnabled(bool enabled) {
    SDKLoggerConfig.shared.setLocalLoggingEnabled(enabled);
  }

  /// Enable verbose debugging mode
  static void setDebugMode(bool enabled) {
    setLogLevel(enabled ? SDKLogLevel.debug : SDKLogLevel.info);
    setLocalLoggingEnabled(enabled);
  }

  /// Force flush all pending logs
  static void flushLogs() {
    DartBridgeTelemetry.flush();
  }
}

// =============================================================================
// SDK Logger Configuration
// =============================================================================

/// Singleton for SDK logger configuration
class SDKLoggerConfig {
  static final SDKLoggerConfig shared = SDKLoggerConfig._();

  SDKLoggerConfig._();

  SDKLogLevel _minLevel = SDKLogLevel.info;
  bool _localLoggingEnabled = true;

  SDKLogLevel get minLevel => _minLevel;
  bool get localLoggingEnabled => _localLoggingEnabled;

  void setMinLevel(SDKLogLevel level) {
    _minLevel = level;
    // C++ logging is configured during DartBridge.initialize() based on environment
    // Re-initializing here is not needed as the level is set on the Dart side
  }

  void setLocalLoggingEnabled(bool enabled) {
    _localLoggingEnabled = enabled;
  }
}
