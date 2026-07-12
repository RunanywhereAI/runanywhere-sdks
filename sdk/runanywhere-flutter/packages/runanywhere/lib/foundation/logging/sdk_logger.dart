/// SDK Logger
///
/// Centralized logging utility with multi-destination support.
/// Matches iOS `Infrastructure/Logging/SDKLogger.swift`, which hosts the
/// central `Logging` service, the `LogDestination` protocol, the
/// per-environment `RALoggingConfiguration` presets, and the `SDKLogger`
/// convenience wrapper in a single file. The Dart equivalents live here:
///   - [SDKLoggerConfig]      <-> Swift `Logging` (central service)
///   - [LogDestination]       <-> Swift `LogDestination` protocol
///   - [ConsoleLogDestination]<-> Swift `printToConsole` (console sink)
///   - [LoggingConfigurations]<-> Swift `RALoggingConfiguration` presets
///   - [SDKLogger]            <-> Swift `SDKLogger` (convenience wrapper)
library;

import 'package:fixnum/fixnum.dart' show Int64;
import 'package:runanywhere/generated/logging.pb.dart'
    show
        GeneratedMessageGenericExtensions,
        LogEntry,
        LogLevel,
        LoggingConfiguration;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show SDKEnvironment;

// Re-export the canonical generated severity enum so the ~40 call sites that
// `import '.../sdk_logger.dart'` keep resolving `LogLevel`. The hand-written
// `enum LogLevel { debug, info, warning, error, fault }` was deleted in favour
// of the generated `LogLevel` (LOG_LEVEL_TRACE = 0 … LOG_LEVEL_FATAL = 5).
export 'package:runanywhere/generated/logging.pbenum.dart' show LogLevel;

/// Per-environment [LoggingConfiguration] presets. The generated proto message
/// cannot be `const`-constructed, so the development/staging/production presets
/// live here as factory helpers (mirrors Swift's `RALoggingConfiguration`
/// extension in `SDKLogger.swift`).
class LoggingConfigurations {
  LoggingConfigurations._();

  /// Default configuration: local logging on, INFO floor, device metadata on.
  static LoggingConfiguration get defaults => LoggingConfiguration(
    enableLocalLogging: true,
    minLogLevel: LogLevel.LOG_LEVEL_INFO,
    includeDeviceMetadata: true,
  );

  /// Development preset — verbose logging (matches Swift).
  static LoggingConfiguration get development => LoggingConfiguration(
    enableLocalLogging: true,
    minLogLevel: LogLevel.LOG_LEVEL_DEBUG,
    includeDeviceMetadata: false,
  );

  /// Staging preset — info-level logging (matches Swift).
  static LoggingConfiguration get staging => LoggingConfiguration(
    enableLocalLogging: true,
    minLogLevel: LogLevel.LOG_LEVEL_INFO,
    includeDeviceMetadata: true,
  );

  /// Production preset — warnings + errors only, local logging off
  /// (matches Swift).
  static LoggingConfiguration get production => LoggingConfiguration(
    enableLocalLogging: false,
    minLogLevel: LogLevel.LOG_LEVEL_WARNING,
    includeDeviceMetadata: true,
  );

  /// Preset for an SDK environment. Mirrors Swift
  /// `RALoggingConfiguration.forEnvironment(_:)` (unknown → development).
  static LoggingConfiguration forEnvironment(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        return development;
      case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
        return staging;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return production;
      default:
        return development;
    }
  }
}

/// A pluggable log sink. Implement this to route SDK logs to your own
/// telemetry/file/network destination. Mirrors Swift's `LogDestination`
/// protocol. This is a host-side interface (carries no wire payload) and so
/// stays hand-written rather than moving to the proto contract.
abstract class LogDestination {
  /// Stable identifier for this destination (e.g. `"console"`, `"file"`).
  /// Used to deduplicate registrations.
  String get identifier;

  /// Whether this destination is currently available (e.g. network
  /// reachable, file handle open).
  bool get isAvailable;

  /// Receive a single log record.
  void write(LogEntry entry);

  /// Force-flush any buffered records.
  void flush();
}

/// Default console sink. Mirrors Swift `Logging.printToConsole(_:)` — it is
/// held by [SDKLoggerConfig] (not registered in the destinations list) and
/// invoked only when `enableLocalLogging` is on.
class ConsoleLogDestination implements LogDestination {
  @override
  String get identifier => 'console';

  @override
  bool get isAvailable => true;

  @override
  void write(LogEntry entry) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      entry.timestampUnixMs.toInt(),
    ).toIso8601String();
    // Generated enum names are `LOG_LEVEL_<SEVERITY>`; strip the prefix for a
    // readable console tag (e.g. `DEBUG`).
    final levelStr = entry.level.name.replaceFirst('LOG_LEVEL_', '');

    // ignore: avoid_print
    print('[$timestamp] [$levelStr] [${entry.category}] ${entry.message}');

    if (entry.metadata.isNotEmpty) {
      // ignore: avoid_print
      print('  metadata: ${entry.metadata}');
    }
  }

  @override
  void flush() {
    // print() is unbuffered — nothing to flush.
  }
}

/// Central logging service holding the currently-configured logging
/// configuration + registered destinations. Mirrors Swift's `Logging.shared`:
/// every [SDKLogger] record routes through [log], which applies the min-level
/// gate, suppresses debug records in production, and fans out to the console
/// + registered destinations. C++ logging is configured separately during
/// `DartBridge.initialize()` via `rac_configure_logging`.
class SDKLoggerConfig {
  SDKLoggerConfig._();
  static final SDKLoggerConfig shared = SDKLoggerConfig._();

  LoggingConfiguration _configuration = LoggingConfigurations.defaults;
  final List<LogDestination> _destinations = <LogDestination>[];
  final ConsoleLogDestination _console = ConsoleLogDestination();

  /// SDK environment applied via [applyEnvironmentConfiguration]; null until
  /// `DartBridge.initialize()` runs (Swift reads
  /// `RunAnywhere.currentEnvironment`).
  SDKEnvironment? _environment;

  LoggingConfiguration get configuration => _configuration;
  List<LogDestination> get destinations =>
      List<LogDestination>.unmodifiable(_destinations);

  void configure(LoggingConfiguration config) {
    _configuration = config;
  }

  /// Apply configuration based on SDK environment. Mirrors Swift
  /// `Logging.applyEnvironmentConfiguration(_:)`, called at the top of init
  /// so logging boots with the correct per-environment config.
  void applyEnvironmentConfiguration(SDKEnvironment environment) {
    _environment = environment;
    configure(LoggingConfigurations.forEnvironment(environment));
  }

  void setMinLogLevel(LogLevel level) {
    _configuration = _configuration.deepCopy()..minLogLevel = level;
  }

  void setLocalLoggingEnabled(bool enabled) {
    _configuration = _configuration.deepCopy()..enableLocalLogging = enabled;
  }

  void addDestination(LogDestination destination) {
    if (!_destinations.any((d) => d.identifier == destination.identifier)) {
      _destinations.add(destination);
    }
  }

  void removeDestination(LogDestination destination) {
    _destinations.removeWhere((d) => d.identifier == destination.identifier);
  }

  /// Core logging entry point. Mirrors Swift `Logging.log(level:category:
  /// message:metadata:)`:
  ///   (a) gate on `minLogLevel` from the active configuration,
  ///   (b) never emit debug/trace records in the production environment
  ///       (Swift compiles `SDKLogger.debug` out of release builds via
  ///       `#if DEBUG`; Dart gates on the SDK environment instead),
  ///   (c) print to console only when `enableLocalLogging` is on, then fan
  ///       out to every available registered destination.
  void log({
    required LogLevel level,
    required String category,
    required String message,
    Map<String, dynamic>? metadata,
  }) {
    final config = _configuration;

    if (level.value < config.minLogLevel.value) return;

    if (_environment == SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION &&
        level.value <= LogLevel.LOG_LEVEL_DEBUG.value) {
      return;
    }

    final entry = LogEntry(
      timestampUnixMs: Int64(DateTime.now().millisecondsSinceEpoch),
      level: level,
      category: category,
      message: message,
      metadata: metadata?.entries.map((e) => MapEntry(e.key, '${e.value}')),
    );

    if (config.enableLocalLogging) {
      _console.write(entry);
    }

    for (final destination in _destinations) {
      if (destination.isAvailable) {
        destination.write(entry);
      }
    }
  }
}

/// Centralized logging utility
/// Aligned with iOS: Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift
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
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
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
  void fault(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final enrichedMetadata = metadata ?? <String, dynamic>{};
    if (error != null) {
      enrichedMetadata['error'] = error.toString();
    }
    if (stackTrace != null) {
      enrichedMetadata['stackTrace'] = stackTrace.toString();
    }

    // The public `fault` convenience maps to the generated enum's highest
    // severity, LOG_LEVEL_FATAL.
    _log(LogLevel.LOG_LEVEL_FATAL, message, metadata: enrichedMetadata);
  }

  /// Log a message with a specific level
  void log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    _log(level, message, metadata: metadata);
  }

  // MARK: - Performance Logging

  /// Log performance metrics
  void performance(
    String metric,
    double value, {
    Map<String, dynamic>? metadata,
  }) {
    final enrichedMetadata = metadata ?? <String, dynamic>{};
    enrichedMetadata['metric'] = metric;
    enrichedMetadata['value'] = value;
    enrichedMetadata['type'] = 'performance';

    _log(
      LogLevel.LOG_LEVEL_INFO,
      '$metric: $value',
      metadata: enrichedMetadata,
    );
  }

  // MARK: - Private Methods

  /// Route through the central service (Swift: `Logging.shared.log(...)`),
  /// which applies min-level gating, production debug suppression, and
  /// destination fan-out.
  void _log(LogLevel level, String message, {Map<String, dynamic>? metadata}) {
    SDKLoggerConfig.shared.log(
      level: level,
      category: category,
      message: message,
      metadata: metadata,
    );
  }
}
