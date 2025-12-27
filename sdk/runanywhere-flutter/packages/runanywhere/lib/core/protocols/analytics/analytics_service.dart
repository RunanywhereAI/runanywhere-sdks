import 'dart:async';

import 'package:runanywhere/core/protocols/analytics/analytics_event.dart';
import 'package:runanywhere/core/protocols/analytics/analytics_metrics.dart';
import 'package:runanywhere/core/protocols/analytics/session_metadata.dart';

/// Base protocol for all analytics services in the SDK
///
/// Corresponds to iOS SDK's AnalyticsService protocol in UnifiedAnalytics.swift
///
/// Note: In Dart, we use abstract classes instead of Swift protocols with
/// associated types. Implementations can use generics if needed for type safety.
abstract class AnalyticsServiceProtocol<TEvent extends AnalyticsEvent,
    TMetrics extends AnalyticsMetrics> {
  // Event tracking

  /// Track a single event
  Future<void> track(TEvent event);

  /// Track multiple events in a batch
  Future<void> trackBatch(List<TEvent> events);

  // Metrics

  /// Get current metrics
  Future<TMetrics> getMetrics();

  /// Clear metrics older than the specified date
  Future<void> clearMetrics({required DateTime olderThan});

  // Session management

  /// Start a new session with the given metadata
  /// Returns the session ID
  Future<String> startSession(SessionMetadata metadata);

  /// End a session by its ID
  Future<void> endSession(String sessionId);

  // Health

  /// Check if the analytics service is healthy
  Future<bool> isHealthy();
}

/// Default implementation of AnalyticsService.
/// Matches iOS AnalyticsQueueManager from Infrastructure/Analytics/Services/AnalyticsQueueManager.swift
class DefaultAnalyticsService
    implements AnalyticsServiceProtocol<AnalyticsEvent, AnalyticsMetrics> {
  final List<AnalyticsEvent> _eventQueue = [];
  SimpleAnalyticsMetrics _metrics = SimpleAnalyticsMetrics.initial();
  final Map<String, SessionMetadata> _sessions = {};

  /// Configuration matching iOS defaults
  final int _batchSize = 50;
  final Duration _flushInterval = const Duration(seconds: 30);
  final int _maxRetries = 3;

  Timer? _flushTimer;
  bool _isDisposed = false;

  DefaultAnalyticsService() {
    _startFlushTimer();
  }

  void _startFlushTimer() {
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushBatch());
  }

  @override
  Future<void> track(AnalyticsEvent event) async {
    if (_isDisposed) return;

    _eventQueue.add(event);
    _metrics = _metrics.copyWith(
      totalEvents: _metrics.totalEvents + 1,
      lastEventTime: DateTime.now(),
    );

    if (_eventQueue.length >= _batchSize) {
      await _flushBatch();
    }
  }

  @override
  Future<void> trackBatch(List<AnalyticsEvent> events) async {
    if (_isDisposed) return;

    _eventQueue.addAll(events);
    _metrics = _metrics.copyWith(
      totalEvents: _metrics.totalEvents + events.length,
      lastEventTime: DateTime.now(),
    );

    if (_eventQueue.length >= _batchSize) {
      await _flushBatch();
    }
  }

  @override
  Future<AnalyticsMetrics> getMetrics() async => _metrics;

  @override
  Future<void> clearMetrics({required DateTime olderThan}) async {
    _eventQueue.removeWhere((event) => event.timestamp.isBefore(olderThan));
    _metrics = SimpleAnalyticsMetrics(
      totalEvents: _eventQueue.length,
      startTime: _metrics.startTime,
      lastEventTime: _eventQueue.isNotEmpty ? _eventQueue.last.timestamp : null,
    );
  }

  @override
  Future<String> startSession(SessionMetadata metadata) async {
    _sessions[metadata.id] = metadata;
    return metadata.id;
  }

  @override
  Future<void> endSession(String sessionId) async {
    _sessions.remove(sessionId);
  }

  @override
  Future<bool> isHealthy() async => !_isDisposed;

  /// Force flush all pending events
  Future<void> flush() async {
    await _flushBatch();
  }

  Future<void> _flushBatch() async {
    if (_eventQueue.isEmpty) return;

    final batch = _eventQueue.take(_batchSize).toList();

    // Process batch with retry logic matching iOS
    var success = false;
    var attempt = 0;

    while (attempt < _maxRetries && !success) {
      try {
        // In a full implementation, this would send to the backend
        // For now, just remove processed events
        await _processBatch(batch);
        success = true;

        // Remove processed events
        _eventQueue.removeRange(0, batch.length.clamp(0, _eventQueue.length));
      } catch (_) {
        attempt++;
        if (attempt < _maxRetries) {
          // Exponential backoff matching iOS
          final delay = Duration(seconds: (1 << attempt));
          await Future<void>.delayed(delay);
        } else {
          // Remove events after max retries to prevent queue growth
          _eventQueue.removeRange(0, batch.length.clamp(0, _eventQueue.length));
        }
      }
    }
  }

  Future<void> _processBatch(List<AnalyticsEvent> batch) async {
    // In a full implementation, this would:
    // 1. Store events locally
    // 2. Send to backend via TelemetryRepository
    // For now, this is a no-op as the events are tracked in memory
  }

  /// Get all tracked events (for testing)
  List<AnalyticsEvent> get events => List.unmodifiable(_eventQueue);

  /// Get all active sessions (for testing)
  Map<String, SessionMetadata> get sessions => Map.unmodifiable(_sessions);

  /// Dispose resources
  void dispose() {
    _isDisposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}
