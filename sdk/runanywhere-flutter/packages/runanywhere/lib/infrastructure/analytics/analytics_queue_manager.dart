//
//  analytics_queue_manager.dart
//  RunAnywhere SDK
//
//  Centralized queue management for all analytics events with batching and retry.
//
//  Corresponds to iOS SDK's AnalyticsQueueManager.swift
//

import 'dart:async';
import 'dart:math';

import 'package:runanywhere/core/protocols/analytics/analytics_event.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/analytics/constants/analytics_constants.dart';
import 'package:runanywhere/infrastructure/analytics/models/domain/telemetry_data.dart';
import 'package:runanywhere/infrastructure/analytics/repositories/telemetry_repository.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// Internal wrapper to unify SDKEvent and AnalyticsEvent for the queue.
class _QueuedEvent {
  final String type;
  final Map<String, String> properties;
  final DateTime timestamp;

  _QueuedEvent({
    required this.type,
    required this.properties,
    required this.timestamp,
  });

  factory _QueuedEvent.fromSDKEvent(SDKEvent event) {
    return _QueuedEvent(
      type: event.type,
      properties: event.properties,
      timestamp: event.timestamp,
    );
  }

  factory _QueuedEvent.fromAnalyticsEvent(AnalyticsEvent event) {
    return _QueuedEvent(
      type: event.type,
      properties: event.eventData.toMap().map(
            (key, value) => MapEntry(key, value.toString()),
          ),
      timestamp: event.timestamp,
    );
  }
}

/// Central queue for all analytics events.
///
/// Handles batching, local persistence, and backend sync.
/// Matches iOS SDK's AnalyticsQueueManager actor pattern.
class AnalyticsQueueManager {
  // Singleton
  static final AnalyticsQueueManager shared = AnalyticsQueueManager._();

  // Properties
  final List<_QueuedEvent> _eventQueue = [];
  final int _batchSize = AnalyticsConstants.telemetryBatchSize;
  final Duration _flushInterval = AnalyticsConstants.flushInterval;
  TelemetryRepository? _telemetryRepository;
  final SDKLogger _logger = SDKLogger(category: 'AnalyticsQueue');
  Timer? _flushTimer;
  final int _maxRetries = AnalyticsConstants.maxRetryAttempts;

  // Private constructor
  AnalyticsQueueManager._() {
    _startFlushTimer();
  }

  /// Initialize with a telemetry repository.
  /// Call this during SDK startup to enable analytics persistence.
  void initialize({required TelemetryRepository telemetryRepository}) {
    _telemetryRepository = telemetryRepository;
    _logger.info('AnalyticsQueueManager initialized with TelemetryRepository');
  }

  /// Check if the queue manager has been initialized
  bool get isInitialized => _telemetryRepository != null;

  /// Enqueue an SDK event for analytics processing (sync, fire-and-forget).
  void enqueue(SDKEvent event) {
    _eventQueue.add(_QueuedEvent.fromSDKEvent(event));

    if (_eventQueue.length >= _batchSize) {
      unawaited(_flushBatch());
    }
  }

  /// Enqueue an analytics event for analytics processing (sync, fire-and-forget).
  void enqueueAnalyticsEvent(AnalyticsEvent event) {
    _eventQueue.add(_QueuedEvent.fromAnalyticsEvent(event));

    if (_eventQueue.length >= _batchSize) {
      unawaited(_flushBatch());
    }
  }

  /// Enqueue an SDK event for analytics processing (async).
  Future<void> enqueueAsync(SDKEvent event) async {
    _eventQueue.add(_QueuedEvent.fromSDKEvent(event));

    if (_eventQueue.length >= _batchSize) {
      await _flushBatch();
    }
  }

  /// Enqueue multiple SDK events
  Future<void> enqueueBatch(List<SDKEvent> events) async {
    _eventQueue.addAll(events.map(_QueuedEvent.fromSDKEvent));

    if (_eventQueue.length >= _batchSize) {
      await _flushBatch();
    }
  }

  /// Enqueue multiple analytics events
  Future<void> enqueueAnalyticsEventBatch(List<AnalyticsEvent> events) async {
    _eventQueue.addAll(events.map(_QueuedEvent.fromAnalyticsEvent));

    if (_eventQueue.length >= _batchSize) {
      await _flushBatch();
    }
  }

  /// Force flush all pending events
  Future<void> flush() async {
    await _flushBatch();
  }

  /// Dispose of the queue manager
  void dispose() {
    _flushTimer?.cancel();
  }

  // Private methods

  void _startFlushTimer() {
    _flushTimer = Timer.periodic(_flushInterval, (_) {
      unawaited(_flushBatch());
    });
  }

  Future<void> _flushBatch() async {
    if (_eventQueue.isEmpty) return;

    final batch = _eventQueue.take(_batchSize).toList();
    await _processBatch(batch);
  }

  Future<void> _processBatch(List<_QueuedEvent> batch) async {
    if (_telemetryRepository == null) {
      _logger.warning(
          'No telemetry repository configured - events will be dropped');
      _eventQueue.removeRange(0, min(batch.length, _eventQueue.length));
      return;
    }

    // Convert to TelemetryData
    final telemetryEvents = <TelemetryData>[];
    for (final event in batch) {
      telemetryEvents.add(TelemetryData(
        eventType: event.type,
        properties: event.properties,
        timestamp: event.timestamp,
      ));
    }

    var success = false;
    var attempt = 0;

    while (attempt < _maxRetries && !success) {
      try {
        // Store each event locally
        for (final telemetryData in telemetryEvents) {
          await _telemetryRepository!.trackEventWithType(
            telemetryData.eventType,
            properties: Map<String, String>.from(telemetryData.properties),
          );
        }

        success = true;
        _eventQueue.removeRange(0, min(batch.length, _eventQueue.length));
      } catch (e) {
        attempt++;
        _logger.warning(
            'Failed to process batch (attempt $attempt/$_maxRetries): $e');
        if (attempt < _maxRetries) {
          // Exponential backoff
          final delay = Duration(seconds: pow(2, attempt).toInt());
          await Future<void>.delayed(delay);
        } else {
          _logger.error(
              'Failed to send batch after $_maxRetries attempts, stored locally');
          _eventQueue.removeRange(0, min(batch.length, _eventQueue.length));
        }
      }
    }
  }
}
