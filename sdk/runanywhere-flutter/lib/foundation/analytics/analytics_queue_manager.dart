//
//  analytics_queue_manager.dart
//  RunAnywhere SDK
//
//  Centralized queue management for all analytics events with batching and retry
//
//  Corresponds to iOS SDK's AnalyticsQueueManager.swift

import 'dart:async';
import 'dart:math';

import '../../core/protocols/analytics/analytics_event.dart';
import '../logging/sdk_logger.dart';

/// Telemetry data for sending to backend
class TelemetryData {
  final String eventType;
  final Map<String, dynamic> properties;
  final DateTime timestamp;

  const TelemetryData({
    required this.eventType,
    required this.properties,
    required this.timestamp,
  });
}

/// Protocol for telemetry repository
///
/// Implementations should handle sending events to the backend
abstract class TelemetryRepository {
  /// Track an event with the given type and properties
  Future<void> trackEvent(
    String eventType, {
    required Map<String, dynamic> properties,
  });
}

/// Central queue for all analytics - handles batching and retry logic
class AnalyticsQueueManager {
  // Singleton
  static final AnalyticsQueueManager shared = AnalyticsQueueManager._();

  // Properties
  final List<AnalyticsEvent> _eventQueue = [];
  final int _batchSize = 50;
  final Duration _flushInterval = const Duration(seconds: 30);
  TelemetryRepository? _telemetryRepository;
  final SDKLogger _logger = SDKLogger(category: 'AnalyticsQueue');
  Timer? _flushTimer;
  final int _maxRetries = 3;

  // Private constructor
  AnalyticsQueueManager._() {
    _startFlushTimer();
  }

  /// Initialize with a telemetry repository
  void initialize(TelemetryRepository telemetryRepository) {
    _telemetryRepository = telemetryRepository;
  }

  /// Enqueue a single event
  Future<void> enqueue(AnalyticsEvent event) async {
    _eventQueue.add(event);

    if (_eventQueue.length >= _batchSize) {
      await _flushBatch();
    }
  }

  /// Enqueue multiple events
  Future<void> enqueueBatch(List<AnalyticsEvent> events) async {
    _eventQueue.addAll(events);

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
      _flushBatch();
    });
  }

  Future<void> _flushBatch() async {
    if (_eventQueue.isEmpty) return;

    final batch = _eventQueue.take(_batchSize).toList();
    await _processBatch(batch);
  }

  Future<void> _processBatch(List<AnalyticsEvent> batch) async {
    // For debugging: log analytics events locally
    assert(() {
      for (final event in batch) {
        _logger.debug('Analytics Event: ${event.type}');
      }
      return true;
    }());

    if (_telemetryRepository == null) {
      _logger.error('No telemetry repository configured');
      _eventQueue.removeRange(0, min(batch.length, _eventQueue.length));
      return;
    }

    // Convert to telemetry data
    final telemetryEvents = <TelemetryData>[];
    for (final event in batch) {
      try {
        final properties = event.eventData.toMap();
        telemetryEvents.add(TelemetryData(
          eventType: event.type,
          properties: {'structured_data': properties},
          timestamp: event.timestamp,
        ));
      } catch (e) {
        _logger.error('Failed to serialize event data for telemetry: $e');
      }
    }

    // Send to backend via existing telemetry repository
    var success = false;
    var attempt = 0;

    while (attempt < _maxRetries && !success) {
      try {
        // Send each event through telemetry repository
        for (final telemetryData in telemetryEvents) {
          await _telemetryRepository!.trackEvent(
            telemetryData.eventType,
            properties: telemetryData.properties,
          );
        }

        success = true;
        _eventQueue.removeRange(0, min(batch.length, _eventQueue.length));
      } catch (e) {
        attempt++;
        if (attempt < _maxRetries) {
          // Exponential backoff
          final delay = Duration(seconds: pow(2, attempt).toInt());
          await Future.delayed(delay);
        } else {
          _logger.error('Failed to send batch after $_maxRetries attempts');
          _eventQueue.removeRange(0, min(batch.length, _eventQueue.length));
        }
      }
    }
  }
}
