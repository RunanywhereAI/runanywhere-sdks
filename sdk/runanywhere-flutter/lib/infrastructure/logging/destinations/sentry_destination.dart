import 'package:runanywhere/foundation/logging/models/log_entry.dart';
import 'package:runanywhere/foundation/logging/models/log_level.dart';
import 'package:runanywhere/infrastructure/logging/protocol/log_destination.dart';

/// Log destination that sends logs to Sentry for crash reporting and error tracking.
/// Only logs at warning level and above are sent to Sentry.
///
/// This is a stub implementation that can be connected to sentry_flutter package later.
/// The implementation matches iOS SentryDestination pattern from:
/// Infrastructure/Logging/Services/Destinations/SentryDestination.swift
///
/// Usage:
/// ```dart
/// // Initialize Sentry first (when sentry_flutter is added)
/// // await SentryFlutter.init((options) { ... });
///
/// // Then add the destination
/// final sentryDest = SentryDestination();
/// loggingService.addDestination(sentryDest);
/// ```
class SentryDestination extends LogDestination {
  // MARK: - LogDestination Implementation

  @override
  final String identifier = 'com.runanywhere.logging.sentry';

  @override
  final String name = 'Sentry';

  /// Minimum log level to send to Sentry (warning and above)
  final LogLevel minSentryLevel;

  /// DSN for Sentry project (when configured)
  final String? dsn;

  /// Environment name (e.g., 'development', 'production')
  final String? environment;

  /// Whether Sentry has been initialized
  bool _isInitialized = false;

  /// Breadcrumb buffer for when Sentry is not yet initialized
  final List<_BreadcrumbData> _breadcrumbBuffer = [];

  /// Maximum breadcrumbs to buffer
  static const int _maxBreadcrumbBuffer = 100;

  // MARK: - Initialization

  SentryDestination({
    this.dsn,
    this.environment,
    this.minSentryLevel = LogLevel.warning,
  });

  @override
  bool get isAvailable => _isInitialized;

  /// Initialize Sentry destination (to be called when Sentry is configured)
  ///
  /// This method should be called after sentry_flutter is initialized.
  /// For now, it's a placeholder for future integration.
  void initialize() {
    if (dsn == null || dsn!.isEmpty) {
      // Sentry not configured, mark as initialized but won't send data
      _isInitialized = true;
      return;
    }

    // TODO: When sentry_flutter is added, initialize here:
    // await SentryFlutter.init((options) {
    //   options.dsn = dsn;
    //   options.environment = environment ?? 'production';
    //   options.tracesSampleRate = 1.0;
    // });

    _isInitialized = true;

    // Flush buffered breadcrumbs
    _flushBreadcrumbBuffer();
  }

  /// Mark as uninitialized (for cleanup)
  void shutdown() {
    _isInitialized = false;
    _breadcrumbBuffer.clear();
  }

  // MARK: - LogDestination Operations

  @override
  void write(LogEntry entry) {
    // Only send warning level and above to Sentry
    if (entry.level < minSentryLevel) {
      return;
    }

    // Add as breadcrumb for context trail
    _addBreadcrumb(entry);

    // For error and fault levels, capture as Sentry event
    if (entry.level >= LogLevel.error) {
      _captureEvent(entry);
    }
  }

  @override
  void flush() {
    if (!isAvailable) return;

    // TODO: When sentry_flutter is added, flush pending events:
    // await Sentry.flush(timeout: Duration(seconds: 2));
  }

  // MARK: - Private Helpers

  void _addBreadcrumb(LogEntry entry) {
    final breadcrumbData = _BreadcrumbData(
      level: entry.level,
      category: entry.category,
      message: entry.message,
      timestamp: entry.timestamp,
      metadata: entry.metadata,
    );

    if (!isAvailable) {
      // Buffer breadcrumbs until Sentry is initialized
      if (_breadcrumbBuffer.length >= _maxBreadcrumbBuffer) {
        _breadcrumbBuffer.removeAt(0);
      }
      _breadcrumbBuffer.add(breadcrumbData);
      return;
    }

    // TODO: When sentry_flutter is added, add breadcrumb:
    // Sentry.addBreadcrumb(
    //   Breadcrumb(
    //     message: entry.message,
    //     category: entry.category,
    //     level: _convertToSentryLevel(entry.level),
    //     timestamp: entry.timestamp,
    //     data: entry.metadata,
    //   ),
    // );
  }

  void _captureEvent(LogEntry entry) {
    if (!isAvailable) return;

    // TODO: When sentry_flutter is added, capture event:
    // final event = SentryEvent(
    //   message: SentryMessage(entry.message),
    //   level: _convertToSentryLevel(entry.level),
    //   timestamp: entry.timestamp,
    //   tags: {
    //     'category': entry.category,
    //     'log_level': entry.level.toString(),
    //   },
    // );
    //
    // // Add metadata as extra context
    // if (entry.metadata != null) {
    //   event = event.copyWith(extra: entry.metadata);
    // }
    //
    // // Add device info if available
    // if (entry.deviceInfo != null) {
    //   final extra = {
    //     ...?event.extra,
    //     'device_model': entry.deviceInfo!.model,
    //     'os_version': entry.deviceInfo!.osVersion,
    //     'architecture': entry.deviceInfo!.architecture,
    //     'total_memory': entry.deviceInfo!.totalMemory,
    //     'available_memory': entry.deviceInfo!.availableMemory,
    //     'has_neural_engine': entry.deviceInfo!.hasNeuralEngine,
    //     if (entry.deviceInfo!.gpuFamily != null)
    //       'gpu_family': entry.deviceInfo!.gpuFamily,
    //   };
    //   event = event.copyWith(extra: extra);
    // }
    //
    // Sentry.captureEvent(event);
  }

  void _flushBreadcrumbBuffer() {
    if (_breadcrumbBuffer.isEmpty) return;

    // Add buffered breadcrumbs to Sentry
    // ignore: unused_local_variable
    for (final breadcrumb in _breadcrumbBuffer) {
      // TODO: When sentry_flutter is added, add buffered breadcrumbs
      // Sentry.addBreadcrumb(
      //   Breadcrumb(
      //     message: breadcrumb.message,
      //     category: breadcrumb.category,
      //     level: _convertToSentryLevel(breadcrumb.level),
      //     timestamp: breadcrumb.timestamp,
      //     data: breadcrumb.metadata,
      //   ),
      // );
    }

    _breadcrumbBuffer.clear();
  }

  /// Convert RunAnywhere LogLevel to Sentry level
  ///
  /// When sentry_flutter is added, this will convert to SentryLevel:
  /// - LogLevel.debug -> SentryLevel.debug
  /// - LogLevel.info -> SentryLevel.info
  /// - LogLevel.warning -> SentryLevel.warning
  /// - LogLevel.error -> SentryLevel.error
  /// - LogLevel.fault -> SentryLevel.fatal
  // ignore: unused_element
  String _convertToSentryLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'debug';
      case LogLevel.info:
        return 'info';
      case LogLevel.warning:
        return 'warning';
      case LogLevel.error:
        return 'error';
      case LogLevel.fault:
        return 'fatal';
    }
  }
}

/// Internal breadcrumb data for buffering
class _BreadcrumbData {
  final LogLevel level;
  final String category;
  final String message;
  final DateTime timestamp;
  final Map<String, String>? metadata;

  _BreadcrumbData({
    required this.level,
    required this.category,
    required this.message,
    required this.timestamp,
    this.metadata,
  });
}
