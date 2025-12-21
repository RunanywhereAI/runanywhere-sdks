import 'dart:async';

import 'package:runanywhere/foundation/logging/models/log_entry.dart';
import 'package:runanywhere/foundation/logging/models/logging_configuration.dart';

/// Manages batching of log entries for remote submission
///
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Services/LogBatcher.swift
class LogBatcher {
  /// Log entries pending submission
  final List<LogEntry> _pendingLogs = [];

  /// Configuration for batching behavior
  LoggingConfiguration _configuration;

  /// Timer for periodic batch submission
  Timer? _batchTimer;

  /// Callback for when a batch is ready
  final void Function(List<LogEntry>) onBatchReady;

  LogBatcher({
    required LoggingConfiguration configuration,
    required this.onBatchReady,
  }) : _configuration = configuration {
    _startBatchTimer();
  }

  /// Add a log entry to the batch
  void add(LogEntry entry) {
    _pendingLogs.add(entry);

    if (_pendingLogs.length >= _configuration.batchSize) {
      _flushBatch();
    }
  }

  /// Force flush all pending logs
  void flush() {
    _flushBatch();
  }

  /// Update configuration and restart timer if needed
  void updateConfiguration(LoggingConfiguration newConfig) {
    _configuration = newConfig;
    _stopBatchTimer();
    if (newConfig.enableRemoteLogging) {
      _startBatchTimer();
    }
  }

  /// Dispose of resources
  void dispose() {
    _stopBatchTimer();
    _flushBatch();
  }

  // MARK: - Private Methods

  void _flushBatch() {
    if (_pendingLogs.isEmpty) return;

    final logsToSend = List<LogEntry>.from(_pendingLogs);
    _pendingLogs.clear();

    // Call the batch ready handler
    onBatchReady(logsToSend);
  }

  void _startBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = Timer.periodic(
      Duration(seconds: _configuration.batchInterval.toInt()),
      (_) => flush(),
    );
  }

  void _stopBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = null;
  }
}
