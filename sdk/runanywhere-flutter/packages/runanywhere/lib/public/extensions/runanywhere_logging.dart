// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_logging.dart — SDK logging configuration.
// Mirrors Swift `RunAnywhere+Logging.swift` (one-to-one method parity).
//
// Public API surface (matches Swift):
//   - configureLogging(LoggingConfiguration)
//   - setLocalLoggingEnabled(bool)
//   - setLogLevel(LogLevel)
//   - addLogDestination(LogDestination)
//   - setDebugMode(bool)
//   - flushLogs()
//
// Public types:
//   - LogLevel             (generated, re-exported via sdk_logger.dart)
//   - LoggingConfiguration (generated proto message; per-environment presets
//                           live as factory helpers on LoggingConfigurations)
//   - LogEntry             (generated proto message — single log record)
//   - LogDestination       (hand-written host-side sink interface)
//
// The central service (`SDKLoggerConfig`), the `LogDestination` interface,
// the `ConsoleLogDestination` default sink, and the `LoggingConfigurations`
// presets live in `foundation/logging/sdk_logger.dart` — mirroring Swift,
// where `Logging`, `LogDestination`, and the configuration presets all live
// in `Infrastructure/Logging/SDKLogger.swift` and the public
// `RunAnywhere+Logging.swift` extension only delegates. Re-exported here so
// existing imports keep resolving.

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/logging.pb.dart'
    show LoggingConfiguration;
import 'package:runanywhere/native/dart_bridge_telemetry.dart';

export 'package:runanywhere/foundation/logging/sdk_logger.dart'
    show
        ConsoleLogDestination,
        LogDestination,
        LoggingConfigurations,
        SDKLoggerConfig;
export 'package:runanywhere/generated/logging.pb.dart'
    show LogEntry, LoggingConfiguration;

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
    setLogLevel(enabled ? LogLevel.LOG_LEVEL_DEBUG : LogLevel.LOG_LEVEL_INFO);
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
